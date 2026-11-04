import Foundation
import Observation
import NookCore

struct AgentQuestion: Identifiable {
    let id: UUID
    let text: String
    let options: [String]

    init(id: UUID = UUID(), text: String, options: [String]) {
        self.id = id
        self.text = text
        self.options = options
    }
}

/// What happened to a draft card. Cards stay in the conversation with their outcome.
enum AgentDraftState: String, Codable {
    case pending
    case saved
    case discarded
    /// A newer draft from the assistant took its place.
    case replaced
    case undone
}

/// One item of the conversation, in the order it happened.
struct AgentEntry: Identifiable {
    enum Kind {
        case user(String, imageCount: Int)
        case assistant(String)
        case question(AgentQuestion)
        case draft(AgentPlan)
        case notice(String, isError: Bool)
    }

    let id = UUID()
    let kind: Kind
}

/// Receives six explicit record capabilities, never AppStore, VaultStore or arbitrary storage.
@MainActor @Observable
final class AgentSession {
    private(set) var entries: [AgentEntry] = []
    private(set) var draftStates: [UUID: AgentDraftState] = [:]
    /// Extra outcome text for a saved draft, such as reminder scheduling.
    private(set) var draftNotes: [UUID: String] = [:]
    private(set) var answers: [UUID: String] = [:]
    /// The draft waiting for confirmation.
    private(set) var plan: AgentPlan?
    /// The question waiting for an answer.
    private(set) var question: AgentQuestion?
    /// The most recently saved draft, while it can still be undone.
    private(set) var undoablePlanID: UUID?
    private(set) var isWorking = false
    private(set) var isUpdatingReminders = false
    private var undoPlan: AgentPlan?
    private var messages: [AIMessage] = []
    private var known: [AgentRecord] = []
    /// The conversation came from storage, so records seen before the restart may have changed.
    private var resumed = false
    private var requestTask: Task<Void, Never>?
    private var generation = 0
    private let read: () -> [AgentRecord]
    private let commit: (AgentPlan) throws -> Void
    private let currency: () -> String
    private let reminderFeedback: () async -> String
    private let history: AgentHistoryStorage?

    /// With `history`, the conversation is restored now and saved after every change.
    init(read: @escaping () -> [AgentRecord], commit: @escaping (AgentPlan) throws -> Void, currency: @escaping () -> String,
         reminderFeedback: @escaping () async -> String = { "" }, history: AgentHistoryStorage? = nil) {
        self.read = read; self.commit = commit; self.currency = currency; self.reminderFeedback = reminderFeedback
        self.history = history
        if let data = history?.load() { restore(from: data) }
    }

    var isEmpty: Bool { entries.isEmpty }

    func state(of plan: AgentPlan) -> AgentDraftState {
        draftStates[plan.id] ?? .pending
    }

    /// Starts over: forgets the conversation, never the saved records.
    func reset() {
        guard !isWorking else { return }
        generation += 1
        requestTask?.cancel(); requestTask = nil
        entries = []; draftStates = [:]; draftNotes = [:]; answers = [:]
        plan = nil; question = nil; undoPlan = nil; undoablePlanID = nil
        messages = []; known = []; resumed = false
        history?.save(nil)
    }

    /// Answers the open question with one of its options.
    func answer(_ question: AgentQuestion, with option: String, configuration: AIConfiguration, key: String) {
        guard !isWorking else { return }
        answers[question.id] = option
        send(option, images: [], configuration: configuration, key: key)
    }

