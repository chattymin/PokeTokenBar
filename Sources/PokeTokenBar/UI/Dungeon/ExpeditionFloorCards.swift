import SwiftUI

// The expedition under way on Home, under Prof. Oak's bubble (the owner, 2026-11-16, choice C of q-mwj29kfss5): the
// whole dungeon as a row of strokes, the floor just crossed, the one under way, the next and the boss as cards, the team
// as battle HUDs, then the last two lines of the journal.

/// The whole dungeon in one row, a stroke a floor: those crossed in their event's color, the one under way longer and
/// blue, those ahead grey, the boss's in gold; on the return, the floor of a fall orange and crossed. Each crossed one
/// tells its journal on hover.
@MainActor
struct ExpeditionFloorDots: View {
    let store: CompanionStore
    let log: [ExpeditionLogEntry]
    let floors: Int
    /// The floor under way; nil on the return.
    let current: Int?
    /// The last floor reached.
    let reached: Int
    /// A lost run's last floor.
    var fellOn: Int? = nil

    init(store: CompanionStore, e: Expedition) {
        self.store = store
        log = e.log
        floors = e.floors
        current = min(e.floor, e.floors)
        reached = min(e.floor, e.floors)
    }

    init(store: CompanionStore, result r: ExpeditionResult) {
        self.store = store
        log = r.log
        floors = DungeonCatalog.dungeon(r.dungeon).floors
        current = nil
        reached = r.won ? floors : min(floors, r.log.map(\.floor).max() ?? 1)
        fellOn = !r.won && !r.roped ? reached : nil
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...max(1, floors), id: \.self) { n in
                let here = n == current
                let tip = n <= reached ? ExpeditionLogText.floor(n, log: log, floors: floors, store: store) : ""
                // The floor under way as wide as the others, white in a thick blue outline (the owner, 2026-11-16: blue
                // and shorter, it did not show among the floors crossed).
                Capsule().fill(here ? Color.white : color(n))
                    .overlay { if here { Capsule().strokeBorder(Design.actionColor, lineWidth: 3) } }
                    .frame(height: here ? 12 : 6)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        if n == fellOn {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(Color.readableOrange)
                                .offset(y: -9)
                        }
                    }
                    .contentShape(Rectangle().inset(by: -4))
                    .hoverTip(tip.isEmpty ? nil : tip)
            }
        }
        .frame(height: 12)
        .padding(.top, fellOn == nil ? 0 : 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.l.dungeonFloorOf(reached, floors))
    }

    private func color(_ n: Int) -> Color {
        if n == current { return Design.actionColor }
        if n == fellOn { return Color.readableOrange }
        if n > reached || (current != nil && n == reached) {
            return n == floors ? Color.yellow.opacity(0.45) : Color.primary.opacity(0.15)
        }
        return (ExpeditionLogText.symbol(floor: n, log: log)?.1 ?? Design.actionColor).opacity(0.75)
    }
}

/// A card of the floor cards' row: its small capital title, then what it holds; the floor under way outlined in blue,
/// one ahead dashed.
@MainActor
struct ExpeditionTile<Content: View>: View {
    let title: String
    var here = false
    var dashed = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 4) {
            Text(title.uppercased()).font(.system(size: 9, weight: .heavy)).kerning(0.4)
                .foregroundStyle(here ? Design.actionColor : .secondary).lineLimit(1).minimumScaleFactor(0.7)
            content().frame(height: 44)
        }
        .padding(.vertical, 7).padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(here ? 0.28 : 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(here ? Design.actionColor : Color.primary.opacity(dashed ? 0.25 : 0),
                          style: StrokeStyle(lineWidth: here ? 1.5 : 1, dash: dashed ? [3, 3] : [])))
    }
}

/// The floor just crossed (what happened there), the one under way (the lead walking it), the next (a "?") and the boss
/// (a silhouette until reached), as cards side by side.
@MainActor
struct ExpeditionFloorCards: View {
    let store: CompanionStore
    let e: Expedition

    private var l: L { store.l }

    enum Slot: Equatable {
        case crossed(Int), current(Int), ahead(Int), boss
    }

