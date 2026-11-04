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
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let session {
                            if session.bubbles.isEmpty { introduction }
                            ForEach(session.bubbles) { bubble in
                                Text(verbatim: bubble.text)
                                    .frame(maxWidth: .infinity, alignment: bubble.isUser ? .trailing : .leading)
                                    .padding(14).background(bubble.isUser ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                                    .textSelection(.enabled)
                            }
                            if let question = session.question {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(verbatim: question.text).font(.headline)
                                    ForEach(question.options, id: \.self) { option in
                                        Button { send(option) } label: {
                                            Text(verbatim: option).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                                .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
                                        }.disabled(session.isWorking)
                                    }
                                }.card()
                            }
                            if let plan = session.plan {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Review Changes").font(.headline)
                                    Text(verbatim: plan.summary)
                                    ForEach(plan.mutations) { mutation in AgentMutationRow(mutation: mutation) }
                                    PrimaryButton(title: "Confirm Changes", symbol: "checkmark") { speech.stop(); session.confirm() }
                                        .disabled(session.isWorking)
                                    Button("Discard Draft", role: .destructive) { session.cancel() }
                                }.card()
                            }
                            if session.isWorking { HStack { ProgressView(); Text("Working on your request…").font(.footnote) } }
                            if let result = session.result {
                                Text(verbatim: result).foregroundStyle(Theme.accent)
                                if session.undoPlan != nil { Button("Undo last action") { session.undo() } }
                            }
                            if let error = session.error { Text(verbatim: error).foregroundStyle(Pastel.rose.strong) }
                        }
                        if let error = error ?? speech.error { Text(verbatim: error).foregroundStyle(Pastel.rose.strong).font(.footnote) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(Metrics.screenPadding)
                }
                .onChange(of: session?.isWorking) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: session?.bubbles.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("Nook Assistant").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { speech.stop(); dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { NavigationLink { AISettingsView() } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel(Text("AI Settings")) }
            }
            .onAppear { session = store.assistantSession }
            .onDisappear { speech.stop() }
            .onChange(of: photo) { _, value in loadPhoto(value) }
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
        }.card()
    }
    private var composer: some View {
        VStack(spacing: 8) {
            if let preview {
                HStack {
                    Image(uiImage: preview).resizable().scaledToFit().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("This image will be sent to your AI provider.").font(.caption)
                    Spacer(); Button { image = nil; self.preview = nil; photo = nil } label: { Image(systemName: "xmark.circle.fill") }
                }
            }
            HStack(alignment: .bottom, spacing: 12) {
                PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo").frame(height: 36) }
                    .disabled(loadingImage || session?.isWorking == true)
                Button {
                    if speech.isListening { speech.stop() }
                    else {
                        let original = input
                        speech.onText = { input = original.isEmpty ? $0 : original + " " + $0 }
                        Task { await speech.start() }
                    }
                } label: { Image(systemName: speech.isListening ? "stop.circle.fill" : "mic").frame(height: 36) }
                    .disabled(session?.isWorking == true)
                TextField("What would you like to do?", text: $input, axis: .vertical).lineLimit(1...5).focused($focused)
                    .padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                if session?.isWorking == true {
                    Button { session?.cancel() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                } else {
                    Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(loadingImage || (input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && image == nil))
                }
            }
        }.padding(12).background(.regularMaterial)
    }
    private func send(_ value: String) {
        let configuration = AISettings.load()
        guard let key = (try? SecretStore.read("ai.apiKey")).flatMap({ String(data: $0, encoding: .utf8) }), !key.isEmpty,
              !configuration.model.isEmpty else { error = String(localized: "Configure an API key and model in AI Settings first."); return }
        speech.stop(); error = nil; focused = false
        session?.send(value, images: image.map { [$0] } ?? [], configuration: configuration, key: key)
        input = ""; image = nil; preview = nil; photo = nil
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

@MainActor
private struct AgentMutationRow: View {
    let mutation: AgentMutation
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label {
                Text(verbatim: mutation.after?["title"]?.string ?? mutation.before?["title"]?.string ?? mutation.kind.rawValue).font(.subheadline.bold())
            } icon: { Image(systemName: mutation.after == nil ? "trash" : mutation.before == nil ? "plus.circle" : "pencil.circle") }
            ForEach(changes, id: \.self) { key in
                HStack(alignment: .top) {
                    Text(verbatim: key).foregroundStyle(Theme.textSecondary).frame(width: 100, alignment: .leading)
                    VStack(alignment: .leading) {
                        if let old = mutation.before?[key], old != .null { Text(verbatim: display(old)).strikethrough().foregroundStyle(Theme.textSecondary) }
                        if let new = mutation.after?[key], new != .null { Text(verbatim: display(new)) }
                    }
                }.font(.caption)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12))
    }
    private var changes: [String] {
        let excluded: Set<String> = ["id", "created_at", "updated_at", "createdAt", "updatedAt", "title"]
        let keys = Set(mutation.after?.object?.keys.map { $0 } ?? []).union(mutation.before?.object?.keys.map { $0 } ?? [])
        return keys.filter { !excluded.contains($0) && mutation.before?[$0] != mutation.after?[$0] && mutation.after?[$0] != .string("") }.sorted()
    }
    private func display(_ value: JSONValue) -> String {
        if let string = value.string {
            if let date = RFC3339.date(from: string) { return date.formatted(date: .abbreviated, time: .shortened) }
            return string
        }
        return value.json
    }
}
