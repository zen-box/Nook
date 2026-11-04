import SwiftUI
import NookCore

struct VaultItemDetailView: View {
    let itemID: UUID
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var revealed: Set<UUID> = []
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let item = store.vault.item(id: itemID) {
                content(item)
            } else {
                ContentUnavailableView("Vault is locked", systemImage: "lock")
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if store.vault.item(id: itemID) != nil {
                    Menu {
                        Button {
                            router.present(.vaultEditor(itemID))
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(Text("More"))
                }
            }
        }
        .confirmationDialog("Delete this item?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Item", role: .destructive) {
                do {
                    try store.vault.delete(itemID)
                    dismiss()
                } catch {
                    router.showToast(ToastMessage(text: "Couldn't save the change", symbol: "exclamationmark.triangle.fill", isWarning: true))
                }
            }
        }
    }

    private func content(_ item: VaultItem) -> some View {
        ScrollView {
            VStack(spacing: Metrics.sectionSpacing) {
                VStack(spacing: 10) {
                    IconTile(symbol: item.icon, pastel: item.pastel, size: 64)
                    Text(item.title)
                        .font(.system(.title2, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(item.category.singularLabel)
                        .font(NookFont.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 8)

                let fields = item.fields.filter { !$0.value.isEmpty }
                if !fields.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                            fieldRow(field)
                            if index < fields.count - 1 {
                                Hairline().padding(.leading, 16)
                            }
                        }
                    }
                    .card(padding: 0)
                }

                if let link = item.url, !link.isEmpty {
                    Button {
                        if let url = Self.webURL(link) {
                            openURL(url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(symbol: "safari", pastel: .blue, size: 34)
                            Text(link)
                                .font(.subheadline)
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .card(padding: 14)
                    }
                    .buttonStyle(.pressable)
                }

                if !item.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(NookFont.micro)
                            .foregroundStyle(Theme.textSecondary)
                        Text(item.notes)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                    }
                    .card(padding: 16)
                }

                Text("Updated \(item.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(NookFont.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 12)
        }
    }

    private func fieldRow(_ field: VaultField) -> some View {
        let isHidden = field.isSecret && !revealed.contains(field.id)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(field.label)
                    .font(NookFont.micro)
                    .foregroundStyle(Theme.textSecondary)
                Text(verbatim: isHidden ? "••••••••" : field.value)
                    .font(field.isSecret ? .subheadline.monospaced() : .subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(isHidden ? 1 : nil)
            }
            Spacer(minLength: 8)
            if field.isSecret {
                Button {
                    if revealed.contains(field.id) {
                        revealed.remove(field.id)
                    } else {
                        revealed.insert(field.id)
                    }
                } label: {
                    Image(systemName: isHidden ? "eye" : "eye.slash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(Theme.surfaceMuted, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(isHidden ? Text("Show") : Text("Hide"))
            }
            Button {
                if field.isSecret {
                    Clipboard.copySecret(field.value)
                    router.showToast(ToastMessage(text: "\(field.label) copied for 90 seconds", symbol: "doc.on.doc.fill"))
                } else {
                    Clipboard.copy(field.value)
                    router.showToast(ToastMessage(text: "Copied", symbol: "doc.on.doc.fill"))
                }
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.primarySoft, in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text("Copy"))
        }
        .padding(16)
    }

    static func webURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        return URL(string: withScheme)
    }
}

struct VaultItemEditorView: View {
    let itemID: UUID?
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var draft = VaultItem(title: "", category: .account, icon: VaultCategory.account.defaultIcon)
    @State private var website = ""
    @State private var revealed: Set<UUID> = []
    @State private var loaded = false

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $draft.category) {
                        ForEach(VaultCategory.allCases, id: \.self) { category in
                            Text(category.singularLabel).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("Name", text: $draft.title)
                    iconPicker
                    Toggle("Favorite", isOn: $draft.isFavorite)
                }
                Section {
                    ForEach($draft.fields) { $field in
                        VaultFieldEditor(field: $field, isRevealed: revealed.contains(field.id)) {
                            if revealed.contains(field.id) {
                                revealed.remove(field.id)
                            } else {
                                revealed.insert(field.id)
                            }
                        }
                    }
                    .onDelete { offsets in
                        draft.fields.remove(atOffsets: offsets)
                    }
                    Menu {
                        Button {
                            draft.fields.append(VaultField(label: String(localized: "Detail")))
                        } label: {
                            Label("Text Field", systemImage: "textformat")
                        }
                        Button {
                            draft.fields.append(VaultField(label: String(localized: "Password"), isSecret: true))
                        } label: {
                            Label("Secret Field", systemImage: "lock")
                        }
                    } label: {
                        Label("Add Field", systemImage: "plus")
                    }
                } header: {
                    Text("Fields")
                } footer: {
                    Text("Secret fields stay hidden until you tap the eye, and copies of them leave the clipboard after 90 seconds.")
                }
                if draft.category == .account {
                    Section("Website") {
                        TextField(text: $website, prompt: Text(verbatim: "example.com")) {
                            Text("Website")
                        }
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                }
                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(itemID == nil ? Text("New Item") : Text("Edit Item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear { load() }
        .onChange(of: draft.category) { old, new in
            // Swap the starter fields while nothing has been typed into them.
            if draft.fields.allSatisfy({ $0.value.isEmpty }) {
                draft.fields = new.templateFields
            }
            if draft.icon == old.defaultIcon || !new.iconChoices.contains(draft.icon) {
                draft.icon = new.defaultIcon
            }
        }
        .onChange(of: store.vault.state) { _, state in
            if state != .unlocked {
                draft = VaultItem(title: "", category: .account, icon: VaultCategory.account.defaultIcon)
                website = ""
                revealed = []
                dismiss()
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(28)
    }

    private var iconPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(draft.category.iconChoices, id: \.self) { symbol in
                    let isSelected = symbol == draft.icon
                    Button {
                        draft.icon = symbol
                    } label: {
                        IconTile(symbol: symbol, pastel: isSelected ? .blue : .slate, size: 40)
                            .overlay {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Theme.accent, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: symbol))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let itemID, let item = store.vault.item(id: itemID) {
            draft = item
            website = item.url ?? ""
        } else {
            draft.fields = draft.category.templateFields
        }
    }

    private func save() {
        var item = draft
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.fields = item.fields.filter {
            !$0.value.isEmpty || !$0.label.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let site = website.trimmingCharacters(in: .whitespacesAndNewlines)
        item.url = item.category == .account && !site.isEmpty ? site : nil
        do {
            try store.vault.save(item)
            dismiss()
        } catch {
            router.showToast(ToastMessage(text: "Couldn't save the change", symbol: "exclamationmark.triangle.fill", isWarning: true))
        }
    }
}

private struct VaultFieldEditor: View {
    @Binding var field: VaultField
    let isRevealed: Bool
    let onToggleReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Label", text: $field.label)
                .font(NookFont.micro)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 10) {
                Group {
                    if field.isSecret && !isRevealed {
                        SecureField("Value", text: $field.value)
                    } else {
                        TextField("Value", text: $field.value)
                    }
                }
                .font(field.isSecret ? .body.monospaced() : .body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                if field.isSecret {
                    Button {
                        field.value = PasswordGenerator.make()
                        if !isRevealed {
                            onToggleReveal()
                        }
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Generate password"))
                    Button(action: onToggleReveal) {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isRevealed ? Text("Hide") : Text("Show"))
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct ChangeMasterPasswordView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var failed = false

    private var canSave: Bool {
        !current.isEmpty && newPassword.count >= VaultCrypto.minimumPasswordLength && newPassword == confirmation && !isWorking
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PasswordField(prompt: "Current master password", text: $current)
                    PasswordField(prompt: "New master password", text: $newPassword)
                    PasswordField(prompt: "Repeat new master password", text: $confirmation)
                    Group {
                        if failed {
                            Text("Wrong master password.")
                                .foregroundStyle(Pastel.rose.strong)
                        } else if !confirmation.isEmpty && newPassword != confirmation {
                            Text("The two passwords don't match.")
                                .foregroundStyle(Pastel.rose.strong)
                        } else {
                            Text("At least 8 characters.")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .font(NookFont.caption)
                    PrimaryButton(title: "Change Password", isWorking: isWorking) {
                        change()
                    }
                    .disabled(!canSave)
                }
                .card()
                .padding(Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Master Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: store.vault.state) { _, state in
            if state != .unlocked {
                current = ""
                newPassword = ""
                confirmation = ""
                dismiss()
            }
        }
        .presentationCornerRadius(28)
    }

    private func change() {
        guard canSave else { return }
        isWorking = true
        failed = false
        Task {
            do {
                try await store.vault.changeMasterPassword(current: current, new: newPassword)
                router.showToast(ToastMessage(text: "Master password changed"))
                dismiss()
            } catch {
                failed = true
            }
            isWorking = false
        }
    }
}
