import SwiftUI
import NookCore

/// Five navigation stacks kept alive side by side, with the floating tab bar on top.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

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
        }
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
        case .newExpense:
            AddTransactionView()
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
                ToastView(toast: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toastID) {
                        try? await Task.sleep(for: .seconds(2))
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
                .foregroundStyle(Pastel.mint.strong)
            Text(toast.text)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Theme.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1) }
        .shadow(color: Theme.shadow, radius: 16, x: 0, y: 6)
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
                router.perform(.expense, store: store)
            } label: {
                Label("Add Expense", systemImage: "creditcard")
            }
            Button {
                router.perform(.account, store: store)
            } label: {
                Label("Add Account", systemImage: "key")
            }
            Button {} label: {
                Label("Upload File", systemImage: "paperclip")
            }
            .disabled(true)
        } label: {
            CircleIcon(symbol: "plus")
        } primaryAction: {
            router.perform(primary, store: store)
        }
        .accessibilityLabel(Text("Add"))
        .accessibilityIdentifier("button.add")
    }
}
