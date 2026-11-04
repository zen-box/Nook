import SwiftUI
import NookCore

/// The password vault. Entries are encrypted on disk; the list is only readable after unlocking
/// with the master password or Face ID, and the vault locks again when Nook leaves the screen.
struct VaultView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var search = ""

    var body: some View {
        let vault = store.vault
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                ScreenHeader(title: "Vault") {
                    if vault.state == .unlocked {
                        CircleIconButton(symbol: "lock", label: "Lock Vault") {
                            vault.lock()
                        }
                    }
                    AddMenuButton(primary: .account)
                }
                Group {
                    if vault.storageFailed {
                        ContentUnavailableView("Vault storage unavailable", systemImage: "exclamationmark.triangle",
                                               description: Text("Restart Nook to try again. Your saved vault has not been changed."))
                    } else { switch vault.state {
                    case .needsSetup:
                        SecureVaultHero(isUnlocked: false)
                        VaultSetupCard()
                    case .locked:
                        SecureVaultHero(isUnlocked: false)
                        VaultUnlockCard()
                    case .unlocked:
                        unlockedContent
                    }
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
            }
            .padding(.top, 8)
            .padding(.bottom, Metrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .top) { StatusBarScrim() }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("screen.vault")
        .onChange(of: router.selectedTab) { _, tab in
            if tab == .vault && vault.canUnlockQuickly {
                Task { _ = await vault.unlockQuickly() }
            }
        }
        .onChange(of: vault.state) { _, state in
            if state != .unlocked {
                search = ""
                router.vaultPath = []
            }
        }
    }

    @ViewBuilder
    private var unlockedContent: some View {
        let vault = store.vault
        SearchField(prompt: "Search accounts or passwords", text: $search)
        if vault.unreadableCount > 0 {
            Label("\(vault.unreadableCount) items could not be decrypted", systemImage: "exclamationmark.triangle")
                .font(NookFont.caption)
                .foregroundStyle(Pastel.rose.strong)
                .card(padding: 14)
        }
        if search.isEmpty {
            SecureVaultHero(isUnlocked: true)
            categoryTiles
            if vault.items.isEmpty {
                EmptyStateView(symbol: "key", title: "No accounts yet", message: "Tap + to save your first account.")
                    .card()
            } else {
                ForEach(VaultCategory.allCases, id: \.self) { category in
                    let items = vault.items(in: category)
                    if !items.isEmpty {
                        SectionHeader(title: category.label, actionTitle: items.count > 4 ? "View All" : nil) {
                            router.push(.vaultList(category), in: .vault)
                        }
                        .padding(.top, 4)
                        VaultRowsCard(items: Array(items.prefix(4)))
                    }
                }
            }
        } else {
            let results = vault.search(search)
            if results.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "No matching items").card()
            } else {
                VaultRowsCard(items: results)
            }
        }
    }

    private var categoryTiles: some View {
        let vault = store.vault
        return HStack(spacing: 10) {
            VaultCategoryTile(title: "All", symbol: "square.grid.2x2", pastel: .blue, count: vault.totalCount) {
                router.push(.vaultList(nil), in: .vault)
            }
            ForEach(VaultCategory.allCases, id: \.self) { category in
                VaultCategoryTile(
                    title: category.label,
                    symbol: category.symbol,
                    pastel: category.pastel,
                    count: vault.counts[category] ?? 0
                ) {
                    router.push(.vaultList(category), in: .vault)
                }
            }
        }
    }
}