    /// The cards for the team on `floor` of `floors`: no floor crossed on the first, no next one when only the boss's
    /// floor is left (its card is the boss's).
    static func slots(floor: Int, floors: Int) -> [Slot] {
        let floor = min(max(1, floor), floors)
        return (floor > 1 ? [.crossed(floor - 1)] : []) + [.current(floor)]
            + (floor + 1 < floors ? [.ahead(floor + 1)] : []) + [.boss]
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(Self.slots(floor: e.floor, floors: e.floors).enumerated()), id: \.offset) { _, slot in
                switch slot {
                case .crossed(let n): crossed(n)
                case .current(let n): current(n)
                case .ahead(let n): ahead(n)
                case .boss: boss
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, here: Bool = false, dashed: Bool = false,
                                      @ViewBuilder _ content: @escaping () -> Content) -> some View {
        ExpeditionTile(title: title, here: here, dashed: dashed, content: content)
    }

    private func crossed(_ n: Int) -> some View {
        let event = ExpeditionLogText.symbol(floor: n, log: e.log)
        let kind = ExpeditionLogText.eventKind(floor: n, log: e.log)
        let tip = ExpeditionLogText.floor(n, of: e, store: store)
        return card(l.dungeonFloor(n)) {
            VStack(spacing: 3) {
                Image(systemName: event?.0 ?? "footprints").font(.system(size: 18, weight: .bold))
                    .foregroundStyle(event?.1 ?? .secondary)
                if let kind {
                    Text(l.dungeonEventName(kind)).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
        }
        .hoverTip(tip.isEmpty ? nil : tip)
    }

    private func current(_ n: Int) -> some View {
        let lead = e.team.first { !$0.isFainted } ?? e.team.first
        let tip = ExpeditionLogText.floor(n, of: e, store: store)
        return card(l.dungeonFloor(n), here: true) {
            if let lead {
                SpriteView(speciesID: lead.spec.speciesID, size: 44, animated: true, shiny: lead.spec.isShiny,
                           form: lead.spec.form)
                    .frame(width: 44, height: 44)
            }
        }
        .hoverTip(tip.isEmpty ? l.dungeonExploringNow : tip)
    }

    private func ahead(_ n: Int) -> some View {
        card(l.dungeonFloor(n), dashed: true) {
            Image(systemName: "questionmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.secondary)
        }
    }

    /// Hidden until reached (Q17), then whole.
    /// Whole once reached, a boss's icon before (the owner, 2026-11-16: never seen ahead, even met before, or a player
    /// could give up a run whose boss he does not like).
    private var boss: some View {
        let reached = e.log.contains { if case .bossReached = $0.kind { true } else { false } }
        let look = Self.bossLook(dungeon: e.dungeon, reachedHere: reached)
        return card(l.battleKind(.boss)) {
            ZStack(alignment: .topTrailing) {
                Self.bossFace(look, boss: e.boss)
                if look == .whole {
                    Image(systemName: "crown.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.yellow)
                }
            }
        }
        .hoverTip(l.dungeonFloorOf(e.floors, e.floors))
    }

    enum BossLook: Equatable { case whole, hidden }

    /// A boss not reached on this run stays hidden, met before or not; a challenge's and a hideout leader's are known,
    /// their cards announce them.
    static func bossLook(dungeon: DungeonID, reachedHere: Bool) -> BossLook {
        reachedHere || dungeon.isChallenge || dungeon.isHideout ? .whole : .hidden
    }

    @ViewBuilder
    static func bossFace(_ look: BossLook, boss: ExpeditionBoss, silhouette: Bool = false) -> some View {
        switch look {
        case .hidden:
            Image(systemName: "crown.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(Color.yellow.opacity(0.85))
                .frame(width: 44, height: 44)
        case .whole:
            SpriteView(speciesID: boss.speciesID, size: 40, shiny: !silhouette && boss.isShiny, form: boss.form,
                       isSilhouette: silhouette)
                .frame(width: 44, height: 44)
        }
    }
}

/// The team as a battle's HUDs, three a row: its sprite, its name, its HP bar (orange under a quarter), "K.O." once down.
@MainActor
struct ExpeditionTeamHUD: View {
    let store: CompanionStore
    let team: [ExpeditionMember]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(Array(team.enumerated()), id: \.offset) { _, member in hud(member) }
        }
    }

    /// The name its Pokédex record keeps, there at once (a card's image draws it too); PokéAPI's otherwise.
    @ViewBuilder
    private func name(_ member: ExpeditionMember) -> some View {
        if let record = store.state.dex.first(where: { $0.id == member.entryID }),
           let stored = store.dexStoredChainNames(record)?[member.spec.speciesID] {
            Text(stored)
        } else {
            PokemonNameLabel(.pokemonSpecies, String(member.spec.speciesID), language: store.language)
        }
    }

    private func hud(_ member: ExpeditionMember) -> some View {
        let share = Double(max(0, member.spec.hp)) / Double(max(1, member.spec.stats.hp))
        let color: Color = share < 0.25 ? .readableOrange : Design.actionColor
        return HStack(spacing: 6) {
            SpriteView(speciesID: member.spec.speciesID, size: 34, shiny: member.spec.isShiny, form: member.spec.form)
                .frame(width: 34, height: 34)
                .grayscale(member.isFainted ? 1 : 0).opacity(member.isFainted ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 3) {
                name(member)
                    .font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(member.isFainted ? .secondary : .primary)
                if member.isFainted {
                    Text(store.l.battleKO).font(.system(size: 10, weight: .heavy)).foregroundStyle(.secondary)
                } else {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.14))
                            Capsule().fill(color).frame(width: geo.size.width * share)
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.18)))
        .hoverTip(member.isFainted ? store.l.battleKO : "\(Int((share * 100).rounded())) %")
    }
}

/// A line of the journal on Home: its event in a square of its color, what happened, a fight's replay, its floor.
@MainActor
struct ExpeditionRecentRow: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let entry: ExpeditionLogEntry
    let floors: Int

    var body: some View {
        let l = store.l
        let (symbol, color) = ExpeditionLogText.entrySymbol(entry)
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.18)))
            Text(ExpeditionLogText.line(entry, floors: floors, store: store) ?? "")
                .font(.system(size: 12)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if case .battle(let battle) = entry.kind { replay(battle, l) }
            Text(l.dungeonFloor(entry.floor)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()
        }
    }

    /// Live while still being fought: the antenna joins it where it is.
    private func replay(_ battle: ExpeditionBattle, _ l: L) -> some View {
        let since = Int(Date().timeIntervalSince(entry.date) * 1000)
        let live = since >= 0 && since < battle.duration
        return Button {
            nav.replayStart = live ? since : 0
            nav.replayBattle = battle
        } label: {
            Group {
                if live { Image(systemName: "dot.radiowaves.left.and.right") } else { Text(l.dungeonReplay) }
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(Design.actionColor).lineLimit(1).fixedSize()
        }
        .buttonStyle(.plain)
        .hoverTip(live ? l.dungeonLive : nil)
        .accessibilityLabel(live ? l.dungeonLive : l.dungeonReplay)
    }
}

