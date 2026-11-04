import SwiftUI
import UIKit
import NookCore

/// P0 shell of the vault (spec 13.5.1: the real vault is P3). Items are demo entries without
/// any secrets; the copy button copies the account name only.
struct VaultView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var search = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                ScreenHeader(title: "Vault") {
                    AddMenuButton(primary: .account)
                }
                SearchField(prompt: "Search accounts or passwords", text: $search)
                    .padding(.horizontal, Metrics.screenPadding)
                Group {
                    if search.isEmpty {
                        SecureVaultHero()
                        categoryTiles
                        SectionHeader(title: "Accounts", actionTitle: "View All") {
                            router.push(.vaultList(.account), in: .vault)
                        }
                        .padding(.top, 4)
                        VaultRowsCard(items: Array(store.vaultItems(in: .account).prefix(4)))
                    } else {
                        let results = store.searchVault(search)
                        if results.isEmpty {
                            EmptyStateView(symbol: "magnifyingglass", title: "No matching items").card()
                        } else {
                            VaultRowsCard(items: results)
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
    }

    private var categoryTiles: some View {
        HStack(spacing: 10) {
            VaultCategoryTile(
                title: "All",
                symbol: "square.grid.2x2",
                pastel: .blue,
                count: store.vaultItems.count
            ) {
                router.push(.vaultList(nil), in: .vault)
            }
            ForEach(VaultCategory.allCases, id: \.self) { category in
                VaultCategoryTile(
                    title: category.label,
                    symbol: category.symbol,
                    pastel: category.pastel,
                    count: store.vaultItems(in: category).count
                ) {
                    router.push(.vaultList(category), in: .vault)
                }
            }
        }
    }
}

private struct SecureVaultHero: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Pastel.mint.strong)
                .frame(width: 54, height: 54)
                .background(Theme.surface.opacity(0.92), in: Circle())
                .shadow(color: Pastel.mint.strong.opacity(0.18), radius: 10, x: 0, y: 4)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Secure Vault")
                        .font(NookFont.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    PreviewBadge()
                }
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
                    UIPasteboard.general.string = item.subtitle
                    router.showToast(ToastMessage(text: "Account name copied", symbol: "doc.on.doc.fill"))
                }
                if index < items.count - 1 {
                    Hairline().padding(.leading, 66)
                }
            }
        }
        .card(padding: 0)
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
                        Text(item.title)
                            .font(NookFont.rowTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Text(item.subtitle)
                            .font(NookFont.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(verbatim: "••••••••")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityLabel(Text("Password hidden"))
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
            .accessibilityLabel(Text("Copy account name"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct VaultListView: View {
    let category: VaultCategory?
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VaultRowsCard(items: store.vaultItems(in: category))
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.vertical, 12)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text(category?.label ?? "All Items"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct VaultItemDetailView: View {
    let itemID: UUID
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if let item = store.vaultItem(id: itemID) {
                ScrollView {
                    VStack(spacing: Metrics.sectionSpacing) {
                        VStack(spacing: 10) {
                            IconTile(symbol: item.icon, pastel: item.pastel, size: 64)
                            Text(item.title)
                                .font(.system(.title2, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                            HStack(spacing: 6) {
                                Text(item.category.label)
                                PreviewBadge()
                            }
                            .font(NookFont.caption)
                            .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.vertical, 8)
                        VStack(spacing: 0) {
                            field(title: "Username", value: Text(item.subtitle)) {
                                UIPasteboard.general.string = item.subtitle
                                router.showToast(ToastMessage(text: "Account name copied", symbol: "doc.on.doc.fill"))
                            }
                            Hairline()
                            field(title: "Password", value: Text("Not stored in this preview"), action: nil)
                        }
                        .card(padding: 0)
                        Label("Passwords will be stored with end-to-end encryption in a later version. Nothing secret is saved yet.", systemImage: "lock.shield")
                            .font(NookFont.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.vertical, 12)
                }
            } else {
                ContentUnavailableView("Item not found", systemImage: "lock")
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(title: LocalizedStringKey, value: Text, action: (() -> Void)?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(NookFont.micro)
                    .foregroundStyle(Theme.textSecondary)
                value
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer(minLength: 8)
            if let action {
                Button(action: action) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 34, height: 34)
                        .background(Theme.primarySoft, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text("Copy"))
            }
        }
        .padding(16)
    }
}
