import SwiftUI
import UniformTypeIdentifiers
import NookCore

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Opened from the avatar. There is no account: everything here is stored on this iPhone.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance: Appearance = .system
    @State private var budgetText = ""
    @State private var backupURL: URL?
    @State private var isImporting = false
    @State private var pendingRestore: Data?
    @State private var confirmRestore = false
    @State private var confirmVaultReset = false
    @State private var isChangingPassword = false
    @AppStorage("widgets.details") private var widgetDetails = false

    var body: some View {
        @Bindable var store = store
        @Bindable var vault = store.vault
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image("NookLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            TextField("Your name", text: $store.displayName)
                                .font(.headline)
                            Text("Local first. Sync is optional.")
                                .font(NookFont.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Picker("Currency", selection: $store.currencyCode) {
                        ForEach(Self.currencies(including: store.currencyCode), id: \.self) { code in
                            Text(verbatim: Self.currencyName(code)).tag(code)
                        }
                    }
                    HStack {
                        Text("Monthly Budget")
                        Spacer()
                        TextField("None", text: $budgetText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                } header: {
                    Text("Money")
                } footer: {
                    Text("Totals count only records in the selected currency.")
                }

                Section {
                    if vault.state == .needsSetup {
                        Text("Create the vault in the Vault tab first.")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Toggle("Unlock with \(DeviceAuthentication.methodName)", isOn: $vault.usesQuickUnlock)
                            .disabled(!DeviceAuthentication.isAvailable)
                        Button("Change Master Password") {
                            isChangingPassword = true
                        }
                        .disabled(vault.state != .unlocked)
                        Button("Reset Vault", role: .destructive) {
                            confirmVaultReset = true
                        }
                    }
                } header: {
                    Text("Vault")
                } footer: {
                    if !DeviceAuthentication.isAvailable {
                        Text("Set a passcode on this iPhone to unlock the vault with Face ID.")
                    }
                    if vault.state == .locked {
                        Text("Unlock the vault before changing its master password.")
                    }
                    if vault.usesQuickUnlock && vault.needsQuickUnlockEnrollment {
                        Text("Unlock once with your master password to enable quick unlock on this device.")
                    }
                    if let error = vault.quickUnlockError {
                        Text(error).foregroundStyle(Pastel.rose.strong)
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(Appearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    LabeledContent("App Language", value: Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? "简体中文" : "English")
                    Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                        Label("Change App Language", systemImage: "globe")
                    }.accessibilityIdentifier("settings.language")
                } header: { Text("Language") } footer: {
                    Text("Choose English or Simplified Chinese in iOS Settings. Nook follows your preferred app language.")
                }

                Section("Assistant") {
                    NavigationLink("AI Settings") { AISettingsView() }
                }
                Section {
                    Toggle("Show Details in Widgets", isOn: $widgetDetails)
                        .onChange(of: widgetDetails) { _, _ in WidgetPublisher.publish(store) }
                    switch store.widgetSharingStatus {
                    case .updated(let date):
                        LabeledContent("Shared Data Updated") { Text(date, style: .time) }
                    case .unavailable:
                        Text("Widget sharing is unavailable. The re-signed app and widget need matching App Groups entitlements.")
                            .font(.footnote).foregroundStyle(Pastel.rose.strong)
                    case .failed:
                        Text("Widget data could not be updated.").foregroundStyle(Pastel.rose.strong)
                    case .notPublished: Text("Widget data has not been published yet.").foregroundStyle(Theme.textSecondary)
                    }
                    Button("Refresh Widget Data") { WidgetPublisher.publish(store) }.accessibilityIdentifier("widgets.refresh")
                    NavigationLink("Widget Previews") { WidgetPreviewView() }
                    Text(verbatim: WidgetSnapshot.group).font(.caption.monospaced()).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                } header: { Text("Widgets") } footer: {
                    Text("Choose Schedule, Trips, Recent Note or Anniversary when adding a widget. Details are hidden by default. Note bodies, passwords and keys are never shared.")
                }

                Section {
                    NavigationLink("S3 Sync") { SyncSettingsView() }
                    NavigationLink("Encrypted Backup") { EncryptedBackupView() }
                    NavigationLink("Device Migration") { DeviceTransferView() }
                    if let backupURL {
                        ShareLink(item: backupURL) {
                            Label("Export Legacy JSON", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Label("Preparing backup…", systemImage: "hourglass")
                    }
                    Button {
                        isImporting = true
                    } label: {
                        Label("Import Legacy JSON", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Use Encrypted Backup for a complete backup. Legacy JSON includes records and attachment references, but no photo/audio files, vault or settings.")
                }

                Section("About") {
                    LabeledContent("Version", value: Self.version)
                    LabeledContent(
                        "Storage",
                        value: store.isTemporary ? String(localized: "Temporary – not saved") : String(localized: "On this iPhone")
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                readBackup(result)
            }
            .confirmationDialog("Replace your data?", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Replace with Backup", role: .destructive) {
                    restore()
                }
            } message: {
                Text("Notes, schedule and finance records on this iPhone will be replaced by the backup. The vault stays as it is.")
            }
            .confirmationDialog("Reset the vault?", isPresented: $confirmVaultReset, titleVisibility: .visible) {
                Button("Delete All Vault Items", role: .destructive) {
                    do {
                        try store.vault.reset()
                    } catch {
                        router.showToast(ToastMessage(text: "Couldn't save the change", symbol: "exclamationmark.triangle.fill", isWarning: true))
                    }
                }
            } message: {
                Text("This deletes every saved account and the master password. It can't be undone.")
            }
            .sheet(isPresented: $isChangingPassword) {
                ChangeMasterPasswordView()
                    .environment(store)
                    .environment(router)
                    .modifier(PrivacyShield())
                    .modifier(AppAppearance())
            }
        }
        .onAppear {
            budgetText = Self.budgetText(store.monthlyBudget)
        }
        .onChange(of: budgetText) { _, text in
            applyBudget(text)
        }
        .task {
            backupURL = try? store.writeBackupFile()
        }
        .presentationCornerRadius(28)
        .preferredColorScheme(appearance.colorScheme)
    }

    private func applyBudget(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            store.monthlyBudgetMinor = 0
        } else if let money = Money.parse(trimmed, currencyCode: store.currencyCode, decimalSeparator: Locale.current.decimalSeparator ?? "."),
                  money.minorUnits >= 0 {
            store.monthlyBudgetMinor = money.minorUnits
        }
    }

    private func readBackup(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            _ = try NookBackup.decode(data)
            pendingRestore = data
            confirmRestore = true
        } catch {
            router.showToast(ToastMessage(text: "This file is not a Nook backup", symbol: "exclamationmark.triangle.fill", isWarning: true))
        }
    }

    private func restore() {
        guard let data = pendingRestore else { return }
        pendingRestore = nil
        do {
            try store.restoreBackup(data)
            backupURL = try? store.writeBackupFile()
            router.showToast(ToastMessage(text: "Backup restored"))
        } catch {
            router.showToast(ToastMessage(text: "Couldn't restore the backup", symbol: "exclamationmark.triangle.fill", isWarning: true))
        }
    }

    private static func budgetText(_ budget: Money?) -> String {
        guard let budget else { return "" }
        return budget.decimalValue.formatted(.number.precision(.fractionLength(budget.minorUnitDigits)).grouping(.never))
    }

    private static let commonCurrencies = ["CNY", "USD", "EUR", "JPY", "HKD", "TWD", "MOP", "GBP", "KRW", "SGD", "AUD", "CAD", "CHF", "THB"]

    private static func currencies(including current: String) -> [String] {
        commonCurrencies.contains(current) ? commonCurrencies : [current] + commonCurrencies
    }

    private static func currencyName(_ code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(name) (\(code))"
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.2.0"
        let build = info?["CFBundleVersion"] as? String ?? "3"
        return "\(short) (\(build))"
    }
}

struct NotificationsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let reminders = store.todaysAgenda(now: context.date)
                ScrollView {
                    VStack(spacing: 12) {
                        Text("Today's upcoming events. System notifications follow each event's reminder setting.")
                            .font(NookFont.caption).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if reminders.isEmpty {
                            EmptyStateView(
                                symbol: "bell.slash",
                                title: "No upcoming events today",
                                message: "Add a timed event and choose a reminder to receive a notification."
                            )
                            .card()
                        } else {
                            ForEach(reminders) { event in
                                HStack(spacing: 12) {
                                    IconTile(symbol: event.category.symbol, pastel: event.category.pastel)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.title)
                                            .font(NookFont.rowTitle)
                                            .foregroundStyle(Theme.textPrimary)
                                        Group {
                                            if event.isAllDay {
                                                Text("All day")
                                            } else {
                                                Text("Starts at \(TimeText.time(event.start))")
                                            }
                                        }
                                        .font(NookFont.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .card()
                            }
                        }
                    }
                    .padding(Metrics.screenPadding)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Today's agenda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(28)
    }
}

/// Opened from the home date pill; the chosen day also drives the schedule week strip.
struct DayPickerSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            DatePicker("Day", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("Choose a Day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Today") {
                            router.selectedDay = LocalDate.today(in: store.timeZone)
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .onAppear { date = router.selectedDay.noon }
        .onChange(of: date) { _, newDate in
            router.selectedDay = LocalDate(newDate, timeZone: store.timeZone)
        }
        .presentationDetents([.fraction(0.62), .large])
        .presentationCornerRadius(28)
    }
}
