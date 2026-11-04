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
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
                }.disabled(isLoading || key.isEmpty)
            } header: { Text("AI Connection") } footer: {
                Text("Your selected text and images are sent directly to this API. The vault is never available to the assistant. API keys stay in this device's Keychain.")
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
        .onAppear {
            key = (try? SecretStore.read("ai.apiKey")).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            models = AISettings.cachedModels(configuration)
        }
        .onChange(of: configuration.apiType) { old, new in
            if configuration.baseURL == old.defaultBase { configuration.baseURL = new.defaultBase }
            models = []; message = nil
        }
    }
    private var filteredModels: [AIModel] {
        let words = search.split(whereSeparator: \.isWhitespace).map(String.init)
        return models.filter { model in words.allSatisfy { model.id.localizedStandardContains($0) || model.name.localizedStandardContains($0) } }
    }
    private func fetchModels() {
        isLoading = true; message = nil
        Task {
            defer { isLoading = false }
            do {
                models = try await AIClient(configuration: configuration, apiKey: key).models()
                AISettings.cache(models, for: configuration)
                if models.isEmpty { message = String(localized: "No models returned. Enter a model ID manually.") }
            } catch { message = error.localizedDescription + " " + String(localized: "You can still enter the model ID manually.") }
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
