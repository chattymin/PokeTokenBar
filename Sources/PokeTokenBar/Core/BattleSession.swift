import Foundation

/// The other side of a battle. The CPU answers instantly; a nearby player will answer over the network.
@MainActor
protocol BattleOpponent: AnyObject {
    func action(in state: BattleState, side: BattleSide) async throws -> BattleAction
    func replacement(in state: BattleState, side: BattleSide) async throws -> Int
}

@MainActor
final class CPUOpponent: BattleOpponent {
    private var rng: BattleRNG
    init(seed: UInt64) { rng = BattleRNG(seed: seed) }

    func action(in state: BattleState, side: BattleSide) async throws -> BattleAction {
        BattleCPU.action(for: side, in: state, rng: &rng)
    }
    func replacement(in state: BattleState, side: BattleSide) async throws -> Int {
        guard let index = BattleCPU.replacement(for: side, in: state) else { throw BattleEngineError.wrongPhase }
        return index
    }
}

/// What the screen shows while events play back — it trails the engine state until playback catches up.
struct BattleDisplay: Equatable, Sendable {
    var active: [Int] = [0, 0]
    var hp: [[Int]]
    var isOut: [Bool] = [false, false]

    init(_ state: BattleState) {
        hp = BattleSide.allCases.map { side in state[side].team.map(\.hp) }
    }

    mutating func apply(_ event: BattleEvent) {
        switch event {
        case .sentOut(let side, let index):
            active[side.rawValue] = index
            isOut[side.rawValue] = true
        case .damaged(let side, _, let value, _, _), .healed(let side, _, let value), .recoil(let side, _, let value):
            hp[side.rawValue][active[side.rawValue]] = value
        case .fainted(let side, _):
            isOut[side.rawValue] = false
        default:
            break
        }
    }
}

/// Runs one battle for the player on side `.a`: asks the opponent, resolves the turn, and plays
/// the resulting events back line by line.
@MainActor @Observable
final class BattleSession {
    enum Outcome: Equatable, Sendable { case won, lost, draw }

    let mySide = BattleSide.a
    let myTeam: BattleTeam
    let opponentTeam: BattleTeam
    private(set) var state: BattleState
    private(set) var display: BattleDisplay
    private(set) var message = ""
    private(set) var log: [String] = []
    private(set) var isPlaying = false
    private(set) var outcome: Outcome?

    private let opponent: any BattleOpponent
    private let language: AppLanguage
    private let names: @MainActor (PokemonNameResource) -> [String: String]?
    private let pace: Duration
    private var seed: UInt64
    private var abandoned = false

    init(myTeam: BattleTeam, opponentTeam: BattleTeam, seed: UInt64, opponent: any BattleOpponent,
         language: AppLanguage, pace: Duration = .milliseconds(1100),
         names: @escaping @MainActor (PokemonNameResource) -> [String: String]? = { _ in nil }) {
        self.myTeam = myTeam
        self.opponentTeam = opponentTeam
        self.seed = seed
        self.opponent = opponent
        self.language = language
        self.pace = pace
        self.names = names
        let initial = BattleState(teamA: myTeam, teamB: opponentTeam, seed: seed)
        state = initial
        display = BattleDisplay(initial)
    }

    var l: L { L(language) }
    var awaitingReplacement: Bool { !isPlaying && state.needsReplacement.contains(mySide) }
    var canChoose: Bool { !isPlaying && state.phase == .choosing && !abandoned }
    var usableMoves: Set<Int> { Set(state.usableMoves(for: mySide)) }
    var switchTargets: [Int] { state.switchTargets(for: mySide) }
    var prompt: String { l.battleWhatWillDo(name(mySide, state[mySide].active)) }

    func start() async {
        await play(state.openingEvents)
        if canChoose { message = prompt }
    }

    func choose(_ action: BattleAction) async {
        guard canChoose, state.legalActions(for: mySide).contains(action) else { return }
        await perform {
            do {
                let theirs = try await opponent.action(in: state, side: mySide.opponent)
                let events = try state.resolveTurn(action, theirs)
                await play(events)
                try await replaceOpponentIfNeeded()
            } catch {
                AppLog.write("battle turn failed: \(error)")
                await play(state.forfeit(mySide.opponent))
            }
        }
    }

    func replace(with index: Int) async {
        guard awaitingReplacement, !abandoned else { return }
        await perform {
            do {
                await play(try state.replace(mySide, with: index))
                try await replaceOpponentIfNeeded()
            } catch {
                AppLog.write("battle replacement failed: \(error)")
            }
        }
    }

