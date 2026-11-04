import SwiftUI
import Observation
import NookCore

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home, notes, vault, schedule, finance

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .notes: "Notes"
        case .vault: "Vault"
        case .schedule: "Schedule"
        case .finance: "Finance"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .notes: "square.and.pencil"
        case .vault: "lock"
        case .schedule: "calendar"
        case .finance: "chart.bar"
        }
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// Screens pushed inside a tab.
enum AppRoute: Hashable {
    case note(UUID)
    case vaultItem(UUID)
    case vaultList(VaultCategory?)
    case transactions
}

enum AppSheet: Identifiable, Hashable {
    case newEvent(LocalDate)
    case editEvent(UUID)
    case newTrip
    case editTrip(UUID)
    case newAnniversary
    case editAnniversary(UUID)
    case newExpense
    case editTransaction(UUID)
    /// A new vault entry (nil) or an existing one.
    case vaultEditor(UUID?)
    case changeMasterPassword
    case notifications
    case settings
    case pickDay

    var id: String {
        switch self {
        case .newEvent(let day): "newEvent-\(day.isoString)"
        case .editEvent(let id): "editEvent-\(id.uuidString)"
        case .newTrip: "newTrip"
        case .editTrip(let id): "editTrip-\(id.uuidString)"
        case .newAnniversary: "newAnniversary"
        case .editAnniversary(let id): "editAnniversary-\(id.uuidString)"
        case .newExpense: "newExpense"
        case .editTransaction(let id): "editTransaction-\(id.uuidString)"
        case .vaultEditor(let id): "vaultEditor-\(id?.uuidString ?? "new")"
        case .changeMasterPassword: "changeMasterPassword"
        case .notifications: "notifications"
        case .settings: "settings"
        case .pickDay: "pickDay"
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: LocalizedStringKey
    var symbol = "checkmark.circle.fill"
    var isWarning = false
}

/// The quick-add actions from the spec (section 3.3).
enum QuickAction {
    case note, event, trip, anniversary, expense, account
}

/// Which tab is showing, what is pushed in each tab, and which sheet is up.
@MainActor @Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var homePath: [AppRoute] = []
    var notesPath: [AppRoute] = []
    var vaultPath: [AppRoute] = []
    var schedulePath: [AppRoute] = []
    var financePath: [AppRoute] = []
    var activeSheet: AppSheet?
    /// The day shown by the home date pill and the schedule week strip.
    var selectedDay: LocalDate
    var scheduleSegment: ScheduleSegment = .calendar
    var toast: ToastMessage?

    init(today: LocalDate = .today()) {
        selectedDay = today
    }

    /// The tab bar hides while a screen is pushed.
    var isTabBarVisible: Bool { path(for: selectedTab).isEmpty }

    func path(for tab: AppTab) -> [AppRoute] {
        switch tab {
        case .home: homePath
        case .notes: notesPath
        case .vault: vaultPath
        case .schedule: schedulePath
        case .finance: financePath
        }
    }

    func setPath(_ path: [AppRoute], for tab: AppTab) {
        switch tab {
        case .home: homePath = path
        case .notes: notesPath = path
        case .vault: vaultPath = path
        case .schedule: schedulePath = path
        case .finance: financePath = path
        }
    }

    /// Tapping the current tab again goes back to its first screen.
    func select(_ tab: AppTab) {
        if tab == selectedTab {
            setPath([], for: tab)
        } else {
            selectedTab = tab
        }
    }

    func push(_ route: AppRoute, in tab: AppTab) {
        selectedTab = tab
        setPath(path(for: tab) + [route], for: tab)
    }

    func showSchedule(segment: ScheduleSegment = .calendar) {
        scheduleSegment = segment
        selectedTab = .schedule
    }

    func shiftSelectedDay(by days: Int) {
        selectedDay = selectedDay.adding(days: days)
    }

    func present(_ sheet: AppSheet) {
        activeSheet = sheet
    }

    func showToast(_ message: ToastMessage) {
        toast = message
    }

    func dismissToast(_ id: UUID) {
        if toast?.id == id {
            toast = nil
        }
    }

    /// Creates a blank note and opens it; the note is dropped again if left empty.
    func startNewNote(in store: AppStore, category: NoteCategory = .personal) {
        let note = store.createNote(category: category)
        selectedTab = .notes
        notesPath = [.note(note.id)]
    }

    func perform(_ action: QuickAction, store: AppStore) {
        switch action {
        case .note:
            startNewNote(in: store)
        case .event:
            present(.newEvent(selectedDay))
        case .trip:
            present(.newTrip)
        case .anniversary:
            present(.newAnniversary)
        case .expense:
            present(.newExpense)
        case .account:
            if store.vault.state == .unlocked {
                present(.vaultEditor(nil))
            } else {
                selectedTab = .vault
                vaultPath = []
                showToast(ToastMessage(text: "Unlock the vault to add an account", symbol: "lock.fill"))
            }
        }
    }
}
