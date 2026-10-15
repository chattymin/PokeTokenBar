import SwiftUI

/// One trade item row — sprite + name. Shared by the offer picker and the accept screen (what
/// I'm giving / what I'm receiving).
/// Shows both the name and the artwork to make clear "what" is being traded in an irreversible
/// trade (`#37` alone doesn't tell you).
/// The name shows the best available value immediately via `store.cachedTradeItemName`, then gets
/// filled in with the exact value via `resolveTradeItemName` — following the same
/// cache-first-then-async-correct approach as `CompanionView`.
@MainActor
struct TradeItemRow: View {
    let item: TradeItem
    let store: CompanionStore
    var spriteSize: CGFloat = 28

    @State private var name: String

    init(item: TradeItem, store: CompanionStore, spriteSize: CGFloat = 28) {
        self.item = item
        self.store = store
        self.spriteSize = spriteSize
        _name = State(initialValue: store.cachedTradeItemName(for: item))
    }

    var body: some View {
        HStack(spacing: 6) {
            SpriteView(speciesID: item.displaySpeciesID, size: spriteSize,
                       shiny: item.displayIsShiny, unownForm: item.displayUnownForm)
            Text(name)
        }
        .task {
            name = await store.resolveTradeItemName(for: item)
        }
    }
}
