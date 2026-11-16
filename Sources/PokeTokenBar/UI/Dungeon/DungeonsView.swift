import SwiftUI

/// The Dungeons tab (Q29, maquette 1): the Legendary Keys, the expedition under way, then every dungeon with its tier,
/// theme (R7), team, rules and length; locked, what is still missing; open, its bosses as met (Q17: a silhouette once
/// reached, whole once beaten, nothing before) and the way to its team screen.
@MainActor
struct DungeonsView: View {
    let store: CompanionStore
    let nav: PopoverNavigation

    var body: some View {
        let l = store.l
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    SectionTitle(text: l.dungeonsTab, systemImage: "map.fill")
                    Spacer(minLength: 4)
                    Button { nav.showingMyTeam = true } label: { Image(systemName: "person.3.fill") }
                        .buttonStyle(.borderless).hoverTip(l.myTeamTitle)
                    Button { nav.showingTypeChart = true } label: { Image(systemName: "tablecells") }
                        .buttonStyle(.borderless).hoverTip(l.typeChartTitle)
                    Button { nav.showingRunHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                        .buttonStyle(.borderless).hoverTip(l.runHistoryTitle)
                    ItemIconView(kind: .legendaryKey, size: 16)
                    Text("\(l.itemName(.legendaryKey)) ×\(store.itemCount(.legendaryKey))")
                        .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                }
                if let expedition = store.expedition {
                    underway(expedition, l)
                } else {
                    Text(l.dungeonsIntro).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // The villains' hideouts first while they keep something (issue #180), the most precious first.
                ForEach(store.villainStashes, id: \.team) { stash in
                    HideoutCard(store: store, team: stash.team) { nav.dungeonTeam = stash.team.hideoutID }
                }
                // The daily and weekly dungeons first, side by side: what they give changes with the day and the week.
                HStack(alignment: .top, spacing: 8) {
                    ForEach([DungeonID.daily, .weekly], id: \.self) { id in
                        ChallengeCard(store: store, id: id) { nav.dungeonTeam = id }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                ForEach(shown, id: \.self) { id in
                    DungeonCard(store: store, id: id, onPrepare: { nav.dungeonTeam = id }, onDetails: { nav.dungeonDetail = id })
                }
            }
            .reservesScrollerLane()
        }
        .frame(height: 520)
        // The day's and the week's bosses stay as first shown.
        .task { store.settleChallengeBosses() }
    }

    /// The Ruins of Alph show only once a Treasure Map, or a visit, made them known.
    private var shown: [DungeonID] {
        DungeonID.allCases.filter { id in
            !id.isChallenge && !id.isHideout && (id != .ruinsOfAlph || store.itemCount(.treasureMap) > 0 || store.dungeonProgress.wins(id) > 0)
        }
    }

    /// The expedition under way as a live card (the owner, 2026-11-09: the grey line among the cards did not show): a
    /// blue frame, a beating dot, the dungeon, its floors as a bar, the team with its HP.
    private func underway(_ e: Expedition, _ l: L) -> some View {
        let floor = min(e.floor, e.floors)
        let shape = RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                LiveDot()
                Text(l.expeditionLive.uppercased()).font(.system(size: 10, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(Design.actionColor)
                Spacer(minLength: 4)
                Button(l.dungeonSee) { nav.tab = .home }.buttonStyle(.pill(prominent: true))
            }
            HStack(spacing: 8) {
                DungeonIcon(id: e.dungeon, size: 30, boss: e.boss)
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.dungeonName(e.dungeon)).font(.callout.weight(.bold)).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(l.dungeonFloorOf(floor, e.floors) + " · " + l.dungeonBattles(e.battles))
                            .foregroundStyle(.secondary)
                        if store.dungeonNeedsAttention {
                            Label(l.expeditionWaitsForYou, systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(Color.readableOrange)
                        }
                    }
                    .font(.caption2).lineLimit(1)
                }
            }
            FloorTrack(floor: floor, floors: e.floors)
            HStack(spacing: 6) {
                ForEach(Array(e.team.enumerated()), id: \.offset) { _, member in
                    VStack(spacing: 2) {
                        SpriteView(speciesID: member.spec.speciesID, size: 26, shiny: member.spec.isShiny,
                                   form: member.spec.form, sameScale: true)
                            .frame(width: 28, height: 28)
                            .grayscale(member.isFainted ? 1 : 0).opacity(member.isFainted ? 0.45 : 1)
                        ExpeditionBar(value: Double(max(0, member.spec.hp)) / Double(max(1, member.spec.stats.hp)),
                                      color: Design.actionColor, height: 3)
                            .frame(width: 26)
                    }
                }
            }
        }
        .padding(10)
        .background(shape.fill(LinearGradient(colors: [Design.actionColor.opacity(0.16), Design.actionColor.opacity(0.05)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(shape.strokeBorder(Design.actionColor.opacity(0.75), lineWidth: 1.5))
    }
}

/// One dungeon's card.
@MainActor
struct DungeonCard: View {
    let store: CompanionStore
    let id: DungeonID
    let onPrepare: () -> Void
    /// Opens the dungeon's page (`DungeonDetailScreen`); nil hides the button.
    var onDetails: (() -> Void)? = nil
    /// The bosses a card shows, the latest met; the others make a count.
    static let bossesShown = 4

    var body: some View {
        let l = store.l
        let dungeon = DungeonCatalog.dungeon(id)
        let (size, rules) = store.teamRules(id)
        // A dungeon won before a rule changed stays open (`isDungeonOpen`).
        let unmet = store.isDungeonOpen(id) ? [] : store.unmetUnlocks(id)
        let wins = store.dungeonProgress.wins(id)
        // A hero card like Home's (the owner, 2026-11-10: "là on dirait un terminal"), washed with the dungeon's types,
        // its diorama large; grey while it is locked.
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                DungeonIcon(id: id, size: 96)
                    .shadow(color: Self.colors(id)[0].opacity(unmet.isEmpty ? 0.6 : 0), radius: 10)
                    .grayscale(unmet.isEmpty ? 0 : 1).opacity(unmet.isEmpty ? 1 : 0.5)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Badge("T\(dungeon.tier.rawValue)", tint: .secondary, style: .solid, size: 10)
                        status(unmet: unmet, wins: wins, l)
                        Spacer(minLength: 4)
                        if let onDetails {
                            Button(action: onDetails) { Image(systemName: "info.circle") }
                                .buttonStyle(.borderless).font(.caption)
                                .hoverTip(l.dungeonDetailsButton)
                                .accessibilityLabel(l.dungeonDetailsButton)
                        }
                    }
                    Text(l.dungeonName(id)).font(.system(size: 19, weight: .bold, design: .rounded)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    // Each badge whole, the row going to a second line beside the diorama: Mt. Coronet's four did not
                    // fit (`DungeonLayoutTests`).
                    WrappingHStack(spacing: 3, lineSpacing: 3) {
                        ForEach(dungeon.themeTypes, id: \.self) { type in
                            Badge(l.typeName(type).uppercased(), tint: .type(type), size: 10).fixedSize()
                        }
                    }
                    Text(([l.dungeonTeamSize(size)] + rules.map(l.dungeonRule)).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if unmet.isEmpty {
                // The entry goes under the bosses when both do not fit on one line (a long entry text, a German button).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        bosses(dungeon, l)
                        Spacer(minLength: 4)
                        entry(l)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        bosses(dungeon, l)
                        HStack { Spacer(minLength: 0); entry(l) }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(dungeon.unlocks.enumerated()), id: \.offset) { _, unlock in
                        let met = store.isMet(unlock)
                        Label(store.unlockLine(unlock), systemImage: met ? "checkmark.circle.fill" : "circle")
                            .font(.caption).foregroundStyle(met ? .primary : .secondary)
                    }
                }
            }
        }
        .heroCard(colors: unmet.isEmpty ? Self.colors(id) : [.gray])
    }

    /// The card's colors: its first two types', gray for none; a challenge's own color (`challengeColor`).
    static func colors(_ id: DungeonID) -> [Color] {
        if id.isChallenge { return [challengeColor(id)] }
        let colors = DungeonCatalog.dungeon(id).themeTypes.prefix(2).map(\.color)
        return colors.isEmpty ? [.gray] : Array(colors)
    }

    /// The day's in warm orange, the week's in violet: the two never mixed up.
    static func challengeColor(_ id: DungeonID) -> Color {
        id == .daily ? Color(.sRGB, red: 1.0, green: 0.62, blue: 0.25) : Color(.sRGB, red: 0.62, green: 0.40, blue: 1.0)
    }

    @ViewBuilder
    private func status(unmet: [DungeonUnlock], wins: Int, _ l: L) -> some View {
        if !unmet.isEmpty {
            Label(l.dungeonLocked, systemImage: "lock.fill").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        } else if wins > 0 {
            Text(l.dungeonWins(wins)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        } else {
            Badge(l.dungeonNew.uppercased(), tint: .blue, style: .tinted)
        }
    }

    /// Q17: the bosses beaten whole, those only reached as silhouettes, a "?" for each one not met yet (#137): how many
    /// wait there, never who.
    private func bosses(_ dungeon: Dungeon, _ l: L) -> some View {
        let slots = BossSlots(store: store, id: id, dungeon: dungeon, size: 30, shownAtMost: Self.bossesShown)
        return HStack(spacing: 2) {
            ForEach(Array(slots.slots.enumerated()), id: \.offset) { _, slot in slot.view(size: 30, language: store.language) }
            if slots.hidden > 0 {
                Text("+\(slots.hidden)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).fixedSize()
            }
        }
    }

    @ViewBuilder
    private func entry(_ l: L) -> some View {
        let keys = store.keysToEnter(id)
        HStack(spacing: 6) {
            if keys > 0 {
                // Never broken in two: the row puts the entry under the bosses instead.
                Text(l.dungeonEntryKeys(keys, key: l.itemName(.legendaryKey))).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize()
            } else if id == .ruinsOfAlph {
                Text(l.dungeonEntryMap(l.itemName(.treasureMap))).font(.caption2).foregroundStyle(.secondary).fixedSize()
            }
            Text(TokenFormatter.compact(store.dungeonCost(id))).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .fixedSize().hoverTip(l.dungeonCost(TokenFormatter.compact(store.dungeonCost(id))))
            Button(store.dungeonProgress.wins(id) > 0 ? l.dungeonGoAgain : l.dungeonPrepare, action: onPrepare)
                .buttonStyle(.pill(prominent: true))
                .disabled(!store.canEnter(id))
                .hoverTip(store.expedition != nil ? l.dungeonOneAtATime : nil)
        }
    }
}

/// The daily or weekly dungeon (2026-11-02), half a row: its boss, the form it gives, then what to do or why not now.
/// Its length, cost, one try and difficulty are on hover.
@MainActor
private struct ChallengeCard: View {
    let store: CompanionStore
    let id: DungeonID
    let onPrepare: () -> Void

    var body: some View {
        let l = store.l
        let dungeon = DungeonCatalog.dungeon(id)
        let unmet = store.unmetUnlocks(id)
        // A run under way keeps its own boss past midnight (or the week's turn): the card shows it, not the next one.
        let running = store.expedition.flatMap { e in
            e.dungeon == id ? BattleForms.form(speciesID: e.boss.speciesID, form: e.boss.form) : nil
        }
        let boss = running ?? store.challengeBoss(id)
        let tried = store.challengeTried(id)
        // The one try lost: the card greyed and its boss crossed out (the owner, 2026-11-09); won, said in blue.
        let outcome = running == nil ? store.challengeOutcome(id) : nil
        let lost = outcome == false
        // The week's won waits for Monday (the owner, 2026-11-10: one of its forms a week at most).
        let weekWon = id == .weekly && outcome == true
        let details = [l.dungeonFloors(dungeon.floors),
                       l.dungeonCost(TokenFormatter.compact(store.dungeonCost(id))),
                       l.challengeOneTryADay].joined(separator: " · ")
        let color = DungeonCard.challengeColor(id)
        VStack(alignment: .leading, spacing: 6) {
            Text(l.challengeCardTitle(id).uppercased()).font(.system(size: 10, weight: .heavy)).kerning(0.6)
                .foregroundStyle(unmet.isEmpty && !lost ? color : .secondary).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            // The boss large and centred, its name under it (the owner, 2026-11-09: at 36 points beside the title it was
            // hard to make out). It fills its box: at one scale with the others, a small form stayed small.
            Group {
                if let boss {
                    // Moving, as the Pokémon raised on Home (the owner, 2026-11-16); a battle form without an animation
                    // shows its still (`BattleForms.isAnimated`).
                    SpriteView(speciesID: boss.speciesID, size: 92, animated: unmet.isEmpty && !lost, form: boss.form)
                        .shadow(color: color.opacity(unmet.isEmpty && !lost ? 0.7 : 0), radius: 12)
                } else {
                    Image(systemName: id == .daily ? "sun.max.fill" : "calendar").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 92)
            .grayscale(unmet.isEmpty && !lost ? 0 : 1).opacity(unmet.isEmpty && !lost ? 1 : 0.5)
            .overlay { if lost { CrossMark().frame(width: 70, height: 70) } }
            .frame(maxWidth: .infinity)
            if let boss {
                VStack(spacing: 2) {
                    BattleFormTitle(form: boss, language: store.language)
                        .font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(2).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    // Only when the form is the player's already (the owner, 2026-11-09: a form not won says nothing);
                    // a run's boss won meanwhile says it too.
                    if store.dungeonProgress.battleForms.contains(boss.key) {
                        Label(l.challengeFormOwned, systemImage: "checkmark.circle")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
            Group {
                if running != nil {
                    Label(l.challengeUnderway, systemImage: "figure.walk")
                } else if let unlock = unmet.first {
                    Label(l.dungeonUnlock(unlock), systemImage: "lock.fill")
                } else if boss == nil {
                    Label(l.challengeAllWonShort, systemImage: "checkmark.seal.fill")
                } else if let outcome {
                    VStack(alignment: .leading, spacing: 2) {
                        if outcome {
                            Label(weekWon ? l.challengeWonWeek : l.challengeWonDay, systemImage: "checkmark.seal.fill")
                                .fontWeight(.semibold).foregroundStyle(Design.actionColor)
                        } else {
                            Label(l.challengeLostDay, systemImage: "xmark")
                                .fontWeight(.semibold).foregroundStyle(Color.readableOrange)
                        }
                        // The day's dungeon draws a new boss tomorrow; the week's, lost, keeps its boss for tomorrow's try,
                        // won, draws a new one on Monday.
                        Text(id == .daily ? l.challengeNextDay : weekWon ? l.challengeNextWeek : l.challengeTryTomorrow)
                    }
                } else if tried {
                    Label(l.challengeTriedShortDay, systemImage: "hourglass")
                } else {
                    Button(l.dungeonPrepare, action: onPrepare)
                        .buttonStyle(.pill(prominent: true))
                        .disabled(!store.canEnter(id))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        // Both cards as high as the taller (the row is fixed to its height): the week's title takes two lines.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .heroCard(colors: [unmet.isEmpty && !lost ? color : .gray], padding: 10)
        .opacity(lost ? 0.8 : 1)
        .hoverTip(boss == nil && unmet.isEmpty ? l.challengeAllWon
                  : weekWon ? l.challengeWeekWonTip
                  : tried ? l.challengeTriedToday
                  : store.expedition != nil && unmet.isEmpty ? l.dungeonOneAtATime
                  : details + "\n" + l.challengeHard)
    }
}

/// A dungeon's icon (R15): its diorama, drawn in code; a daily or weekly dungeon's boss instead, known from the start
/// (the owner, 2026-11-03: "on doit voir le boss pas un décor").
@MainActor
struct DungeonIcon: View {
    let id: DungeonID
    var size: CGFloat = 32
    var boss: ExpeditionBoss?
    /// A challenge's boss moving, where it is shown large (Home's card; the owner, 2026-11-16); the small icons of the
    /// lists stay still.
    var animated = false

    var body: some View {
        Group {
            if id.isChallenge, let boss {
                SpriteView(speciesID: boss.speciesID, size: size, animated: animated, form: boss.form, sameScale: true)
            } else if let image = DungeonSprites.image(id) {
                Image(decorative: image, scale: 1).resizable().interpolation(size.truncatingRemainder(dividingBy: 32) == 0 ? .none : .high)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A dungeon's bosses as a player knows them (Q17, #137): beaten whole, reached as a silhouette, a "?" when not met.
/// The Ruins of Alph, whose boss is any final species, show those met and one "?" for the rest.
@MainActor
struct BossSlots {
    @MainActor
    enum Slot {
        /// `beaten`: shown whole, else a silhouette (a secret boss: once caught).
        case met(speciesID: Int, beaten: Bool, form: PokemonForm? = nil)
        case unknown

        @ViewBuilder
        func view(size: CGFloat, language: AppLanguage) -> some View {
            switch self {
            case .met(let species, let beaten, let form):
                SpriteView(speciesID: species, size: size, form: form, isSilhouette: !beaten, sameScale: true)
                    .speciesNameTooltip(species, form: form, language: language)
            case .unknown:
                Text("?").font(.system(size: size * 0.45, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: size / 4).strokeBorder(.secondary.opacity(0.45),
                                                                                    style: StrokeStyle(lineWidth: 1, dash: [3])))
            }
        }
    }

    /// Up to `shownAtMost` slots, the latest met last; `hidden` more met past them.
    private(set) var slots: [Slot]
    let hidden: Int
    let met: Int

    init(store: CompanionStore, id: DungeonID, dungeon: Dungeon, size: CGFloat, shownAtMost: Int) {
        let progress = store.dungeonProgress
        let reached = dungeon.bosses.filter { progress.bossesReached.contains(DungeonProgress.bossKey(id, $0)) }
        // Whole once caught in this dungeon, a silhouette until then, beaten or not (the owner, 2026-11-12: a shiny
        // Mewtwo missed showed as caught, the species already his from an egg).
        func slot(_ species: Int) -> Slot {
            .met(speciesID: species, beaten: progress.caughtInDungeon(id, species))
        }
        met = reached.count
        if dungeon.bosses.count <= shownAtMost {
            // Every boss has its place, in the catalog's order: its "?" until it is met.
            slots = dungeon.bosses.map { reached.contains($0) ? slot($0) : .unknown }
            hidden = 0
        } else {
            let shown = Array(reached.suffix(shownAtMost - 1))
            slots = shown.map(slot) + [.unknown]
            hidden = reached.count - shown.count
        }
        // A secret boss shows only once met, after the others, a silhouette until caught (the owner, 2026-11-10): no
        // "?" gives it away, and the bosses' count stays the dungeon's own.
        let secrets = SecretBosses.candidates(id).filter { progress.secretsMet.contains(SecretBosses.key(id, $0)) }
        slots += secrets.map { .met(speciesID: $0.speciesID, beaten: progress.secretsCaught.contains(SecretBosses.key(id, $0)),
                                    form: $0.form) }
    }
}

/// A cross over a lost challenge's boss: two strokes with round ends, orange on a light outline so it reads on any
/// sprite (the owner, 2026-11-09: "fais la croix plus propre").
@MainActor
struct CrossMark: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let inset = size.width * 0.12
            path.move(to: CGPoint(x: inset, y: inset))
            path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
            path.move(to: CGPoint(x: size.width - inset, y: inset))
            path.addLine(to: CGPoint(x: inset, y: size.height - inset))
            context.stroke(path, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            context.stroke(path, with: .color(.readableOrange), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

/// A dot that beats while something runs; still with Reduce Motion.
@MainActor
struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = false

    var body: some View {
        Circle().fill(Design.actionColor).frame(width: 7, height: 7)
            .background(Circle().fill(Design.actionColor.opacity(0.35)).scaleEffect(beat ? 2.2 : 1).opacity(beat ? 0 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { beat = true }
            }
    }
}

/// The floors as a bar: what was walked filled, a tick per floor.
@MainActor
struct FloorTrack: View {
    let floor: Int
    let floors: Int

    var body: some View {
        VStack(spacing: 2) {
            ExpeditionBar(value: floors > 0 ? Double(floor) / Double(floors) : 0, color: Design.actionColor, height: 6)
            HStack(spacing: 0) {
                ForEach(0...max(1, floors), id: \.self) { i in
                    Rectangle().fill(Color.secondary.opacity(i <= floor ? 0.5 : 0.25)).frame(width: 1.5, height: 4)
                    if i < floors { Spacer(minLength: 0) }
                }
            }
        }
    }
}

extension CompanionStore {
    /// An unlock's line, Mt. Coronet's bosses with how many are done ("12/28").
    func unlockLine(_ unlock: DungeonUnlock) -> String {
        guard case .caughtBosses(let ids) = unlock else { return l.dungeonUnlock(unlock) }
        let total = DungeonCatalog.bosses(of: ids).count
        return l.dungeonUnlock(unlock) + " · \(total - bossesLeft(ids).count)/\(total)"
    }
}