    func send(_ text: String, images: [AIImage], configuration: AIConfiguration, key: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if images.isEmpty && ["取消", "算了", "不要了", "取消刚才的操作", "cancel"].contains(trimmed.lowercased()) {
            entries.append(AgentEntry(kind: .user(trimmed, imageCount: 0)))
            cancel()
            return
        }
        guard !isWorking, !trimmed.isEmpty || !images.isEmpty else { return }
        generation += 1
        let ticket = generation
        if let question, answers[question.id] == nil {
            answers[question.id] = trimmed
        }
        question = nil
        entries.append(AgentEntry(kind: .user(trimmed, imageCount: images.count)))
        messages.append(AIMessage(role: "user", text: text, images: images))
        saveHistory()
        isWorking = true
        requestTask = Task {
            defer { if ticket == generation { isWorking = false; requestTask = nil; saveHistory() } }
            do {
                let client = AIClient(configuration: configuration, apiKey: key)
                for _ in 0..<6 {
                    try Task.checkCancellation()
                    var system = AgentTools.instructions(now: Date(), timeZone: .current, currency: currency())
                    if let plan { system += "\n当前未保存草稿（用户补充时替换它，不要新增重复内容）：\(try JSONValue.from(plan).json)" }
                    if resumed { system += "\n这段对话是 App 重启后从本机恢复的，之前查到的记录可能已变化。修改或删除已有记录前，先用 search_records 重新查找。" }
                    let response = try await client.response(system: system, messages: messages)
                    guard ticket == generation else { return }
                    messages.append(AIMessage(role: "assistant", text: response.text, calls: response.calls, providerItems: response.providerItems))
                    let reply = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !reply.isEmpty { entries.append(AgentEntry(kind: .assistant(reply))) }
                    if response.calls.isEmpty { return }
                    var shouldReturn = false
                    for call in response.calls {
                        let output: String
                        do {
                            switch call.name {
                            case "search_records": output = try search(call.arguments).json
                            case "ask_user":
                                guard let text = call.arguments["question"]?.string, !text.isEmpty else { throw AgentPlanError.invalid("question") }
                                let asked = AgentQuestion(text: text, options: Array((call.arguments["options"]?.array ?? []).compactMap(\.string).prefix(5)))
                                question = asked
                                entries.append(AgentEntry(kind: .question(asked)))
                                output = "Question displayed. No changes saved. Await the user's answer."; shouldReturn = true
                            case "prepare_actions":
                                guard let values = call.arguments["actions"] else { throw AgentPlanError.invalid("actions") }
                                let actions = try values.decoded([AgentAction].self)
                                guard actions.allSatisfy({ action in action.operation == .create || known.contains { $0.kind == action.kind && $0.id == action.id } }) else { throw AgentPlanError.missingRecord }
                                let draft = try AgentPlanner.prepare(actions, records: read(),
                                    summary: call.arguments["summary"]?.string ?? "Review changes", currency: currency())
                                if let previous = plan { draftStates[previous.id] = .replaced }
                                plan = draft; question = nil
                                draftStates[draft.id] = .pending
                                entries.append(AgentEntry(kind: .draft(draft)))
                                output = "Draft prepared for confirmation. Nothing saved yet."; shouldReturn = true
                            default: throw AgentPlanError.invalid("unregistered tool")
                            }
                        } catch {
                            output = "Tool rejected: \(error.localizedDescription). Correct the arguments or ask the user. Nothing saved."
                        }
                        messages.append(AIMessage(role: "tool", text: output, toolCallID: call.id, toolName: call.name))
                    }
                    if shouldReturn { return }
                }
                throw AgentPlanError.invalid("too many steps; please narrow the request")
            } catch is CancellationError {
                if ticket == generation { notice(String(localized: "Cancelled. Nothing saved."), isError: false) }
            } catch {
                if ticket == generation { notice(Self.message(for: error), isError: true) }
            }
        }
    }

    private func search(_ args: JSONValue) throws -> JSONValue {
        guard let name = args["kind"]?.string, let kind = AgentRecordKind(rawValue: name) else { throw AgentPlanError.invalid("record type") }
        let query = args["query"]?.string ?? ""
        let from = args["from"]?.string.flatMap(RFC3339.date)
        let to = args["to"]?.string.flatMap(RFC3339.date)
        if let from, let to, to <= from { throw AgentPlanError.invalid("search date range") }
        if args["from"] != nil && from == nil || args["to"] != nil && to == nil { throw AgentPlanError.invalid("RFC3339 search dates") }
        let matches = read().filter { record in
            guard record.kind == kind else { return false }
            if !query.isEmpty, !record.data.json.localizedStandardContains(query) { return false }
            if from != nil || to != nil {
                let date = ["start", "dueAt", "occurred_at", "start_date", "date"].compactMap { key -> Date? in
                    guard let s = record.data[key]?.string else { return nil }
                    return RFC3339.date(from: s) ?? LocalDate(isoString: s)?.startDate(in: .current)
                }.first
                // A recurring series is a candidate if it has an occurrence in the requested range.
                if kind == .event, let event = try? record.data.decoded(ScheduleEvent.self), event.recurrence != nil {
                    let range = DateInterval(start: from ?? Date(), end: to ?? (from ?? Date()).addingTimeInterval(366 * 86400))
                    return !event.occurrences(in: range).isEmpty
                }
                guard let date, from.map({ date >= $0 }) ?? true, to.map({ date < $0 }) ?? true else { return false }
            }
            return true
        }
        let page = Array(matches.prefix(20))
        for record in page {
            known.removeAll { $0.kind == record.kind && $0.id == record.id }; known.append(record)
        }
        return .object(["records": try .from(page), "more": .bool(matches.count > page.count)])
    }

