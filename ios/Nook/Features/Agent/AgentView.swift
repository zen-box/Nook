import SwiftUI
import PhotosUI
import NookCore

@MainActor
struct AgentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var session: AgentSession?
    @State private var input = ""
    @State private var photo: PhotosPickerItem?
    @State private var image: AIImage?
    @State private var preview: UIImage?
    @State private var speech = SpeechInput()
    @State private var error: String?
    @State private var loadingImage = false
    @State private var confirmDeletion = false
    @State private var deletionCount = 0
    @State private var confirmUndo = false
    @State private var confirmReset = false
    @State private var needsSetup = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let session {
                            if session.isEmpty { introduction }
                            ForEach(session.entries) { entry in
                                row(entry, in: session)
                                    .id(entry.id)
                            }
                            if session.isWorking {
                                WorkingRow(isUpdatingReminders: session.isUpdatingReminders)
                            }
                        }
                        if let error = error ?? speech.error {
                            NoticeRow(text: error, isError: true)
                        }
                        if needsSetup {
                            NavigationLink { AISettingsView() } label: {
                                Label("Open AI Settings", systemImage: "slider.horizontal.3")
                                    .font(.system(.subheadline, weight: .semibold))
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(Metrics.screenPadding)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: session?.entries.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: session?.isWorking) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("Nook Assistant").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { speech.stop(); dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        confirmReset = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(session?.isEmpty != false || session?.isWorking == true)
                    .accessibilityLabel(Text("New Conversation"))
                    NavigationLink { AISettingsView() } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel(Text("AI Settings"))
                        .accessibilityIdentifier("assistant.settings")
                }
            }
            .onAppear { session = store.assistantSession }
            .onDisappear { speech.stop() }
            .onChange(of: photo) { _, value in loadPhoto(value) }
            .confirmationDialog(
                deletionCount == 1 ? Text("Delete this record?") : Text("Delete \(deletionCount) records?"),
                isPresented: $confirmDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { speech.stop(); session?.confirm() }
            } message: {
                Text("You can undo this right after saving.")
            }
            .confirmationDialog("Undo this change?", isPresented: $confirmUndo, titleVisibility: .visible) {
                Button("Undo Change", role: .destructive) { session?.undo() }
            } message: {
                Text("The records go back to how they were before you confirmed.")
            }
            .confirmationDialog("Start a new conversation?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("New Conversation", role: .destructive) { input = ""; session?.reset() }
            } message: {
                Text("The chat is cleared. Records you saved are kept.")
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: AgentEntry, in session: AgentSession) -> some View {
        switch entry.kind {
        case .user(let text, let imageCount):
            UserBubble(text: text, imageCount: imageCount)
        case .assistant(let text):
            AssistantBubble(text: text)
        case .question(let question):
            QuestionCard(
                question: question,
                answer: session.answers[question.id],
                isOpen: session.question?.id == question.id && !session.isWorking
            ) { option in
                answer(question, with: option)
            }
        case .draft(let plan):
            DraftCard(
                plan: plan,
                state: session.state(of: plan),
                note: session.draftNotes[plan.id],
                canUndo: session.undoablePlanID == plan.id,
                isBusy: session.isWorking,
                onConfirm: { confirm(plan) },
                onDiscard: { session.discard() },
                onUndo: { confirmUndo = true }
            )
        case .notice(let text, let isError):
            NoticeRow(text: text, isError: isError)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Get things done with Nook", systemImage: "sparkles").font(.title3.bold())
            Text("Add expenses, notes, tasks, events and anniversaries. Review changes before saving. The vault is never accessible.")
                .foregroundStyle(Theme.textSecondary)
            ForEach(["Record an expense", "Plan an event", "Find and update a note"], id: \.self) { label in
                Button { input = String(localized: String.LocalizationValue(label)); focused = true } label: {
                    Text(LocalizedStringKey(label)).font(.subheadline).padding(10).background(Theme.primarySoft, in: Capsule())
                }
            }
            Label("Tap the microphone to speak instead of typing.", systemImage: "mic")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }.card()
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let preview {
                HStack {
                    Image(uiImage: preview).resizable().scaledToFit().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("This image will be sent to your AI provider.").font(.caption)
                    Spacer(); Button { image = nil; self.preview = nil; photo = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel(Text("Remove image"))
                }
            }
            if speech.isListening {
                HStack(spacing: 8) {
                    Circle().fill(Pastel.rose.base).frame(width: 8, height: 8)
                    Text("Listening… tap stop when you're done.").font(.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .transition(.opacity)
            }
            HStack(alignment: .bottom, spacing: 12) {
                PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo").frame(height: 36) }
                    .disabled(loadingImage || session?.isWorking == true)
                    .accessibilityLabel(Text("Add Photo"))
                Button {
                    if speech.isListening { speech.stop() }
                    else {
                        let original = input
                        speech.onText = { input = original.isEmpty ? $0 : original + " " + $0 }
                        Task { await speech.start() }
                    }
                } label: {
                    Group {
                        if speech.isPreparing {
                            ProgressView()
                        } else {
                            Image(systemName: speech.isListening ? "stop.circle.fill" : "mic")
                                .foregroundStyle(speech.isListening ? Pastel.rose.strong : Theme.accent)
                        }
                    }
                    .frame(width: 28, height: 36)
                }
                .disabled(session?.isWorking == true)
                .accessibilityLabel(speech.isListening ? Text("Stop Voice Input") : Text("Voice Input"))
                TextField("What would you like to do?", text: $input, axis: .vertical).lineLimit(1...5).focused($focused)
                    .padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                if session?.isUpdatingReminders == true {
                    ProgressView().frame(height: 36)
                } else if session?.isWorking == true {
                    Button { session?.cancel() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                        .accessibilityLabel(Text("Stop"))
                } else {
                    Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(loadingImage || (input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && image == nil))
                        .accessibilityLabel(Text("Send"))
                }
            }
        }
        .padding(12).background(.regularMaterial)
        .animation(.easeOut(duration: 0.2), value: speech.isListening)
    }

    private func credentials() -> (configuration: AIConfiguration, key: String)? {
        let configuration = AISettings.load()
        guard let key = (try? SecretStore.read("ai.apiKey")).flatMap({ String(data: $0, encoding: .utf8) }), !key.isEmpty,
              !configuration.model.isEmpty else {
            error = String(localized: "Configure an API key and model in AI Settings first.")
            needsSetup = true
            return nil
        }
        needsSetup = false
        return (configuration: configuration, key: key)
    }

    private func send(_ value: String) {
        guard let auth = credentials() else { return }
        speech.stop(); error = nil; focused = false
        session?.send(value, images: image.map { [$0] } ?? [], configuration: auth.configuration, key: auth.key)
        input = ""; image = nil; preview = nil; photo = nil
    }

    private func answer(_ question: AgentQuestion, with option: String) {
        guard let auth = credentials() else { return }
        speech.stop(); error = nil; focused = false
        session?.answer(question, with: option, configuration: auth.configuration, key: auth.key)
    }

    /// Deleting records asks once more; other drafts are confirmed by the card itself.
    private func confirm(_ plan: AgentPlan) {
        let deletions = plan.mutations.filter { $0.after == nil }.count
        if deletions > 0 {
            deletionCount = deletions
            confirmDeletion = true
        } else {
            speech.stop()
            session?.confirm()
        }
    }

    private func loadPhoto(_ value: PhotosPickerItem?) {
        guard let value else { return }; loadingImage = true
        Task {
            defer { loadingImage = false }
            guard let data = try? await value.loadTransferable(type: Data.self), let source = UIImage(data: data) else {
                error = String(localized: "Couldn't read the image."); return
            }
            let ratio = min(1, 2048 / max(source.size.width, source.size.height))
            let size = CGSize(width: source.size.width * ratio, height: source.size.height * ratio)
            let scaled = UIGraphicsImageRenderer(size: size).image { _ in source.draw(in: CGRect(origin: .zero, size: size)) }
            guard let jpeg = scaled.jpegData(compressionQuality: 0.85) else { return }
            image = AIImage(data: jpeg); preview = scaled
        }
    }
}

// MARK: - Conversation rows

private struct UserBubble: View {
    let text: String
    let imageCount: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !text.isEmpty {
                Text(verbatim: text)
                    .textSelection(.enabled)
            }
            if imageCount > 0 {
                Label("\(imageCount) images attached", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 40)
    }
}

private struct AssistantBubble: View {
    let text: String

    var body: some View {
        MarkdownText(source: text)
            .textSelection(.enabled)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border, lineWidth: 1)
            }
            .padding(.trailing, 24)
    }
}

