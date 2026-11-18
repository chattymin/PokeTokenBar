import SwiftUI

/// A dungeon battle played at its own pace (maquette 5): the same seed replays it to the millisecond, at half its speed
/// (the owner, 2026-11-09: "le combat passe trop vite"). Each Pokémon on the field has its HP bar (blue) and its cast
/// bar (purple) under its sprite; below, the whole battle as a journal to scroll back through, each side's moves on its
/// own side (`BattleLog`).
@MainActor
struct BattleReplayView: View {
    let store: CompanionStore
    let battle: ExpeditionBattle
    /// Where it starts, in milliseconds: a battle still being fought opens at its present moment.
    var startAt = 0
    let onBack: () -> Void

    @State private var outcome: BattleOutcome?
    @State private var lines: [BattleLogLine] = []
    @State private var elapsed = 0
    @State private var playing = true

    /// A frame every 100 ms, the battle moving on by half of it.
    private static let step = 100
    static let speed = 0.5

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button { onBack() } label: { Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
                Text(l.battleKind(battle.kind)).font(.headline)
                Text(Self.clock(elapsed)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let outcome {
                let frame = BattleFrame.at(elapsed, setup: outcome.setup, events: outcome.events)
                // #134 (the owner, 2026-11-06): the battle as an arena, face to face.
                BattleArena(store: store, frame: frame, setup: outcome.setup, elapsed: elapsed)
                journal(outcome.setup)
                HStack {
                    Button(playing ? l.battlePause : l.battlePlay) { playing.toggle() }
                        .buttonStyle(.pill())
                    Spacer()
                    if elapsed >= outcome.duration {
                        Label(outcome.winner == 0 ? l.battleWon : l.battleLost,
                              systemImage: outcome.winner == 0 ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(outcome.winner == 0 ? Design.actionColor : .orange)
                    } else {
                        Button(l.battleSkip) { elapsed = outcome.duration }
                            .buttonStyle(.pill())
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: 520, alignment: .top)
        .task {
            let setup = battle.setup
            let ran = await BattleEngine.offMain { BattleEngine.run(setup) }
            elapsed = min(max(0, startAt), ran.duration)
            lines = BattleLog.lines(ran.events, setup: ran.setup)
            outcome = ran
            while !Task.isCancelled, elapsed < ran.duration {
                try? await Task.sleep(for: .milliseconds(Self.step))
                if playing { elapsed = min(ran.duration, elapsed + Int(Double(Self.step) * Self.speed)) }
            }
        }
    }

    static func clock(_ ms: Int) -> String { String(format: "%d:%02d", ms / 60_000, ms / 1000 % 60) }

    /// Everything said so far, the latest at the bottom, kept in view while the battle plays; paused, it can be scrolled
    /// back through.
    private func journal(_ setup: BattleSetup) -> some View {
        let shown = lines.prefix { $0.time <= elapsed }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(shown) { line in
                        BattleLogRow(store: store, line: line, setup: setup).id(line.id)
                    }
                }
                .reservesScrollerLane()
            }
            .frame(maxHeight: .infinity)
            .onChange(of: shown.count) {
                if playing, let last = shown.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

/// #134, the battle as an arena (maquette of 2026-11-06): the foes up and to the right, the team down and to the left,
/// face to face on their grounds, each with its plate (name, HP written and drawn, the move being cast, its status),
/// the benches as balls; the last move that landed in a banner with its type and how effective it was, its damage
/// rising off the Pokémon hit, which shakes.
@MainActor
struct BattleArena: View {
    let store: CompanionStore
    let frame: BattleFrame
    let setup: BattleSetup
    let elapsed: Int

    /// How long a hit stays in the banner and its damage on screen.
    static let hitShown = 1_100
    /// The leap of the one hitting and the knock-back of the one hit, in battle milliseconds (the replay runs at half
    /// speed: a quarter of a second on screen).
    static let hopLength = 130.0
    static let recoilLength = 150.0

    /// 0 → 1 → 0 over `length` from the hit, nothing after.
    static func bump(_ age: Double, length: Double) -> Double {
        guard age >= 0, age < length else { return 0 }
        return sin(Double.pi * age / length)
    }

    var body: some View {
        let foes = frame.units.filter { $0.side == 1 && $0.onField }
        let ours = frame.units.filter { $0.side == 0 && $0.onField }
        let last = frame.recentHits.last.flatMap { elapsed - $0.time < Self.hitShown ? $0 : nil }
        let tint = foes.first.flatMap { PokemonTypeData.types(forSpeciesID: $0.speciesID, form: $0.form).first }?.color ?? .gray
        let ourTint = ours.first.flatMap { PokemonTypeData.types(forSpeciesID: $0.speciesID, form: $0.form).first }?.color ?? .gray
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [tint.opacity(0.28), ourTint.opacity(0.22)], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(foes, id: \.id) { plate($0) }
                        bench(side: 1)
                    }
                    Spacer(minLength: 0)
                    fighters(foes, size: foes.count > 1 ? 52 : 70, hit: last, mirrored: false)
                }
                if let last { banner(last) } else { Color.clear.frame(height: 22) }
                HStack(alignment: .bottom, spacing: 6) {
                    fighters(ours, size: ours.count > 1 ? 56 : 78, hit: last, mirrored: true)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        bench(side: 0)
                        ForEach(ours, id: \.id) { plate($0) }
                    }
                }
            }
            .padding(10)
        }
        .frame(height: 236)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// The Pokémon on the field on their ground, the one just hit shaking, its damage rising off it.
    private func fighters(_ units: [BattleFrame.Unit], size: CGFloat, hit: BattleFrame.Hit?, mirrored: Bool) -> some View {
        HStack(alignment: .bottom, spacing: -size * 0.25) {
            ForEach(units, id: \.id) { unit in
                let struck = hit?.target == unit.id
                let striking = hit?.attacker == unit.id && !struck
                let age = Double(elapsed - (hit?.time ?? 0))
                // Forward is toward the other side: up and right for the player's, down and left for the foes'.
                let forward: CGFloat = mirrored ? 1 : -1
                let recoil = struck ? Self.bump(age, length: Self.recoilLength) : 0
                let hop = striking ? Self.bump(age, length: Self.hopLength) : 0
                ZStack(alignment: .top) {
                    Ellipse().fill(Color.black.opacity(0.18)).frame(width: size * 0.95, height: size * 0.22)
                        .offset(y: size * 0.82)
                    Group {
                        // The player's side seen from behind, as in the games (the owner, 2026-11-09); the foes face us.
                        if mirrored {
                            BackSpriteView(speciesID: unit.speciesID, size: size, shiny: unit.isShiny, form: unit.form)
                        } else {
                            SpriteView(speciesID: unit.speciesID, size: size, shiny: unit.isShiny, form: unit.form,
                                       sameScale: true, bottomAligned: true)
                        }
                    }
                        // The one hit flushes red and is knocked back a little; the one hitting leaps at it (the owner,
                        // 2026-11-10: "juste pour donner de la vie au combat"), both quick.
                        .colorMultiply(recoil > 0 ? Color(.sRGB, red: 1, green: 1 - 0.65 * recoil, blue: 1 - 0.65 * recoil) : .white)
                        .offset(x: forward * (CGFloat(hop) * 12 - CGFloat(recoil) * 8),
                                y: -forward * (CGFloat(hop) * 5 - CGFloat(recoil) * 4) - CGFloat(hop) * 7)
                    if struck, let hit {
                        Text("-\(hit.damage)")
                            .font(.system(size: 15, weight: .heavy, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .offset(y: -CGFloat(min(age, Double(Self.hitShown))) / 40)
                            .opacity(1 - min(1, age / Double(Self.hitShown)))
                    }
                }
                .frame(width: size, height: size * 1.05)
            }
        }
    }

    /// A Pokémon's plate: name and gender, its HP drawn and written, its cast, its status.
    private func plate(_ unit: BattleFrame.Unit) -> some View {
        let l = store.l
        let share = Double(unit.hp) / Double(max(1, unit.maxHP))
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                PokemonNameLabel(.pokemonSpecies, String(unit.speciesID), language: store.language)
                    .font(.caption2.weight(.bold)).lineLimit(1)
                GenderGlyph(gender: unit.gender, l: l)
                if let status = unit.status {
                    Text(l.ailmentName(status).uppercased()).font(.system(size: 9, weight: .heavy))
                        .padding(.horizontal, 3).background(Capsule().fill(Color.secondary.opacity(0.3)))
                }
            }
            HStack(spacing: 4) {
                Text(l.battleHP).font(.system(size: 9, weight: .heavy)).foregroundStyle(.secondary)
                ExpeditionBar(value: share, color: .blue, height: 5)
            }
            HStack(spacing: 4) {
                Text("\(unit.hp)/\(unit.maxHP)").font(.system(size: 9, weight: .semibold)).monospacedDigit()
                Spacer(minLength: 2)
                if let move = unit.castMove {
                    PokemonNameLabel(.move, move, language: store.language).font(.system(size: 9)).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            ExpeditionBar(value: unit.castProgress(at: elapsed), color: .purple, height: 2)
        }
        .padding(6)
        .frame(width: 150, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.82)))
    }

    /// The side's Pokémon as balls: one in play or waiting, one down crossed out.
    private func bench(side: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(frame.units.filter { $0.side == side }, id: \.id) { unit in
                Image(systemName: unit.fainted ? "xmark.circle" : "circle.inset.filled")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(unit.fainted ? Color.secondary : Color.primary.opacity(unit.onField ? 1 : 0.6))
            }
        }
    }