private struct SecureVaultHero: View {
    let isUnlocked: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Pastel.mint.strong)
                .frame(width: 54, height: 54)
                .background(Theme.surface.opacity(0.92), in: Circle())
                .shadow(color: Pastel.mint.strong.opacity(0.18), radius: 10, x: 0, y: 4)
            VStack(alignment: .leading, spacing: 5) {
                Text("Secure Vault")
                    .font(NookFont.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("Your accounts and passwords are encrypted and safe.")
                    .font(NookFont.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(colors: [Pastel.mint.soft, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                WaveShape(baseline: 0.82, amplitude: 7, wavelength: 0.8, phase: 0.1, fillsBelow: true)
                    .fill(Pastel.mint.base.opacity(0.18))
                WaveShape(baseline: 0.9, amplitude: 5, wavelength: 1.1, phase: 0.55, fillsBelow: true)
                    .fill(Pastel.mint.base.opacity(0.22))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Pastel.mint.base.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: Theme.shadow, radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .combine)
    }
}

/// First use: choose the master password that protects the vault key.
private struct VaultSetupCard: View {
    @Environment(AppStore.self) private var store
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var failed = false

    private var canCreate: Bool {
        password.count >= VaultCrypto.minimumPasswordLength && password == confirmation && !isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconTile(symbol: "key.fill", pastel: .mint, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create a master password")
                        .font(NookFont.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("It encrypts everything you keep in the vault.")
                        .font(NookFont.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            PasswordField(prompt: "Master password", text: $password)
            PasswordField(prompt: "Repeat master password", text: $confirmation)
            Group {
                if !confirmation.isEmpty && password != confirmation {
                    Text("The two passwords don't match.")
                        .foregroundStyle(Pastel.rose.strong)
                } else if failed {
                    Text("Couldn't create the vault. Please try again.")
                        .foregroundStyle(Pastel.rose.strong)
                } else {
                    Text("At least 8 characters. Nook can't recover a forgotten master password: without it the vault can only be reset.")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .font(NookFont.caption)
            .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Create Vault", isWorking: isWorking) {
                create()
            }
            .disabled(!canCreate)
        }
        .card()
    }

    private func create() {
        guard canCreate else { return }
        isWorking = true
        failed = false
        Task {
            do {
                try await store.vault.setUp(masterPassword: password)
                password = ""
                confirmation = ""
            } catch {
                failed = true
            }
            isWorking = false
        }
    }
}

private struct VaultUnlockCard: View {
    @Environment(AppStore.self) private var store
    @State private var password = ""
    @State private var isWorking = false
    @State private var wrongPassword = false
    @State private var confirmReset = false

    var body: some View {
        let vault = store.vault
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconTile(symbol: "lock.fill", pastel: .blue, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vault is locked")
                        .font(NookFont.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(vault.totalCount) accounts · \(vault.categoryCount) categories")
                        .font(NookFont.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if vault.canUnlockQuickly {
                PrimaryButton(title: "Unlock with \(DeviceAuthentication.methodName)", symbol: DeviceAuthentication.methodSymbol) {
                    Task { _ = await vault.unlockQuickly() }
                }
            }
            PasswordField(prompt: "Master password", text: $password)
                .onSubmit { unlock() }
            if wrongPassword {
                Text("Wrong master password.")
                    .font(NookFont.caption)
                    .foregroundStyle(Pastel.rose.strong)
            }
            if vault.canUnlockQuickly {
                SoftButton(title: "Unlock") { unlock() }
                    .disabled(password.isEmpty || isWorking)
            } else {
                PrimaryButton(title: "Unlock", isWorking: isWorking) { unlock() }
                    .disabled(password.isEmpty || isWorking)
            }
            Button("Forgot master password?") {
                confirmReset = true
            }
            .font(NookFont.caption)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
        }
        .card()
        .confirmationDialog("Reset the vault?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Delete All Vault Items", role: .destructive) {
                try? store.vault.reset()
            }
        } message: {
            Text("Without the master password the saved items can't be decrypted. Resetting deletes them and lets you choose a new master password.")
        }
    }

    private func unlock() {
        guard !password.isEmpty, !isWorking else { return }
        isWorking = true
        wrongPassword = false
        Task {
            do {
                try await store.vault.unlock(masterPassword: password)
                password = ""
            } catch is CancellationError {
                password = ""
            } catch {
                wrongPassword = true
            }
            isWorking = false
        }
    }
}

private struct VaultCategoryTile: View {
    let title: LocalizedStringKey
    let symbol: String
    let pastel: Pastel
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                IconTile(symbol: symbol, pastel: pastel, size: 32)
                Text(verbatim: "\(count)")
                    .font(.system(.title3, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Text(title)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
            .shadow(color: Theme.shadow, radius: 12, x: 0, y: 5)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
    }
}

struct VaultRowsCard: View {
    let items: [VaultItem]
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VaultRow(item: item) {
                    copy(item)
                }
                if index < items.count - 1 {
                    Hairline().padding(.leading, 66)
                }
            }
        }
        .card(padding: 0)
    }

    /// Copies the password (or card number) when there is one, otherwise the login name.
    private func copy(_ item: VaultItem) {
        if let secret = item.primarySecret {
            Clipboard.copySecret(secret.value)
            router.showToast(ToastMessage(text: "\(secret.label) copied for 90 seconds", symbol: "doc.on.doc.fill"))
        } else if !item.subtitle.isEmpty {
            Clipboard.copy(item.subtitle)
            router.showToast(ToastMessage(text: "Copied", symbol: "doc.on.doc.fill"))
        }
    }
}

private struct VaultRow: View {
    let item: VaultItem
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: AppRoute.vaultItem(item.id)) {
                HStack(spacing: 12) {
                    IconTile(symbol: item.icon, pastel: item.pastel)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(item.title)
                                .font(NookFont.rowTitle)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            if item.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Pastel.peach.base)
                            }
                        }
                        Text(item.subtitle)
                            .font(NookFont.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if item.primarySecret != nil {
                        Text(verbatim: "••••••••")
                            .font(.system(.footnote, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .accessibilityLabel(Text("Password hidden"))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.primarySoft, in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text("Copy password"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct VaultListView: View {
    let category: VaultCategory?
    @Environment(AppStore.self) private var store

    var body: some View {
        let items = store.vault.items(in: category)
        ScrollView {
            Group {
                if items.isEmpty {
                    EmptyStateView(symbol: "key", title: "No accounts yet").card()
                } else {
                    VaultRowsCard(items: items)
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 12)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text(category?.label ?? "All Items"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
