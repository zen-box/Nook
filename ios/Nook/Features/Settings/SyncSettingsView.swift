import SwiftUI
import NookCore

@MainActor
struct SyncSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var configuration = S3Configuration()
    @State private var accessKey = ""
    @State private var secretKey = ""
    @State private var sessionToken = ""
    @State private var recovery = ""
    @State private var creating = false
    @State private var savedRecovery = false
    @State private var message: String?
    @State private var selectedHistory: SyncHistoryItem?
    @State private var confirmRestore = false
    @State private var selectedConflict: SyncRecord?

    var body: some View {
        let sync = store.syncCoordinator
        Form {
            Section {
                if let date = sync.lastSuccess { LabeledContent("Last Successful Sync", value: date.formatted(date: .abbreviated, time: .shortened)) }
                if let status = sync.status { Text(verbatim: status).font(.footnote) }
                if let error = sync.error { Text(verbatim: error).foregroundStyle(Pastel.rose.strong).font(.footnote) }
                if sync.isWorking { ProgressView() }
                Button("Sync Now") { Task { await sync.sync() } }.disabled(sync.isWorking || sync.configuration == nil)
            } header: { Text("Encrypted Sync") } footer: {
                Text("Works locally without a server. S3 stores encrypted data and history. Automatic sync runs while Nook is active; open Nook to finish pending uploads before changing phones.")
            }
            Section("S3 Connection") {
                TextField("HTTPS Endpoint", text: $configuration.endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Bucket", text: $configuration.bucket).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Region (R2: auto)", text: $configuration.region).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Folder Prefix", text: $configuration.prefix).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("Path-style Addressing", isOn: $configuration.pathStyle)
                SecureField("Access Key ID", text: $accessKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Secret Access Key", text: $secretKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Session Token (optional)", text: $sessionToken).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section {
                Toggle("Create a New Encrypted Library", isOn: $creating)
                    .onChange(of: creating) { _, value in
                        savedRecovery = false
                        recovery = value ? SyncCrypto.code(SyncCrypto.makeKey()) : ""
                    }
                if creating {
                    Text(verbatim: recovery).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button("Copy Recovery Code") { Clipboard.copySecret(recovery) }
                    Toggle("I saved the recovery code separately", isOn: $savedRecovery)
                } else {
                    SecureField("Recovery Code", text: $recovery).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Button("Connect") { connect() }
                    .disabled(sync.isWorking || accessKey.isEmpty || secretKey.isEmpty || (creating && !savedRecovery))
            } header: { Text("Library Key") } footer: {
                Text("S3 credentials download data; the recovery code decrypts it. Losing every device and the code makes recovery impossible. Creating a library never overwrites an existing one.")
            }
            if let message { Section { Text(verbatim: message).font(.footnote) } }
            if !sync.conflicts.isEmpty {
                Section("Conflicting Versions") {
                    ForEach(sync.conflicts) { conflict in
                        Button { selectedConflict = conflict } label: {
                            VStack(alignment: .leading) {
                                Text(verbatim: conflict.visible?.payload?["title"]?.string ?? conflict.id)
                                Text("\(conflict.heads.count) versions preserved").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
            }
            if !sync.history.isEmpty {
                Section("Encrypted History") {
                    ForEach(sync.history.sorted { $0.date > $1.date }.prefix(30)) { item in
                        Button { selectedHistory = item; confirmRestore = true } label: {
                            Text(item.date, format: .dateTime.year().month().day().hour().minute().second())
                        }
                    }
                }
            }
            if sync.configuration != nil {
                Section {
                    Button("Disconnect S3", role: .destructive) { sync.disconnect() }.disabled(sync.isWorking)
                } footer: { Text("Disconnecting keeps local data, the saved library key and all cloud history. It does not delete the bucket.") }
            }
        }
        .navigationTitle("S3 Sync")
        .onAppear {
            configuration = sync.configuration ?? S3Configuration()
            if let account = try? sync.savedCredentialAccount(), let bytes = try? SecretStore.read(account), let credentials = try? JSONDecoder().decode(S3Credentials.self, from: bytes) {
                accessKey = credentials.accessKey; secretKey = credentials.secretKey; sessionToken = credentials.sessionToken
            }
        }
        .confirmationDialog("Restore this historical snapshot?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore Snapshot", role: .destructive) { if let selectedHistory { Task { await sync.restoreHistory(selectedHistory) } } }
        } message: { Text("Current data will be saved to encrypted history first. The selected snapshot replaces local records, including the encrypted vault.") }
        .sheet(item: $selectedConflict) { conflict in
            NavigationStack {
                List(conflict.heads) { version in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(version.editedAt, format: .dateTime.year().month().day().hour().minute())
                        if let payload = version.payload {
                            Text(verbatim: payload["title"]?.string ?? conflict.id).font(.headline)
                            if !conflict.id.hasPrefix("vault/") { Text(verbatim: payload.json).font(.caption).textSelection(.enabled) }
                            else { Text("Encrypted vault version").font(.caption) }
                        } else { Text("Deleted version").foregroundStyle(Pastel.rose.strong) }
                        Button("Keep This Version") { selectedConflict = nil; Task { await sync.resolve(conflict, choosing: version) } }.disabled(sync.isWorking)
                    }.padding(.vertical)
                }.navigationTitle("Choose a Version")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedConflict = nil } } }
            }.modifier(AppAppearance())
        }
    }
    private func connect() {
        Task {
            do {
                _ = try await store.syncCoordinator.configure(configuration, credentials: .init(accessKey: accessKey, secretKey: secretKey, sessionToken: sessionToken),
                                                               recovery: recovery, create: creating)
                message = nil; await store.syncCoordinator.sync()
            } catch { message = error.localizedDescription }
        }
    }
}
