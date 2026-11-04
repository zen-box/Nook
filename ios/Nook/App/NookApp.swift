import SwiftUI

@main
struct NookApp: App {
    @State private var store = AppStore(seed: .make())
    @State private var router = AppRouter()
    @AppStorage("appearance") private var appearance: Appearance = .system

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
