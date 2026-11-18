import SwiftUI

/// The pages of a long list, the way the Pokédex grid turns them: "‹ 3 / 12 ›", the scroll wheel turning them too
/// (`pagedByScrollWheel`). Every paged list of the app uses it, so they all look and behave alike (#183).
@MainActor
struct PageControl: View {
    @Binding var page: Int
    let pageCount: Int
    let l: L
    /// What the middle reads instead of "3 / 12", for pages grouped under a name ("November · 1 / 2", the costumes).
    var caption: String? = nil

    var body: some View {
        if pageCount > 1 {
            HStack(spacing: 0) {
                DexPageButton(forward: false, label: l.dexPagePrev) { page = max(0, page - 1) }
                    .disabled(page == 0)
                Text(caption ?? "\(page + 1) / \(pageCount)")
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel(caption ?? l.dexPageLabel(page + 1, pageCount))
                DexPageButton(forward: true, label: l.dexPageNext) { page = min(pageCount - 1, page + 1) }
                    .disabled(page >= pageCount - 1)
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(height: 18)
        }
    }
}

/// Cutting a list into pages.
enum Paging {
    static func pageCount(_ count: Int, size: Int) -> Int { max(1, (count + size - 1) / max(1, size)) }

    /// The page asked, kept within the pages there are (a filter may leave fewer).
    static func clamped(_ page: Int, count: Int, size: Int) -> Int { min(max(0, page), pageCount(count, size: size) - 1) }

    static func slice<T>(_ items: [T], page: Int, size: Int) -> [T] {
        let page = clamped(page, count: items.count, size: size)
        return Array(items.dropFirst(page * size).prefix(size))
    }
}

/// A page's content in the room left to it, the wheel turning the pages. A page taller than its room (a long language,
/// a card unfolded) scrolls instead, and the wheel then scrolls it: turning the page would leave its end unreachable.
@MainActor
struct PagedArea<Content: View>: View {
    @Binding var page: Int
    let pageCount: Int
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat = 0
    @State private var roomHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                .reservesScrollerLane()
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { roomHeight = $0 }
        .background {
            if contentHeight <= roomHeight + 0.5 {
                Color.clear.pagedByScrollWheel(page: $page, pageCount: pageCount)
            }
        }
    }
}

extension View {
    /// The scroll wheel or the trackpad turns the pages, one step per gesture, as on the Pokédex grid.
    func pagedByScrollWheel(page: Binding<Int>, pageCount: Int) -> some View {
        background(ScrollWheelPager { step in
            let next = DexScrollPager.pageAfterScroll(current: page.wrappedValue, pageCount: pageCount, step: step)
            if next != page.wrappedValue { page.wrappedValue = next }
        })
    }
}
