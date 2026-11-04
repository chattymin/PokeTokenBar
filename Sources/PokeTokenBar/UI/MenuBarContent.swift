/// Read both stores in the same observation scope so growth changes redraw without a usage poll.
@MainActor
enum MenuBarContent {
    static func lines(store: UsageStore, companion: CompanionStore) -> [String] {
        store.menuLines(growthText: store.showGrowthInMenu ? companion.menuGrowthText : nil)
    }
}