extension ExpeditionLogText {
    /// The kind of the floor's main event, as `symbol(floor:log:)` ranks them, for its name.
    static func eventKind(floor n: Int, log: [ExpeditionLogEntry]) -> ExpeditionEventKind? {
        let ranked: [(Int, ExpeditionEventKind)] = log.filter { $0.floor == n }.compactMap { entry in
            switch entry.kind {
            case .shiny: (0, .shiny)
            case .chest: (2, .chest)
            case .battle(let b): (4, b.kind)
            case .trap: (5, .trap)
            case .lost: (6, .lost)
            case .spring: (7, .spring)
            case .center: (8, .center)
            default: nil
            }
        }
        return ranked.min { $0.0 < $1.0 }?.1
    }

    /// One line's symbol and color: a floor's own for its events, the journal's for the rest.
    static func entrySymbol(_ entry: ExpeditionLogEntry) -> (String, Color) {
        if let own = symbol(floor: entry.floor, log: [entry]) { return own }
        switch entry.kind {
        case .branch(_, let risky): return (risky ? "dice.fill" : "dice", risky ? Color.readableOrange : Design.actionColor)
        case .revive: return ("cross.vial.fill", .pink)
        case .emergencyHeal: return ("heart.fill", .pink)
        case .capture(_, _, let caught): return ("circle.circle", caught ? Design.actionColor : .secondary)
        case .victory: return ("flag.checkered", Design.actionColor)
        case .defeat: return ("xmark.octagon", Color.readableOrange)
        case .abandon: return ("figure.walk", .secondary)
        default: return ("footprints", .secondary)
        }
    }
}