    /// The last move that landed: its type, its name, and how effective it was, said in words.
    private func banner(_ hit: BattleFrame.Hit) -> some View {
        let l = store.l
        let attacker = setup.sides.flatMap(\.battlers).first { $0.id == hit.attacker }
        let type = MoveTable.move(hit.move).map { move in attacker.map { move.type(for: $0) } ?? move.type }
        return HStack(spacing: 5) {
            if let type { TypeMiniBadge(type: type, l: l) }
            PokemonNameLabel(.move, hit.move, language: store.language).font(.caption.weight(.bold))
            if let note = BattleLogRow.note(hit.effectiveness, critical: hit.critical, l) {
                Text(note).font(.caption2.weight(.semibold))
                    .foregroundStyle(hit.effectiveness >= 2 || hit.critical ? Color.blue : Color.readableOrange)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(.background.opacity(0.85)))
        .frame(height: 22)
    }
}

/// One line of the battle's journal: a move on its side's half (the player's on the left with a blue edge, the foe's
/// on the right with an orange one), who used it on whom as their sprites, its type, name, damage and effect; what
/// happened to a Pokémon (it comes in, falls, is burned, heals, eats a berry) in the middle.
@MainActor
struct BattleLogRow: View {
    let store: CompanionStore
    let line: BattleLogLine
    let setup: BattleSetup