private struct NoticeRow: View {
    let text: String
    let isError: Bool

    var body: some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle")
        }
        .font(.footnote)
        .foregroundStyle(isError ? Pastel.rose.strong : Theme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isError ? Pastel.rose.soft : Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct WorkingRow: View {
    let isUpdatingReminders: Bool

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Group {
                if isUpdatingReminders {
                    Text("Scheduling reminders…")
                } else {
                    Text("Working on your request…")
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

private struct QuestionCard: View {
    let question: AgentQuestion
    let answer: String?
    let isOpen: Bool
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(verbatim: question.text).font(.headline)
            } icon: {
                Image(systemName: "questionmark.bubble").foregroundStyle(Theme.accent)
            }
            ForEach(question.options, id: \.self) { option in
                let chosen = option == answer
                Button {
                    onSelect(option)
                } label: {
                    HStack {
                        Text(verbatim: option)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        if chosen {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(12)
                    .background(chosen ? Theme.accent.opacity(0.14) : Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.pressable)
                .disabled(!isOpen)
                .opacity(isOpen || chosen ? 1 : 0.55)
            }
            if isOpen {
                Group {
                    if question.options.isEmpty {
                        Text("Type your answer below.")
                    } else {
                        Text("Choose an option or type your own answer.")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            } else if let answer, !question.options.contains(answer) {
                Label {
                    Text(verbatim: answer)
                } icon: {
                    Image(systemName: "arrowshape.turn.up.left")
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }
}

private struct DraftCard: View {
    let plan: AgentPlan
    let state: AgentDraftState
    let note: String?
    let canUndo: Bool
    let isBusy: Bool
    let onConfirm: () -> Void
    let onDiscard: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checklist").foregroundStyle(Theme.accent)
                Text("Review Changes").font(.headline)
                Spacer(minLength: 8)
                DraftStateBadge(state: state)
            }
            if !plan.summary.isEmpty {
                Text(verbatim: plan.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(plan.mutations) { mutation in AgentMutationRow(mutation: mutation) }
            switch state {
            case .pending:
                Text("Nothing is saved until you confirm.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    SoftButton(title: "Discard", symbol: "xmark") { onDiscard() }
                    PrimaryButton(title: "Confirm", symbol: "checkmark") { onConfirm() }
                        .disabled(isBusy)
                }
            case .saved:
                if let note {
                    Text(verbatim: note)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                if canUndo {
                    Button {
                        onUndo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.system(.subheadline, weight: .semibold))
                    }
                    .disabled(isBusy)
                }
            case .discarded:
                Text("Discarded. Nothing was saved.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            case .replaced:
                Text("Replaced by a newer draft below.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            case .undone:
                Text("Undone. The records are back to how they were.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
        .opacity(state == .discarded || state == .replaced ? 0.65 : 1)
        .animation(.easeOut(duration: 0.2), value: state)
    }
}

private struct DraftStateBadge: View {
    let state: AgentDraftState

    var body: some View {
        Label {
            title
        } icon: {
            Image(systemName: symbol)
        }
        .font(.system(.caption, weight: .semibold))
        .foregroundStyle(pastel.strong)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(pastel.soft, in: Capsule())
    }

    private var title: Text {
        switch state {
        case .pending: Text("Not saved")
        case .saved: Text("Saved")
        case .discarded: Text("Discarded")
        case .replaced: Text("Replaced")
        case .undone: Text("Undone")
        }
    }

    private var symbol: String {
        switch state {
        case .pending: "clock"
        case .saved: "checkmark.circle.fill"
        case .discarded: "xmark.circle"
        case .replaced: "arrow.triangle.2.circlepath"
        case .undone: "arrow.uturn.backward.circle"
        }
    }

    private var pastel: Pastel {
        switch state {
        case .pending: .peach
        case .saved: .mint
        case .discarded, .replaced: .slate
        case .undone: .violet
        }
    }
}

@MainActor
private struct AgentMutationRow: View {
    let mutation: AgentMutation
    @Environment(AppStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label {
                Text(verbatim: mutation.after?["title"]?.string ?? mutation.before?["title"]?.string ?? mutation.kind.rawValue).font(.subheadline.bold())
            } icon: {
                Image(systemName: mutation.after == nil ? "trash" : mutation.before == nil ? "plus.circle" : "pencil.circle")
                    .foregroundStyle(mutation.after == nil ? Pastel.rose.strong : Theme.accent)
            }
            if mutation.after == nil {
                Text("Will be deleted").font(.caption).foregroundStyle(Pastel.rose.strong)
            }
            ForEach(changes, id: \.self) { key in
                HStack(alignment: .top) {
                    Text(LocalizedStringKey(label(key))).foregroundStyle(Theme.textSecondary).frame(width: 86, alignment: .leading)
                    VStack(alignment: .leading) {
                        if let old = mutation.before?[key], old != .null { Text(verbatim: display(old, key: key)).strikethrough().foregroundStyle(Theme.textSecondary).lineLimit(6) }
                        if let new = mutation.after?[key], new != .null { Text(verbatim: display(new, key: key)).lineLimit(6) }
                        else if mutation.after != nil { Text("Not set").foregroundStyle(Theme.textSecondary) }
                    }
                }.font(.caption)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12))
    }
    private var changes: [String] {
        let excluded: Set<String> = ["id", "created_at", "updated_at", "createdAt", "updatedAt", "title", "series_id", "occurrence_start", "rich_content", "file_refs", "todos"]
        let keys = Set(mutation.after?.object?.keys.map { $0 } ?? []).union(mutation.before?.object?.keys.map { $0 } ?? [])
        return keys.filter { key in
            guard !excluded.contains(key), mutation.before?[key] != mutation.after?[key] else { return false }
            if mutation.before == nil {
                guard let value = mutation.after?[key], value != .null, value != .string(""), value != .array([]), value != .bool(false) else { return false }
            }
            return true
        }.sorted()
    }
    private func label(_ key: String) -> String {
        switch key {
        case "body": "Content"
        case "start", "start_date": "Starts"
        case "end", "end_date": "Ends"
        case "all_day": "All day"
        case "location", "destination": "Location"
        case "notes", "note", "summary", "description": "Notes"
        case "category": "Category"
        case "type": "Type"
        case "amount_minor": "Amount"
        case "currency": "Currency"
        case "occurred_at": "Date"
        case "reminder_minutes", "reminderMinutes", "reminder": "Reminder"
        case "recurrence", "repeat_rule": "Repeat"
        case "transport": "Travel Information"
        case "plan_id": "Trip"
        case "note_id": "Trip Plan Note"
        case "dueAt": "Due"
        case "isCompleted": "Completed"
        case "pinned": "Pinned"
        case "show_countdown": "Countdown"
        case "date": "Date"
        case "tags": "Tags"
        default: "Details"
        }
    }
    private func localized(_ value: String) -> String { String(localized: String.LocalizationValue(value)) }
    private func display(_ value: JSONValue, key: String) -> String {
        if key == "amount_minor", let amount = value.int {
            return Money(minorUnits: Int64(amount), currencyCode: mutation.after?["currency"]?.string ?? mutation.before?["currency"]?.string ?? store.currencyCode).formatted()
        }
        if key == "reminder_minutes" || key == "reminderMinutes", let minutes = value.int {
            return minutes == 0 ? String(localized: "At start time") : String(localized: "\(minutes) minutes before")
        }
        if key == "plan_id", let id = value.string.flatMap(UUID.init(uuidString:)) { return store.trip(id: id)?.title ?? String(localized: "Trip") }
        if key == "note_id", let id = value.string.flatMap(UUID.init(uuidString:)) { return store.note(id: id)?.title ?? String(localized: "Trip Plan Note") }
        if key == "transport", let details = try? value.decoded(TransportDetails.self) { return details.readableSummary }
        if key == "recurrence", let rule = try? value.decoded(EventRecurrence.self) {
            let frequency = ["daily": "Daily", "weekly": "Weekly", "monthly": "Monthly", "yearly": "Yearly"][rule.frequency.rawValue]!
            var parts = [localized(frequency), String(localized: "Every \(rule.interval)")]
            if rule.frequency == .weekly {
                let days = rule.weekdays.map { Calendar.current.shortStandaloneWeekdaySymbols[$0 % 7] }.joined(separator: ", ")
                if !days.isEmpty { parts.append(days) }
            }
            parts.append(rule.timeZoneID)
            if let end = rule.endsOn { parts.append(end.isoString) }
            if let count = rule.occurrenceLimit { parts.append(String(localized: "\(count) occurrences")) }
            return parts.joined(separator: " · ")
        }
        if key == "reminder", let reminder = try? value.decoded(AnniversaryReminder.self) {
            let days = reminder.daysBefore.map { $0 == 0 ? String(localized: "On the day") : String(localized: "\($0) days before") }
            return String(format: "%02d:%02d", reminder.hour, reminder.minute) + " · " + days.joined(separator: ", ")
        }
        if let boolean = value.bool { return boolean ? String(localized: "Yes") : String(localized: "No") }
        if let items = value.array { return items.compactMap(\.string).joined(separator: ", ") }
        if let string = value.string {
            if let date = RFC3339.date(from: string) { return date.formatted(date: .abbreviated, time: .shortened) }
            if key == "category" || key == "type" || key == "repeat_rule" {
                let names = ["work": "Work", "travel": "Travel", "life": "Life", "personal": "Personal", "health": "Health", "other": "Other", "others": "Others", "food": "Food & Dining", "shopping": "Shopping", "transport": "Transport", "housing": "Housing", "entertainment": "Entertainment", "salary": "Salary", "birthday": "Birthday", "anniversary": "Anniversary", "project": "Project", "custom": "Custom", "expense": "Expense", "income": "Income", "transfer": "Transfer", "yearly": "Yearly", "none": "Never"]
                return localized(names[string] ?? string)
            }
            return string
        }
        return value.json
    }
}
