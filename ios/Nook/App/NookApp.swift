import SwiftUI

@main
struct NookApp: App {
    @State private var store: AppStore
    @State private var router = AppRouter()
    @AppStorage("appearance") private var appearance: Appearance = .system

    init() {
        _store = State(initialValue: AppStore.makeForLaunch())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .tint(Theme.accent)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