    func forfeit() async {
        guard outcome == nil, !isPlaying else { return }
        await perform { await play(state.forfeit(mySide)) }
    }

    func rematch() async {
        guard !isPlaying else { return }
        var reseed = BattleRNG(seed: seed)
        seed = reseed.next()
        state = BattleState(teamA: myTeam, teamB: opponentTeam, seed: seed)
        display = BattleDisplay(state)
        log = []
        outcome = nil
        await start()
    }

    /// The window closed: stop playback without resolving anything further.
    func abandon() { abandoned = true }

    // MARK: Playback

    private func replaceOpponentIfNeeded() async throws {
        // The player picks first, like in the main series; the opponent follows.
        guard state.needsReplacement.contains(mySide.opponent), !state.needsReplacement.contains(mySide) else { return }
        let index = try await opponent.replacement(in: state, side: mySide.opponent)
        await play(try state.replace(mySide.opponent, with: index))
    }

    /// The prompt depends on `isPlaying`, so it is chosen only after playback has ended.
    private func perform(_ body: () async -> Void) async {
        isPlaying = true
        await body()
        isPlaying = false
        finishOrPrompt()
    }

    private func finishOrPrompt() {
        if case .finished(let winner) = state.phase {
            outcome = winner == nil ? .draw : winner == mySide ? .won : .lost
            message = outcome == .won ? l.battleWon : outcome == .lost ? l.battleLost : l.battleDraw
        } else if awaitingReplacement {
            message = l.battleChooseNext
        } else if canChoose {
            message = prompt
        }
    }

    private func play(_ events: [BattleEvent]) async {
        for event in events {
            if abandoned { return }
            display.apply(event)
            let lines = self.lines(for: event)
            if lines.isEmpty, case .damaged = event { try? await Task.sleep(for: pace / 2) }
            for line in lines {
                message = line
                log.append(line)
                try? await Task.sleep(for: pace)
            }
        }
    }

    // MARK: Text

    func name(_ side: BattleSide, _ index: Int) -> String {
        let pokemon = state[side].team[index].pokemon
        let base = language.resolveName(pokemon.names) ?? "#\(pokemon.speciesID)"
        return UnownForm.displayName(base, speciesID: pokemon.speciesID, form: pokemon.unownForm)
    }

    func moveName(_ raw: String) -> String { localized(.move, raw) }

    func typeName(_ raw: String) -> String {
        raw == BattleTypeChart.typeless ? "—" : localized(.type, raw)
    }

    private func localized(_ kind: PokemonNameResource.Kind, _ raw: String) -> String {
        names(PokemonNameResource(kind: kind, name: raw)).flatMap { language.resolveName($0) }
            ?? PokemonNameLocalization.identifier(raw)
    }

    private func subject(_ side: BattleSide) -> String {
        let own = name(side, display.active[side.rawValue])
        return side == mySide ? own : l.battleOpposing(own)
    }

    /// Lines start with a capital even when they open with a lowercase subject ("the opposing …").
    func lines(for event: BattleEvent) -> [String] {
        rawLines(for: event).map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    private func rawLines(for event: BattleEvent) -> [String] {
        switch event {
        case .sentOut(let side, let index):
            return [side == mySide ? l.battleGo(name(side, index)) : l.battleOpponentSentOut(name(side, index))]
        case .usedMove(let side, let move): return [l.battleUsed(subject(side), moveName(move))]
        case .noMovesLeft(let side): return [l.battleNoMovesLeft(subject(side))]
        case .missed(let side): return [l.battleMissed(subject(side))]
        case .noEffect(let target): return [l.battleNoEffect(subject(target))]
        case .damaged(_, _, _, let effectiveness, let critical):
            var lines: [String] = []
            if critical { lines.append(l.battleCritical) }
            if effectiveness > 4 { lines.append(l.battleSuperEffective) }
            if effectiveness < 4 { lines.append(l.battleNotVeryEffective) }
            return lines
        case .healed(let side, _, _): return [l.battleHealed(subject(side))]
        case .recoil(let side, _, _): return [l.battleRecoil(subject(side))]
        case .statChanged(let side, let stat, let change):
            return [l.battleStatChanged(subject(side), l.battleStatLabel(stat), change)]
        case .statLimit(let side, let stat, let rising):
            return [l.battleStatLimit(subject(side), l.battleStatLabel(stat), rising: rising)]
        case .failed: return [l.battleFailed]
        case .fainted(let side, _): return [l.battleFainted(subject(side))]
        case .forfeited(let side): return [side == mySide ? l.battleYouForfeited : l.battleOpponentForfeited]
        case .ended: return []
        }
    }
}
