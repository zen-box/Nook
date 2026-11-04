import SwiftUI
import NookCore

@MainActor
struct AISettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var configuration = AISettings.load()
    @State private var key = ""
    @State private var models: [AIModel] = []
    @State private var search = ""
    @State private var isLoading = false
    @State private var isTesting = false
    @State private var testSucceeded = false
    @State private var testMessage: String?
    @State private var work: Task<Void, Never>?
    @State private var message: String?
    @State private var confirmClearHistory = false
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Picker("API Type", selection: $configuration.apiType) {
                    ForEach(AIProtocol.allCases) { type in Text(verbatim: type.label).tag(type) }
                }
                TextField("API Base", text: $configuration.baseURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                SecureField("API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Model ID", text: $configuration.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { fetchModels() } label: {
                    HStack { Text("Fetch Models"); if isLoading { Spacer(); ProgressView() } }
                }.disabled(isBusy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: { Text("AI Connection") } footer: {
                Text("Your selected text and images are sent directly to this API. The vault is never available to the assistant. API keys stay in this device's Keychain.")
            }
            Section {
                Button { testConnection() } label: {
                    HStack {
                        Label("Test Connection", systemImage: "network")
                        Spacer()
                        if isTesting { ProgressView() }
                    }
                }
                .accessibilityIdentifier("ai.testConnection")
                .disabled(isBusy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let testMessage {
                    Label { Text(verbatim: testMessage).textSelection(.enabled) } icon: {
                        Image(systemName: testSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    }.foregroundStyle(testSucceeded ? Color.green : Color.red)
                        .font(.footnote).accessibilityIdentifier("ai.testResult")
                }
            } footer: {
                Text("Sends a short request to the selected model using the values above, without saving them. No personal records are sent. API usage may be billed.")
            }
            Section {
                Toggle("Keep Chat History", isOn: $store.keepsAssistantHistory)
                    .accessibilityIdentifier("ai.keepHistory")
                Button("Clear Chat History", role: .destructive) { confirmClearHistory = true }
                    .disabled(store.isAssistantWorking)
                    .accessibilityIdentifier("ai.clearHistory")
            } header: { Text("Chat History") } footer: {
                Text("Saved only on this iPhone, in the same protected database as your records. Not included in S3 sync, encrypted backups or phone transfers. Images aren't kept, and only the latest 300 messages are. When off, chats last only until Nook is closed.")
            }
            if let message { Section { Text(verbatim: message).font(.footnote) } }
            if !models.isEmpty {
                Section {
                    TextField("Search models", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
                    ForEach(filteredModels) { model in
                        Button {
                            configuration.model = model.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(verbatim: model.id).foregroundStyle(Theme.textPrimary)
                                    if model.name != model.id { Text(verbatim: model.name).font(.caption).foregroundStyle(Theme.textSecondary) }
                                }
                                Spacer()
                                if configuration.model == model.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } header: { Text("Models") } footer: {
                    Text("Model names do not guarantee image or tool support. If fetching fails, enter the model ID above.")
                }
            }
        }
        .navigationTitle("AI Settings")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } } }
        .confirmationDialog("Clear chat history?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("Clear Chat History", role: .destructive) {
                store.clearAssistantHistory()
                router.showToast(ToastMessage(text: "Chat history cleared"))
            }
        } message: {
            Text("The conversation is deleted from this iPhone. Notes, events and other records you saved are kept.")
        }
        .onAppear {
            key = (try? SecretStore.read("ai.apiKey")).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            models = AISettings.cachedModels(configuration)
        }
        .onChange(of: configuration.apiType) { old, new in
            if configuration.baseURL == old.defaultBase { configuration.baseURL = new.defaultBase }
            models = []; message = nil
        }
        .onChange(of: configuration) { old, new in
            cancelWork()
            if old.baseURL != new.baseURL || old.apiType != new.apiType { models = []; search = "" }
        }
        .onChange(of: key) { _, _ in cancelWork() }
        .onDisappear { cancelWork() }
    }
    private var isBusy: Bool { isLoading || isTesting }
    private func cancelWork() {
        work?.cancel(); work = nil; isLoading = false; isTesting = false; testMessage = nil
    }
    private var filteredModels: [AIModel] {
        let words = search.split(whereSeparator: \.isWhitespace).map(String.init)
        return models.filter { model in words.allSatisfy { model.id.localizedStandardContains($0) || model.name.localizedStandardContains($0) } }
    }
    private func fetchModels() {
        isLoading = true; message = nil
        let captured = configuration, capturedKey = key
        work = Task {
            defer { if !Task.isCancelled { isLoading = false } }
            do {
                let values = try await AIClient(configuration: captured, apiKey: capturedKey).models()
                try Task.checkCancellation()
                guard configuration == captured, key == capturedKey else { return }
                models = values
                AISettings.cache(models, for: captured)
                if models.isEmpty { message = String(localized: "No models returned. Enter a model ID manually.") }
            } catch is CancellationError { } catch {
                if !Task.isCancelled { message = error.localizedDescription + " " + String(localized: "You can still enter the model ID manually.") }
            }
        }
    }
    private func testConnection() {
        isTesting = true; testMessage = nil
        let captured = configuration, capturedKey = key, started = Date()
        work = Task {
            defer { if !Task.isCancelled { isTesting = false } }
            do {
                let reply = try await AIClient(configuration: captured, apiKey: capturedKey).testConnection()
                try Task.checkCancellation()
                guard configuration == captured, key == capturedKey else { return }
                guard reply.calls.isEmpty, !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.invalidResponse }
                let seconds = Date().timeIntervalSince(started).formatted(.number.precision(.fractionLength(1)))
                testSucceeded = true
                testMessage = String(localized: "\(captured.model) responded in \(seconds) s")
            } catch is CancellationError { } catch {
                if !Task.isCancelled {
                    testSucceeded = false
                    if let aiError = error as? AIError, case .http(let status) = aiError {
                        switch status {
                        case 401, 403: testMessage = String(localized: "Authentication failed. Check the API key and model access.")
                        case 404: testMessage = String(localized: "Endpoint or model not found. Check the API type, base URL and model ID.")
                        case 429: testMessage = String(localized: "The service reported a quota or rate limit. Check your balance or try again later.")
                        default: testMessage = error.localizedDescription
                        }
                    } else { testMessage = error.localizedDescription }
                }
            }
        }
    }
    private func save() {
        do {
            _ = try AIClient(configuration: configuration, apiKey: key).endpoint("models")
            if key.isEmpty { try SecretStore.delete("ai.apiKey") }
            else { try SecretStore.write(Data(key.utf8), account: "ai.apiKey") }
            UserDefaults.standard.set(try JSONEncoder().encode(configuration), forKey: "ai.configuration")
            store.syncCoordinator.scheduleSync()
            dismiss()
        } catch { message = error.localizedDescription }
    }
}

enum AISettings {
    static func load() -> AIConfiguration {
        UserDefaults.standard.data(forKey: "ai.configuration").flatMap { try? JSONDecoder().decode(AIConfiguration.self, from: $0) } ?? AIConfiguration()
    }
    private static func cacheKey(_ c: AIConfiguration) -> String { "ai.models.\(c.apiType.rawValue).\(c.baseURL)" }
    static func cache(_ values: [AIModel], for c: AIConfiguration) { UserDefaults.standard.set(values.map(\.id), forKey: cacheKey(c)) }
    static func cachedModels(_ c: AIConfiguration) -> [AIModel] { (UserDefaults.standard.stringArray(forKey: cacheKey(c)) ?? []).map { AIModel(id: $0) } }
}
