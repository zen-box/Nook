import Foundation
import Observation
import NookCore

struct AgentBubble: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
}
struct AgentQuestion: Identifiable {
    let id = UUID()
    let text: String
    let options: [String]
}

/// Receives six explicit record capabilities, never AppStore, VaultStore or arbitrary storage.
@MainActor @Observable
final class AgentSession {
    private(set) var bubbles: [AgentBubble] = []
    private(set) var question: AgentQuestion?
    private(set) var plan: AgentPlan?
    private(set) var isWorking = false
    private(set) var error: String?
    private(set) var result: String?
    private(set) var undoPlan: AgentPlan?
    private var messages: [AIMessage] = []
    private var known: [AgentRecord] = []
    private var requestTask: Task<Void, Never>?
    private var generation = 0
    private let read: () -> [AgentRecord]
    private let commit: (AgentPlan) throws -> Void
    private let currency: () -> String

    init(read: @escaping () -> [AgentRecord], commit: @escaping (AgentPlan) throws -> Void, currency: @escaping () -> String) {
        self.read = read; self.commit = commit; self.currency = currency
    }
    func send(_ text: String, images: [AIImage], configuration: AIConfiguration, key: String) {
        guard !isWorking, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else { return }
        generation += 1
        let ticket = generation
        question = nil; error = nil; result = nil; undoPlan = nil
        bubbles.append(AgentBubble(isUser: true, text: text + (images.isEmpty ? "" : "\n📷 \(images.count)")))
        messages.append(AIMessage(role: "user", text: text, images: images))
        isWorking = true
        requestTask = Task {
            defer { if ticket == generation { isWorking = false } }
            do {
                let client = AIClient(configuration: configuration, apiKey: key)
                for _ in 0..<6 {
                    try Task.checkCancellation()
                    var system = AgentTools.instructions(now: Date(), timeZone: .current, currency: currency())
                    if let plan { system += "\n当前未保存草稿（用户补充时替换它，不要新增重复内容）：\(try JSONValue.from(plan).json)" }
                    let response = try await client.response(system: system, messages: messages)
                    guard ticket == generation else { return }
                    messages.append(AIMessage(role: "assistant", text: response.text, calls: response.calls, providerItems: response.providerItems))
                    if response.calls.isEmpty {
                        if !response.text.isEmpty { bubbles.append(AgentBubble(isUser: false, text: response.text)) }
                        return
                    }
                    var shouldReturn = false
                    for call in response.calls {
                        let output: String
                        do {
                            switch call.name {
                            case "search_records": output = try search(call.arguments).json
                            case "ask_user":
                                guard let text = call.arguments["question"]?.string, !text.isEmpty else { throw AgentPlanError.invalid("question") }
                                question = AgentQuestion(text: text, options: Array((call.arguments["options"]?.array ?? []).compactMap(\.string).prefix(5)))
                                output = "Question displayed. No changes saved. Await the user's answer."; shouldReturn = true
                            case "prepare_actions":
                                guard let values = call.arguments["actions"] else { throw AgentPlanError.invalid("actions") }
                                let actions = try values.decoded([AgentAction].self)
                                let draft = try AgentPlanner.prepare(actions, records: known,
                                    summary: call.arguments["summary"]?.string ?? "Review changes", currency: currency())
                                plan = draft; question = nil
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
                if ticket == generation { error = String(localized: "Cancelled. Nothing saved.") }
            } catch {
                if ticket == generation { self.error = error.localizedDescription }
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
            let inverse = AgentPlan(summary: String(localized: "Undo last action"), mutations: plan.mutations.map {
                AgentMutation(kind: $0.kind, id: $0.id, before: $0.after, after: $0.before)
            })
            undoPlan = inverse
            for mutation in plan.mutations {
                known.removeAll { $0.kind == mutation.kind && $0.id == mutation.id }
                if let after = mutation.after { known.append(.init(kind: mutation.kind, id: mutation.id, data: after)) }
            }
            messages.append(AIMessage(role: "user", text: "客户端确认已成功保存以下操作：\((try? JSONValue.from(plan).json) ?? plan.summary)。后续修改这些记录要使用真实ID进行update。"))
            result = String(localized: "Changes saved. Reminder delivery follows your notification permissions.")
            self.plan = nil
        } catch { self.error = error.localizedDescription }
    }
    func undo() {
        guard let undoPlan else { return }
        do {
            try commit(undoPlan); self.undoPlan = nil
            known = []; result = String(localized: "Last action undone.")
            messages.append(AIMessage(role: "user", text: "客户端已撤销刚才的操作，请勿认为其仍然有效。"))
        } catch { self.error = error.localizedDescription }
    }
    func cancel() {
        generation += 1; requestTask?.cancel(); requestTask = nil; isWorking = false
        plan = nil; question = nil; error = nil; result = String(localized: "Cancelled. Nothing saved.")
        messages.append(AIMessage(role: "user", text: "用户已取消当前草稿，尚未保存。后续不要自动恢复或执行它。"))
    }
}