    func confirm() {
        guard !isWorking, let plan else { return }
        do {
            try commit(plan)
        } catch {
            notice(Self.message(for: error), isError: true)
            saveHistory()
            return
        }
        // Undo starts from what was actually stored, which can differ in form from the draft
        // (normalized dates and ids), so its conflict check compares like with like.
        let stored = read()
        undoPlan = AgentPlan(summary: String(localized: "Undo last action"), mutations: plan.mutations.map { mutation in
            AgentMutation(
                kind: mutation.kind,
                id: mutation.id,
                before: stored.first { $0.kind == mutation.kind && $0.id == mutation.id }?.data,
                after: mutation.before
            )
        })
        undoablePlanID = plan.id
        draftStates[plan.id] = .saved
        for mutation in plan.mutations {
            known.removeAll { $0.kind == mutation.kind && $0.id == mutation.id }
            if let after = stored.first(where: { $0.kind == mutation.kind && $0.id == mutation.id }) { known.append(after) }
        }
        messages.append(AIMessage(role: "user", text: "客户端确认已成功保存以下操作：\((try? JSONValue.from(plan).json) ?? plan.summary)。后续修改这些记录要使用真实ID进行update。"))
        self.plan = nil
        let needsReminder = plan.mutations.contains { m in
            let key = m.kind == .event ? "reminder_minutes" : m.kind == .task ? "reminderMinutes" : "reminder"
            return [.event, .task, .anniversary].contains(m.kind) && m.after?[key] != nil && m.after?[key] != .null
        }
        saveHistory()
        if needsReminder {
            isWorking = true; isUpdatingReminders = true
            let planID = plan.id
            Task {
                let feedback = await reminderFeedback()
                if !feedback.isEmpty { draftNotes[planID] = feedback }
                isWorking = false; isUpdatingReminders = false
                saveHistory()
            }
        }
    }

    func discard() {
        guard let plan else { return }
        draftStates[plan.id] = .discarded
        self.plan = nil
        messages.append(AIMessage(role: "user", text: "用户已放弃当前草稿，尚未保存。后续不要自动恢复或执行它。"))
        saveHistory()
    }

    func undo() {
        guard !isWorking, let undoPlan, let planID = undoablePlanID else { return }
        do {
            try commit(undoPlan)
        } catch AgentPlanError.conflict {
            notice(String(localized: "This record was edited after it was saved, so the change can't be undone automatically. Edit it directly instead."), isError: true)
            self.undoPlan = nil; undoablePlanID = nil
            saveHistory()
            return
        } catch {
            notice(Self.message(for: error), isError: true)
            saveHistory()
            return
        }
        self.undoPlan = nil; undoablePlanID = nil
        draftStates[planID] = .undone
        known = []
        messages.append(AIMessage(role: "user", text: "客户端已撤销刚才的操作，请勿认为其仍然有效。"))
        saveHistory()
    }

    /// Stops the request in flight and drops the pending draft.
    func cancel() {
        // Confirmation commits synchronously. Waiting for notification feedback is not an
        // unsaved request and must never be reported as cancelled or rolled back.
        if isUpdatingReminders { return }
        let wasWorking = isWorking
        generation += 1; requestTask?.cancel(); requestTask = nil; isWorking = false
        if let plan { draftStates[plan.id] = .discarded }
        let hadDraft = plan != nil
        plan = nil; question = nil
        if wasWorking || hadDraft { notice(String(localized: "Cancelled. Nothing saved."), isError: false) }
        messages.append(AIMessage(role: "user", text: "用户已取消当前草稿，尚未保存。后续不要自动恢复或执行它。"))
        saveHistory()
    }

    // MARK: - History

    /// Writes the conversation to local storage, when the session has one.
    func saveHistory() {
        guard let history else { return }
        guard !entries.isEmpty else {
            history.save(nil)
            return
        }
        guard let data = try? NookJSON.makeEncoder().encode(snapshot()) else { return }
        history.save(data)
    }

