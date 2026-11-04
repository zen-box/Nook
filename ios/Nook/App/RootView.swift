import SwiftUI
import NookCore

/// Five navigation stacks side by side in a paging scroll view: swipe left or right to change
/// tab, or tap the floating tab bar on top.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("hint.swipeTabs") private var swipeHintShown = false
    /// The page the pager shows; follows `router.selectedTab` both ways.
    @State private var page: AppTab? = .home
    /// Set while the pager animates to a tapped tab, so pages passed on the way are ignored.
    @State private var scrollTarget: AppTab?

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()
            pager
            if router.isTabBarVisible {
                FloatingTabBar(selection: router.selectedTab, onSelect: { router.select($0) },
                               onAssistant: { router.present(.assistant) })
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
                .overlay(alignment: .top) { ToastOverlay() }
                .modifier(PrivacyShield())
                .modifier(AppAppearance())
        }
        .onChange(of: router.selectedTab) { _, tab in
            guard page != tab else { return }
            scrollTarget = tab
            withAnimation(.snappy(duration: 0.35)) { page = tab }
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                if scrollTarget == tab { scrollTarget = nil }
            }
        }
        .onChange(of: page) { _, current in
            guard scrollTarget == nil, let current, current != router.selectedTab else { return }
            router.selectedTab = current
        }
        .task {
            page = router.selectedTab
            if !swipeHintShown && !ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                swipeHintShown = true
                try? await Task.sleep(for: .seconds(1.2))
                router.showToast(ToastMessage(text: "Tip: swipe left or right to switch pages", symbol: "hand.draw"))
            }
        }
        .task {
            store.syncReminders()
            store.syncCoordinator.scheduleSync()
            WidgetPublisher.publish(store)
            if store.isTemporary {
                router.showToast(ToastMessage(text: "Storage unavailable: changes won't be kept", symbol: "exclamationmark.triangle.fill", isWarning: true))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The vault forgets its key and entries as soon as the app leaves the screen.
            if phase == .background {
                store.vault.lock()
            }
            if phase == .active { store.syncReminders(); store.syncCoordinator.scheduleSync(); WidgetPublisher.publish(store) }
        }
        .onChange(of: store.dataRevision) { _, _ in store.syncCoordinator.scheduleSync(); WidgetPublisher.publish(store) }
        .onChange(of: store.vault.syncRevision) { _, _ in store.syncCoordinator.scheduleSync() }
        .onChange(of: appearance) { _, _ in store.syncCoordinator.scheduleSync() }
        .onOpenURL { url in
            router.open(url, in: store)
        }
        .modifier(PrivacyShield())
        .onChange(of: store.saveFailures) { _, _ in
            router.showToast(ToastMessage(text: "Couldn't save the change", symbol: "exclamationmark.triangle.fill", isWarning: true))
        }
    }
}

extension RootView {
    /// Native paging: nested vertical lists keep scrolling normally, and horizontal paging is off
    /// while a screen is pushed so the back-swipe gesture stays with the navigation stack.
    private var pager: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    TabStack(tab: tab)
                        // `scrollDisabled` below is inherited; the pages' own lists stay scrollable.
                        .scrollDisabled(false)
                        .containerRelativeFrame(.horizontal)
                        .accessibilityHidden(router.selectedTab != tab)
                        .id(tab)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page, anchor: .center)
        .scrollIndicators(.hidden)
        .scrollDisabled(!router.isTabBarVisible)
        .ignoresSafeArea(.container)
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
    @Environment(AppStore.self) private var store

    var body: some View {
        switch sheet {
        case .newEvent(let day):
            EventEditorView(mode: .create(day))
        case .editEvent(let id):
            if let event = store.event(id: id), event.transport != nil, event.recurrence == nil {
                TripEditorView(tripID: event.planID, transportEventID: id)
            } else { EventEditorView(mode: .edit(id)) }
        case .editOccurrence(let id, let date):
            EventEditorView(mode: .occurrence(id, date))
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
        case .assistant:
            AgentView()
        case .tasks:
            TasksView()
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
        .accessibilityHint(Text("Tap to add. Touch and hold for more options."))
        .accessibilityIdentifier("button.add")
    }
}
