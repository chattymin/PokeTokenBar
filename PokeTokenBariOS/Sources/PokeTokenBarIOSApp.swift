import SwiftUI
import PokeTokenBarShared

@main
struct PokeTokenBarIOSApp: App {
    @State private var store = PhonePayloadStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                DashboardView()
                    .tabItem { Label("Home", systemImage: "house") }
                ShopView()
                    .tabItem { Label("Shop", systemImage: "cart") }
                BagView()
                    .tabItem { Label("Bag", systemImage: "bag") }
                CollectionView()
                    .tabItem { Label("Collection", systemImage: "square.grid.3x3") }
            }
            .environment(store)
            .preferredColorScheme(store.appearance.colorScheme)
        }
    }
}
