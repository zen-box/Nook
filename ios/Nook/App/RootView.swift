import SwiftUI
import NookCore

/// Five navigation stacks kept alive side by side, with the floating tab bar on top.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()
            ForEach(AppTab.allCases) { tab in
                let isActive = router.selectedTab == tab
                TabStack(tab: tab)
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                    .accessibilityHidden(!isActive)
            }
            if router.isTabBarVisible {
                FloatingTabBar(selection: router.selectedTab) { tab in
                    router.select(tab)
                }
                .ignoresSafeArea(.keyboard)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: router.isTabBarVisible)
        .overlay(alignment: .top) {
            ToastOverlay()
        }
        .sheet(item: $router.activeSheet) { sheet in
            SheetContent(sheet: sheet)
                .environment(store)
                .environment(router)
                .modifier(PrivacyShield())
                .modifier(AppAppearance())
        }
        .task {
            store.syncReminders()
            if store.isTemporary {
                router.showToast(ToastMessage(text: "Storage unavailable: changes won't be kept", symbol: "exclamationmark.triangle.fill", isWarning: true))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The vault forgets its key and entries as soon as the app leaves the screen.
            if phase == .background {
                store.vault.lock()
            }
        }
        .modifier(PrivacyShield())
        .onChange(of: store.saveFailures) { _, _ in
            router.showToast(ToastMessage(text: "Couldn't save the change", symbol: "exclamationmark.triangle.fill", isWarning: true))
        }
    }
}

/// Covers content while inactive without cancelling the system authentication prompt.
struct PrivacyShield: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.overlay {
            if scenePhase != .active {
                Theme.background.ignoresSafeArea()
                    .overlay { Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(Theme.textSecondary) }
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Each presentation observes the preference, including a sheet that is already open.
struct AppAppearance: ViewModifier {
    @AppStorage("appearance") private var appearance: Appearance = .system

    func body(content: Content) -> some View {
        content.preferredColorScheme(appearance.colorScheme)
    }
}

private struct TabStack: View {
    let tab: AppTab
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        switch tab {
        case .home:
            NavigationStack(path: $router.homePath) {
                HomeView().appDestinations()
            }
        case .notes:
            NavigationStack(path: $router.notesPath) {
                NotesView().appDestinations()
            }
        case .vault:
            NavigationStack(path: $router.vaultPath) {
                VaultView().appDestinations()
            }
        case .schedule:
            NavigationStack(path: $router.schedulePath) {
                ScheduleView().appDestinations()
            }
        case .finance:
            NavigationStack(path: $router.financePath) {
                FinanceView().appDestinations()
            }
        }
    }
}

extension View {
    func appDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            RouteDestination(route: route)
        }
    }
}

private struct RouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .note(let id):
            NoteEditorView(noteID: id)
        case .vaultItem(let id):
            VaultItemDetailView(itemID: id)
        case .vaultList(let category):
            VaultListView(category: category)
        case .transactions:
            AllTransactionsView()
        }
    }
}

private struct SheetContent: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .newEvent(let day):
            EventEditorView(mode: .create(day))
        case .editEvent(let id):
            EventEditorView(mode: .edit(id))
        case .newTrip:
            TripEditorView(tripID: nil)
        case .editTrip(let id):
            TripEditorView(tripID: id)
        case .newAnniversary:
            AnniversaryEditorView(anniversaryID: nil)
        case .editAnniversary(let id):
            AnniversaryEditorView(anniversaryID: id)
        case .newExpense:
            AddTransactionView(entryID: nil)
        case .editTransaction(let id):
            AddTransactionView(entryID: id)
        case .vaultEditor(let id):
            VaultItemEditorView(itemID: id)
        case .changeMasterPassword:
            ChangeMasterPasswordView()
        case .notifications:
            NotificationsView()
        case .settings:
            SettingsView()
        case .pickDay:
            DayPickerSheet()
        }
    }
}

// MARK: - Toast

private struct ToastOverlay: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack {
            if let toast = router.toast {
                let toastID = toast.id
                let seconds = toast.isWarning ? 3 : 2
                ToastView(toast: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toastID) {
                        try? await Task.sleep(for: .seconds(seconds))
                        router.dismissToast(toastID)
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: router.toast)
        .padding(.top, 6)
    }
}

private struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.symbol)
                .foregroundStyle(toast.isWarning ? Pastel.rose.strong : Pastel.mint.strong)
            Text(toast.text)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(Theme.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1) }
        .shadow(color: Theme.shadow, radius: 16, x: 0, y: 6)
        .padding(.horizontal, Metrics.screenPadding)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - "+" button

/// Round "+" button: a tap runs the screen's main action, a long press shows every quick-add
/// action (spec section 3.3).
struct AddMenuButton: View {
    let primary: QuickAction
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        Menu {
            Button {
                router.perform(.note, store: store)
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }
            Button {
                router.perform(.event, store: store)
            } label: {
                Label("New Event", systemImage: "calendar.badge.plus")
            }
            Button {
                router.perform(.trip, store: store)
            } label: {
                Label("New Trip", systemImage: "airplane.departure")
            }
            Button {
                router.perform(.anniversary, store: store)
            } label: {
                Label("New Anniversary", systemImage: "gift")
            }
            Button {
                router.perform(.expense, store: store)
            } label: {
                Label("Add Expense", systemImage: "creditcard")
            }
            Button {
                router.perform(.account, store: store)
            } label: {
                Label("Add Account", systemImage: "key")
            }
        } label: {
            CircleIcon(symbol: "plus")
        } primaryAction: {
            router.perform(primary, store: store)
        }
        .accessibilityLabel(Text("Add"))
        .accessibilityIdentifier("button.add")
    }
}
