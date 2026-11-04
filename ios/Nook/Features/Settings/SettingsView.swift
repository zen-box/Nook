import SwiftUI
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

/// Opened from the avatar. P0 has no account (spec 13.6), so this is local settings only.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance: Appearance = .system
    @State private var backupURL: URL?
    @State private var backupFailed = false

    var body: some View {
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
                            Text(verbatim: "Nook")
                                .font(.headline)
                            Text("Local profile · no account needed")
                                .font(NookFont.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
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
                    if let backupURL {
                        ShareLink(item: backupURL) {
                            Label("Export Backup", systemImage: "square.and.arrow.up")
                        }
                    } else if backupFailed {
                        Label("Backup could not be prepared", systemImage: "exclamationmark.triangle")
                    } else {
                        Label("Preparing backup…", systemImage: "hourglass")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Exports notes, schedule and finance records as a JSON file. Vault items are never included.")
                }
                Section("About") {
                    LabeledContent("Version", value: Self.version)
                    LabeledContent("Storage", value: String(localized: "Sample data in memory"))
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
            .task {
                do {
                    backupURL = try store.writeBackupFile()
                } catch {
                    backupFailed = true
                }
            }
        }
        .presentationCornerRadius(28)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

struct NotificationsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let reminders = store.reminders(now: context.date)
                ScrollView {
                    VStack(spacing: 12) {
                        if reminders.isEmpty {
                            EmptyStateView(
                                symbol: "bell.slash",
                                title: "No notifications",
                                message: "Reminders for today's events will show up here."
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
            .navigationTitle("Notifications")
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