    private func snapshot() -> AgentHistorySnapshot {
        let kept = Array(entries.suffix(AgentHistorySnapshot.entryLimit))
        var planIDs = Set<UUID>()
        var questionIDs = Set<UUID>()
        let stored = kept.map { entry -> AgentHistorySnapshot.StoredEntry in
            switch entry.kind {
            case .user(let text, let imageCount):
                return .init(kind: .user, text: text, imageCount: imageCount)
            case .assistant(let text):
                return .init(kind: .assistant, text: text)
            case .question(let question):
                questionIDs.insert(question.id)
                return .init(kind: .question, text: question.text, questionID: question.id, options: question.options)
            case .draft(let plan):
                planIDs.insert(plan.id)
                return .init(kind: .draft, plan: plan)
            case .notice(let text, let isError):
                return .init(kind: .notice, text: text, isError: isError)
            }
        }
        return AgentHistorySnapshot(
            savedAt: Date(),
            entries: stored,
            draftStates: draftStates.filter { planIDs.contains($0.key) },
            draftNotes: draftNotes.filter { planIDs.contains($0.key) },
            answers: answers.filter { questionIDs.contains($0.key) },
            pendingPlanID: plan.flatMap { planIDs.contains($0.id) ? $0.id : nil },
            openQuestionID: question.flatMap { questionIDs.contains($0.id) ? $0.id : nil },
            undoPlan: undoablePlanID.flatMap { planIDs.contains($0) ? undoPlan : nil },
            undoablePlanID: undoablePlanID.flatMap { planIDs.contains($0) ? $0 : nil },
            messages: AgentHistorySnapshot.trimmed(messages, limit: AgentHistorySnapshot.messageLimit).map { AgentHistorySnapshot.StoredMessage($0) }
        )
    }

    /// Restores a saved conversation. Unreadable or newer data is ignored, never fatal.
    private func restore(from data: Data) {
        guard let snapshot = try? NookJSON.makeDecoder().decode(AgentHistorySnapshot.self, from: data),
              snapshot.version <= AgentHistorySnapshot.currentVersion else { return }
        var restored: [AgentEntry] = []
        var plans: [UUID: AgentPlan] = [:]
        var questions: [UUID: AgentQuestion] = [:]
        for stored in snapshot.entries {
            switch stored.kind {
            case .user:
                restored.append(AgentEntry(kind: .user(stored.text ?? "", imageCount: stored.imageCount ?? 0)))
            case .assistant:
                if let text = stored.text { restored.append(AgentEntry(kind: .assistant(text))) }
            case .question:
                guard let text = stored.text, let id = stored.questionID else { continue }
                let question = AgentQuestion(id: id, text: text, options: stored.options ?? [])
                questions[id] = question
                restored.append(AgentEntry(kind: .question(question)))
            case .draft:
                guard let plan = stored.plan else { continue }
                plans[plan.id] = plan
                restored.append(AgentEntry(kind: .draft(plan)))
            case .notice:
                if let text = stored.text { restored.append(AgentEntry(kind: .notice(text, isError: stored.isError ?? false))) }
            }
        }
        entries = restored
        draftStates = snapshot.draftStates
        draftNotes = snapshot.draftNotes
        answers = snapshot.answers
        plan = snapshot.pendingPlanID.flatMap { id in draftStates[id] == .pending ? plans[id] : nil }
        question = snapshot.openQuestionID.flatMap { id in answers[id] == nil ? questions[id] : nil }
        if let id = snapshot.undoablePlanID, draftStates[id] == .saved, let inverse = snapshot.undoPlan {
            undoablePlanID = id
            undoPlan = inverse
        }
        messages = snapshot.messages.map(\.message)
        resumed = !messages.isEmpty
    }

    private func notice(_ text: String, isError: Bool) {
        entries.append(AgentEntry(kind: .notice(text, isError: isError)))
    }

    /// Readable messages for planner errors; other errors already describe themselves.
    static func message(for error: any Error) -> String {
        switch error as? AgentPlanError {
        case .conflict?:
            String(localized: "This record changed after the draft was prepared. Ask again to get an updated draft.")
        case .missingRecord?:
            String(localized: "The record wasn't found. Ask again and name it more precisely.")
        case .scopeRequired?:
            String(localized: "Choose this occurrence, this and future occurrences, or the entire series.")
        case .invalid(let detail)?:
            String(localized: "The assistant's draft was incomplete (\(detail)). Try rephrasing the request.")
        case nil:
            error.localizedDescription
        }
    }
}
