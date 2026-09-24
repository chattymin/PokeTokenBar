/// Shared duplicate reduction for species and form selection. Keep every candidate selectable.
enum CollectionWeight {
    static func adjusted(_ weight: Int, isCollected: Bool) -> Int {
        isCollected ? max(1, weight / 2) : max(1, weight)
    }
}
