import SwiftUI
import PokeTokenBarShared

@main
struct PokeTokenBarIOSApp: App {
    @State private var store = PhonePayloadStore()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environment(store)
                .preferredColorScheme(store.appearance.colorScheme)
        }
    }
}
