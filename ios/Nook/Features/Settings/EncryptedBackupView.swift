import SwiftUI
import UniformTypeIdentifiers
import NookCore

@MainActor
struct EncryptedBackupView: View {
    @Environment(AppStore.self) private var store
    @State private var code = ""
    @State private var importCode = ""
    @State private var savedCode = false
    @State private var working = false
    @State private var exported: URL?
    @State private var importing = false
    @State private var staged: StagedArchive?
    @State private var confirm = false
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Button("Prepare Recovery Code") { prepareCode() }
                if !code.isEmpty {
                    Text(verbatim: code).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button("Copy Recovery Code") { Clipboard.copySecret(code) }
                    Toggle("I saved the recovery code separately", isOn: $savedCode)
                    Button("Create Encrypted Backup") { export() }.disabled(!savedCode || working)
                }
                if let exported { ShareLink(item: exported) { Label("Share Encrypted Backup", systemImage: "square.and.arrow.up") } }
            } header: { Text("Complete Backup") } footer: {
                Text("Includes notes, original photos and audio, tasks, calendar, finance, settings and the encrypted vault. The vault still requires its own master password. API keys are excluded. Keep the recovery code separately from this file.")
            }
            Section {
                SecureField("Backup Recovery Code", text: $importCode).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Choose Encrypted Backup") { importing = true }.disabled(working || importCode.isEmpty)
            } header: { Text("Restore") } footer: { Text("Restoring replaces local records after you confirm. If S3 sync is configured, the restored changes will also be synchronized.") }
            if working { ProgressView() }
            if let message { Text(verbatim: message).font(.footnote) }
        }
        .navigationTitle("Encrypted Backup")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }; read(url)
        }
        .confirmationDialog("Replace local data with this backup?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Restore Backup", role: .destructive) {
                guard let staged else { return }
                do {
                    try BackupArchive.install(staged, into: store)
                    message = String(localized: "Encrypted backup restored.")
                    try? FileManager.default.removeItem(at: staged.folder); self.staged = nil
                } catch { message = error.localizedDescription }
            }
        } message: {
            if let staged { Text("\(staged.dataset.values.count) records and \(staged.refs.count) attachments. Keep a backup of this device before replacing its data.") }
        }
        .onDisappear { if let staged { try? FileManager.default.removeItem(at: staged.folder) } }
    }
    private func prepareCode() {
        do {
            if let existing = try SecretStore.read("backup.root") { code = SyncCrypto.code(existing) }
            else {
                let key = SyncCrypto.makeKey(); try SecretStore.write(key, account: "backup.root"); code = SyncCrypto.code(key)
            }
        } catch { message = error.localizedDescription }
    }
    private func export() {
        working = true; message = nil
        Task {
            defer { working = false }
            do {
                let values = try store.portableValues(), refs = try AppStore.attachmentRefs(in: values)
                let folder = store.attachments.folder, key = try SyncCrypto.key(from: code)
                exported = try await Task.detached(priority: .userInitiated) { try BackupArchive.write(values: values, refs: refs, folder: folder, key: key) }.value
                message = String(localized: "Encrypted backup is ready. Share it to a safe location.")
            } catch { message = error.localizedDescription }
        }
    }
    private func read(_ url: URL) {
        working = true; message = nil
        Task {
            defer { working = false }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let key = try SyncCrypto.key(from: importCode)
                if let staged { try? FileManager.default.removeItem(at: staged.folder); self.staged = nil }
                staged = try await Task.detached(priority: .userInitiated) { try BackupArchive.read(url, key: key) }.value
                confirm = true
            } catch { message = error.localizedDescription }
        }
    }
}