    var body: some View {
        let l = store.l
        switch line.kind {
        case .move(let attacker, let target, let move, let result):
            let ours = line.side == 0
            HStack(spacing: 4) {
                if ours { edge(Design.actionColor); time } else { Spacer(minLength: 0) }
                Group {
                    if ours {
                        sprite(attacker)
                        Image(systemName: "arrowtriangle.right.fill").font(.system(size: 6)).foregroundStyle(.secondary)
                        if let target, target != attacker { sprite(target) }
                        moveLabel(move, attacker: attacker, l)
                        outcomeText(result, l)
                    } else {
                        outcomeText(result, l)
                        moveLabel(move, attacker: attacker, l)
                        if let target, target != attacker { sprite(target) }
                        Image(systemName: "arrowtriangle.left.fill").font(.system(size: 6)).foregroundStyle(.secondary)
                        sprite(attacker)
                    }
                }
                if ours { Spacer(minLength: 0) } else { time; edge(Color.readableOrange) }
            }
            .frame(minHeight: 20)
        default:
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                time
                event(l)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 18)
        }
    }

    private var time: some View {
        Text(BattleReplayView.clock(line.time)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary)
    }

    private func edge(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 16)
    }

    private func battler(_ id: String) -> BattlerSpec? { setup.sides.flatMap(\.battlers).first { $0.id == id } }

    @ViewBuilder
    private func sprite(_ id: String) -> some View {
        if let spec = battler(id) {
            SpriteView(speciesID: spec.speciesID, size: 18, shiny: spec.isShiny, form: spec.form, sameScale: true)
                .frame(width: 20, height: 20)
        }
    }

    private func moveLabel(_ move: String, attacker: String, _ l: L) -> some View {
        let type = MoveTable.move(move).map { m in battler(attacker).map { m.type(for: $0) } ?? m.type }
        return HStack(spacing: 3) {
            if let type { TypeMiniBadge(type: type, l: l) }
            PokemonNameLabel(.move, move, language: store.language).font(.caption2).lineLimit(1)
        }
    }

    @ViewBuilder
    private func outcomeText(_ result: BattleLogLine.Result, _ l: L) -> some View {
        switch result {
        case .hit(let damage, let effectiveness, let critical):
            Text("−\(damage)").font(.caption2.weight(.heavy)).monospacedDigit()
            if let note = Self.note(effectiveness, critical: critical, l) {
                Text(note).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
        case .miss: Text(l.battleLogMiss).font(.system(size: 9)).foregroundStyle(.secondary)
        case .noEffect: Text(l.battleLogNoEffect).font(.system(size: 9)).foregroundStyle(.secondary)
        case .failed: Text(l.battleLogFailed).font(.system(size: 9)).foregroundStyle(.secondary)
        case .used: EmptyView()
        }
    }

    /// Who, then what happened to it.
    @ViewBuilder
    private func event(_ l: L) -> some View {
        switch line.kind {
        case .enter(let id): who(id, glyph: "arrow.down.right", text: l.battleLogEnters, l)
        case .faint(let id): who(id, glyph: "xmark", text: l.battleKO, l)
        case .status(let id, let ailment): who(id, glyph: "exclamationmark.circle", text: l.ailmentName(ailment), l)
        case .heal(let id, let amount): who(id, glyph: "plus", text: "+\(amount) \(l.battleHP)", l)
        case .hurt(let id, let amount): who(id, glyph: "minus", text: "−\(amount) \(l.battleHP)", l)
        case .berry(let id, let berry):
            who(id, glyph: "leaf", text: l.itemName(berry == .oran ? .oranBerry : .sitrusBerry), l)
        case .move: EmptyView()
        }
    }

    private func who(_ id: String, glyph: String, text: String, _ l: L) -> some View {
        HStack(spacing: 3) {
            Image(systemName: glyph).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            sprite(id)
            if let spec = battler(id) {
                PokemonNameLabel(.pokemonSpecies, String(spec.speciesID), language: store.language)
                    .font(.caption2.weight(.semibold)).lineLimit(1)
            }
            Text(text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    /// "Critical hit!", "Super effective!", "Not very effective": nothing for a plain hit.
    static func note(_ effectiveness: Double, critical: Bool, _ l: L) -> String? {
        if critical { return l.battleCritical }
        if effectiveness >= 2 { return l.battleSuperEffective }
        if effectiveness > 0, effectiveness < 1 { return l.battleNotVeryEffective }
        return nil
    }
}

/// A Pokémon's gender beside its name: ♂ in blue, ♀ in orange, the glyph saying it without the color; nothing for a
/// genderless one.
@MainActor
struct GenderGlyph: View {
    let gender: PokemonGender?
    let l: L

    var body: some View {
        switch gender {
        case .male?:
            Text("♂").font(.caption2.weight(.bold)).foregroundStyle(.blue).accessibilityLabel(l.genderLabel(gender))
        case .female?:
            Text("♀").font(.caption2.weight(.bold)).foregroundStyle(Color.readableOrange)
                .accessibilityLabel(l.genderLabel(gender))
        default:
            EmptyView()
        }
    }
}

/// A Pokémon from behind, for the player's side of the arena: Showdown's back render, drawn as the arena draws the
/// fronts (one scale, standing on the bottom of its box). Until its back is there, and for the eight forms without one
/// (the owner, 2026-11-09: "tu les laisses de face"), its front turned toward the foe.
@MainActor
struct BackSpriteView: View {
    let speciesID: Int
    let size: CGFloat
    let shiny: Bool
    let form: PokemonForm?
    @State private var back: NSImage?

    init(speciesID: Int, size: CGFloat, shiny: Bool, form: PokemonForm?) {
        self.speciesID = speciesID
        self.size = size
        self.shiny = shiny
        self.form = form
        _back = State(initialValue: SpriteLoader.cachedBackImage(speciesID: speciesID, shiny: shiny,
                                                                 form: Self.resolved(speciesID, form)))
    }

    private static func resolved(_ speciesID: Int, _ form: PokemonForm?) -> PokemonForm? {
        PokemonForm.resolved(speciesID: speciesID, form: PikachuCostume.displayForm(speciesID: speciesID, form: form))
    }

    var body: some View {
        Group {
            if let back {
                let fit = SpriteView.imageSize(for: back, box: size, sameScale: true)
                Image(nsImage: back)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: fit.width, height: fit.height)
                    .offset(y: fit.height * SpriteFit.bottomMargin(of: back))
                    .frame(width: size, height: size, alignment: .bottom)
            } else {
                SpriteView(speciesID: speciesID, size: size, shiny: shiny, form: form, sameScale: true, bottomAligned: true)
                    .scaleEffect(x: -1, y: 1)
            }
        }
        .task(id: "\(speciesID)-\(shiny)-\(form?.rawValue ?? "")") {
            back = await SpriteLoader.backImage(speciesID: speciesID, shiny: shiny, form: Self.resolved(speciesID, form))
        }
    }
}
