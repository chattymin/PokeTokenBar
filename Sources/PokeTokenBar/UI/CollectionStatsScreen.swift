import SwiftUI

/// The Collection's statistics (the owner, 2026-11-10, his choice of the map): the counter's four rings, the Pokédex
/// as a map of generations by types, the categories and battle forms, and what is closest to done at the bottom. A
/// click on a cell, a row, a type or a tile shows who is missing. Done is blue and marked ✓, what is left orange and
/// counted: never the color alone.
@MainActor
struct CollectionStatsScreen: View {
    let store: CompanionStore
    let onBack: () -> Void
    @State private var selected: CollectionStats.Group?

    /// 18 cells and the generation labels fit the popover's width beside the scroller's lane.
    private static let cell: CGFloat = 15
    private static let label: CGFloat = 24
    static let done = Color(.sRGB, red: 0.25, green: 0.52, blue: 0.95)
    static let left = Color(.sRGB, red: 0.96, green: 0.56, blue: 0.13)

    var body: some View {
        let l = store.l
        let stats = store.collectionStats
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { onBack() } label: { Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
                Image(systemName: "square.grid.3x3.fill").foregroundStyle(.secondary)
                Text(l.dexStatsTitle).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    rings(stats, l)
                    section(l.dexStatsMapTitle)
                    map(stats, l)
                    Text(l.dexStatsMapHint).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let selected, !Self.isTile(selected) { details(selected, stats, l) }
                    section(l.dexStatsCategories)
                    tiles(stats, l)
                    if let selected, Self.isTile(selected) { details(selected, stats, l) }
                    let almost = stats.almostDone()
                    if !almost.isEmpty {
                        section(l.dexStatsAlmostDone)
                        ForEach(almost, id: \.self) { group in
                            StatsMissingCard(store: store, title: l.dexStatsGroup(group), tally: stats.tally(group))
                        }
                    }
                }
                .reservesScrollerLane()
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: 520, alignment: .top)
    }

    private static func isTile(_ group: CollectionStats.Group) -> Bool {
        switch group {
        case .category, .battle: true
        default: false
        }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 10, weight: .heavy)).kerning(0.6).foregroundStyle(.secondary)
    }

    // MARK: The rings

    private func rings(_ stats: CollectionStats, _ l: L) -> some View {
        HStack(spacing: 4) {
            StatsRing(title: l.dexStatsSpecies, owned: stats.species.owned, total: stats.species.total, color: Self.done)
            StatsRing(title: l.dexStatsForms, owned: stats.forms.owned, total: stats.forms.total, color: Self.done)
            StatsRing(title: l.dexStatsLines, owned: stats.lines.owned, total: stats.lines.total, color: Self.done)
            StatsRing(title: l.dexStatsShinies, owned: stats.shinies.owned, total: stats.shinies.total, color: Self.left)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: The map

    private func short(_ type: PokemonType, _ l: L) -> String { String(l.typeName(type).prefix(3)).uppercased() }

    private func map(_ stats: CollectionStats, _ l: L) -> some View {
        let types = PokemonType.allCases
        return Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                Color.clear.frame(width: Self.label, height: 28)
                ForEach(types, id: \.self) { type in
                    Text(short(type, l)).font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(-90)).fixedSize()
                        .frame(width: Self.cell, height: 28)
                        .background(type.color.opacity(selected == .type(type) ? 0.75 : 0.35))
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(.type(type)) }
                        .hoverTip("\(l.typeName(type)) · \(stats.tally(.type(type)).owned)/\(stats.tally(.type(type)).total)")
                }
            }
            ForEach(1...CollectionStats.generationCount, id: \.self) { generation in
                GridRow {
                    Text(l.dexStatsGenerationShort(generation)).font(.system(size: 9, weight: .bold))
                        .frame(width: Self.label, height: Self.cell)
                        .background(Color.secondary.opacity(selected == .generation(generation) ? 0.4 : 0.15))
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(.generation(generation)) }
                        .hoverTip("\(l.dexStatsGeneration(generation)) · \(stats.tally(.generation(generation)).owned)/\(stats.tally(.generation(generation)).total)")
                    ForEach(types, id: \.self) { type in
                        cell(.cell(generation: generation, type: type), stats, l)
                    }
                }
            }
        }
    }

    /// Blue the more it is complete, orange the more is left; its number says how many are left, ✓ once all are there.
    private func cell(_ group: CollectionStats.Group, _ stats: CollectionStats, _ l: L) -> some View {
        let tally = stats.tally(group)
        let lit: Bool = {
            switch (selected, group) {
            case (nil, _): return true
            case (.generation(let g)?, .cell(let generation, _)): return g == generation
            case (.type(let t)?, .cell(_, let type)): return t == type
            case (let s?, _): return s == group
            }
        }()
        return Group {
            if tally.total == 0 {
                Color.secondary.opacity(0.05)
            } else {
                Text(tally.isDone ? "✓" : "\(tally.left)").font(.system(size: tally.left > 9 ? 7 : 8.5, weight: .bold))
                    .monospacedDigit().foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Self.blend(tally.fraction))
                    .background(Color.secondary.opacity(0.12))
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(group) }
                    .hoverTip("\(l.dexStatsGroup(group)) · \(tally.owned)/\(tally.total)")
            }
        }
        .frame(width: Self.cell, height: Self.cell)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.white.opacity(selected == group ? 0.9 : 0), lineWidth: 1))
        .opacity(lit ? 1 : 0.35)
    }

    /// Blue once complete; else orange, the deeper the more is left (a cell nearly done is faint).
    static func blend(_ fraction: Double) -> Color {
        fraction >= 1 ? done : left.opacity(0.2 + 0.8 * (1 - max(0, min(1, fraction))))
    }

    private func toggle(_ group: CollectionStats.Group) {
        selected = selected == group ? nil : group
    }

    // MARK: The tiles

    private func tiles(_ stats: CollectionStats, _ l: L) -> some View {
        let groups: [CollectionStats.Group] = CollectionStats.Category.allCases.map { .category($0) }
            + CollectionStats.battleKinds.map { .battle($0) }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(groups, id: \.self) { group in
                let tally = stats.tally(group)
                Button { toggle(group) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(tally.owned)").font(.system(size: 15, weight: .heavy)).monospacedDigit()
                            Text("/\(tally.total)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            Spacer(minLength: 0)
                            if tally.isDone { Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(Self.done) }
                        }
                        Text(l.dexStatsGroup(group)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            .minimumScaleFactor(0.75)
                        StatsBar(fraction: tally.fraction)
                    }
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.secondary.opacity(selected == group ? 0.24 : 0.1)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func details(_ group: CollectionStats.Group, _ stats: CollectionStats, _ l: L) -> some View {
        StatsMissingCard(store: store, title: l.dexStatsGroup(group), tally: stats.tally(group))
    }
}

/// A ring of the counter: its share, its count under.
@MainActor
struct StatsRing: View {
    let title: String
    let owned: Int
    let total: Int
    let color: Color

    var body: some View {
        let fraction = total == 0 ? 0 : Double(owned) / Double(total)
        VStack(spacing: 2) {
            ZStack {
                // Inset by half the line: the stroke stays inside its frame, never cut by the scroll view.
                Circle().inset(by: 2.25).stroke(Color.secondary.opacity(0.2), lineWidth: 4.5)
                Circle().inset(by: 2.25).trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((fraction * 100).rounded(.down)))%").font(.system(size: 12, weight: .bold)).monospacedDigit()
            }
            .frame(width: 54, height: 54)
            Text(title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text("\(owned)/\(total)").font(.system(size: 9.5)).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

@MainActor
struct StatsBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.22))
                Capsule().fill(CollectionStatsScreen.done).frame(width: geometry.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 4)
    }
}

/// A set with its count and bar, and the Pokémon it still lacks, each named under the pointer.
@MainActor
struct StatsMissingCard: View {
    let store: CompanionStore
    let title: String
    let tally: CollectionStats.Tally

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(tally.owned)/\(tally.total)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                if tally.isDone {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(CollectionStatsScreen.done)
                } else {
                    Text("−\(tally.left)").font(.caption.weight(.bold)).foregroundStyle(CollectionStatsScreen.left).monospacedDigit()
                }
            }
            StatsBar(fraction: tally.fraction)
            if tally.isDone {
                Text(l.dexStatsAllThere).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(l.dexStatsLeft(tally.left)).font(.caption2.weight(.bold)).foregroundStyle(CollectionStatsScreen.left)
                WrappingHStack(spacing: 2, lineSpacing: 2) {
                    ForEach(tally.missing, id: \.self) { missing in
                        SpriteView(speciesID: missing.speciesID, size: 28, form: missing.form, sameScale: true)
                            .frame(width: 28, height: 28)
                            .speciesNameTooltip(missing.speciesID, form: missing.form, language: store.language)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .designSurface(cornerRadius: 10)
    }
}
