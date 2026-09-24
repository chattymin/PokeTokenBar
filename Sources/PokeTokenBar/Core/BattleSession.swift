import Foundation

/// The other side of a battle. The CPU answers instantly; a nearby player answers over a `BattleLink`.
@MainActor
protocol BattleOpponent: AnyObject {
    var supportsRematch: Bool { get }
    /// Hands over our choice for this turn and returns theirs.
    func exchange(_ mine: BattleAction, in state: BattleState, side: BattleSide) async throws -> BattleAction
    func sendReplacement(_ index: Int, in state: BattleState) async throws
    func replacement(in state: BattleState, side: BattleSide) async throws -> Int
    func notifyForfeit()
    func close()
}

@MainActor
final class CPUOpponent: BattleOpponent {
    private var rng: BattleRNG
    init(seed: UInt64) { rng = BattleRNG(seed: seed) }

    var supportsRematch: Bool { true }
    func exchange(_ mine: BattleAction, in state: BattleState, side: BattleSide) async throws -> BattleAction {
        BattleCPU.action(for: side, in: state, rng: &rng)
    }
    func sendReplacement(_ index: Int, in state: BattleState) async throws {}
    func replacement(in state: BattleState, side: BattleSide) async throws -> Int {
        guard let index = BattleCPU.replacement(for: side, in: state) else { throw BattleEngineError.wrongPhase }
        return index
    }
    func notifyForfeit() {}
    func close() {}
}

extension NetworkOpponent {
    var supportsRematch: Bool { false }
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

/// Runs one battle for the local player: exchanges choices with the opponent, resolves turns and plays
/// the resulting events back line by line.
@MainActor @Observable
final class BattleSession {
    enum Outcome: Equatable, Sendable { case won, lost, draw, aborted }

    let mySide: BattleSide
    var theirSide: BattleSide { mySide.opponent }
    let opponentName: String?
    private(set) var state: BattleState
    private(set) var display: BattleDisplay
    private(set) var message = ""
    private(set) var log: [String] = []
    private(set) var isAnimating = false
    private(set) var isWaitingForOpponent = false
    private(set) var outcome: Outcome?
    /// When the local player's choice is made for them. nil when there is no limit (practice).
    private(set) var turnDeadline: Date?
    var onFinish: ((Outcome) -> Void)?

    private let myTeam: BattleTeam
    private let opponentTeam: BattleTeam
    private let opponent: any BattleOpponent
    private let language: AppLanguage
    private let names: @MainActor (PokemonNameResource) -> [String: String]?
    private let pace: Duration
    private let turnTimeLimit: Duration?
    private let clock: () -> Date
    private var seed: UInt64
    private var abandoned = false
    private var forfeitRequested = false
    private var pendingInterrupt: BattleLinkError?
    private var timer: Task<Void, Never>?

    init(myTeam: BattleTeam, opponentTeam: BattleTeam, seed: UInt64, opponent: any BattleOpponent,
         language: AppLanguage, mySide: BattleSide = .a, opponentName: String? = nil,
         turnTimeLimit: Duration? = nil, pace: Duration = .milliseconds(1100), clock: @escaping () -> Date = Date.init,
         names: @escaping @MainActor (PokemonNameResource) -> [String: String]? = { _ in nil }) {
        self.myTeam = myTeam
        self.opponentTeam = opponentTeam
        self.seed = seed
        self.opponent = opponent
        self.language = language
        self.mySide = mySide
        self.opponentName = opponentName
        self.turnTimeLimit = turnTimeLimit
        self.pace = pace
        self.clock = clock
        self.names = names
        let initial = Self.makeState(myTeam, opponentTeam, mySide: mySide, seed: seed)
        state = initial
        display = BattleDisplay(initial)
    }

    /// Side `.a` always holds the challenger's team, so both machines build the identical state.
    private static func makeState(_ mine: BattleTeam, _ theirs: BattleTeam, mySide: BattleSide, seed: UInt64) -> BattleState {
        mySide == .a ? BattleState(teamA: mine, teamB: theirs, seed: seed) : BattleState(teamA: theirs, teamB: mine, seed: seed)
    }

    var l: L { L(language) }
    var isPlaying: Bool { isAnimating || isWaitingForOpponent }
    var canRematch: Bool { opponent.supportsRematch }
    var awaitingReplacement: Bool { !isPlaying && !abandoned && outcome == nil && state.needsReplacement.contains(mySide) }
    var canChoose: Bool { !isPlaying && !abandoned && state.phase == .choosing && outcome == nil }
    var canForfeit: Bool { outcome == nil && !abandoned && !isAnimating && !forfeitRequested }
    var usableMoves: Set<Int> { Set(state.usableMoves(for: mySide)) }
    var switchTargets: [Int] { state.switchTargets(for: mySide) }
    var prompt: String { l.battleWhatWillDo(name(mySide, state[mySide].active)) }

    func start() async {
        await animate(state.openingEvents)
        finishOrPrompt()
    }

    func choose(_ action: BattleAction) async {
        guard canChoose, state.legalActions(for: mySide).contains(action) else { return }
        await perform {
            let theirs = try await waitForOpponent { try await opponent.exchange(action, in: state, side: theirSide) }
            let events = mySide == .a ? try state.resolveTurn(action, theirs) : try state.resolveTurn(theirs, action)
            await animate(events)
            try await replaceOpponentIfNeeded()
        }
    }

    func replace(with index: Int) async {
        guard awaitingReplacement else { return }
        await perform {
            await animate(try state.replace(mySide, with: index))
            try await opponent.sendReplacement(index, in: state)
            try await replaceOpponentIfNeeded()
        }
    }

    /// Allowed while waiting on the opponent too — a slow peer must not trap the player in the battle.
    func forfeit() async {
        guard canForfeit else { return }
        opponent.notifyForfeit()
        if isWaitingForOpponent {
            forfeitRequested = true
            opponent.close()   // the pending wait throws; `handle` then records our forfeit
            return
        }
        await perform { await animate(state.forfeit(mySide)) }
        opponent.close()
    }

    func rematch() async {
        guard canRematch, !isPlaying else { return }
        var reseed = BattleRNG(seed: seed)
        seed = reseed.next()
        state = Self.makeState(myTeam, opponentTeam, mySide: mySide, seed: seed)
        display = BattleDisplay(state)
        log = []
        outcome = nil
        await start()
    }

    /// The window closed. Mid-battle that counts as leaving, so the peer is told.
    func abandon() {
        guard !abandoned else { return }
        abandoned = true
        timer?.cancel()
        turnDeadline = nil
        if outcome == nil { opponent.notifyForfeit() }
        opponent.close()
    }

    /// The peer forfeited or vanished. Synchronous so it cannot arrive "late".
    ///
    /// While a turn runs it is only recorded: a wait that already received the peer's move will not
    /// throw, so relying on it would drop a forfeit sent right after that move. `perform` applies the
    /// record afterwards, and `handle` ignores it if the wait did throw and the battle already ended.
    func opponentInterrupted(_ error: BattleLinkError) {
        guard outcome == nil, !abandoned else { return }
        if isPlaying {
            pendingInterrupt = pendingInterrupt ?? error
            return
        }
        Task { await perform { throw error } }
    }

    // MARK: Flow

    private func perform(_ body: () async throws -> Void) async {
        timer?.cancel()
        turnDeadline = nil
        do {
            try await body()
        } catch {
            await handle(error)
        }
        if let pending = pendingInterrupt, outcome == nil {
            pendingInterrupt = nil
            await handle(pending)
        }
        finishOrPrompt()
    }

    private func waitForOpponent<T>(_ body: () async throws -> T) async throws -> T {
        isWaitingForOpponent = true
        defer { isWaitingForOpponent = false }
        return try await body()
    }

    private func handle(_ error: Error) async {
        if case .finished = state.phase { return }
        if forfeitRequested {
            await animate(state.forfeit(mySide))
            return
        }
        AppLog.write("battle interrupted: \(error)")
        switch error as? BattleLinkError {
        case .peerForfeited:
            await animate(state.forfeit(theirSide))
        case .disconnected, .timedOut:
            _ = state.forfeit(theirSide)
            await say(l.battleOpponentLeft)
        default:
            // Desync, a malformed message, or an illegal move from the peer: nobody can be declared winner.
            outcome = .aborted
            opponent.close()
            await say(l.battleConnectionProblem)
        }
    }

    private func replaceOpponentIfNeeded() async throws {
        // The player picks first, like in the main series; the opponent follows.
        guard state.needsReplacement.contains(theirSide), !state.needsReplacement.contains(mySide) else { return }
        let index = try await waitForOpponent { try await opponent.replacement(in: state, side: theirSide) }
        await animate(try state.replace(theirSide, with: index))
    }

    private func finishOrPrompt() {
        if outcome == .aborted {
            message = l.battleConnectionProblem
        } else if case .finished(let winner) = state.phase {
            let result: Outcome = winner == nil ? .draw : winner == mySide ? .won : .lost
            if outcome == nil { onFinish?(result) }
            outcome = result
            message = result == .won ? l.battleWon : result == .lost ? l.battleLost : l.battleDraw
        } else if awaitingReplacement {
            message = l.battleChooseNext
            armTimer { [weak self] in
                guard let self, let pick = self.switchTargets.randomElement() else { return }
                await self.replace(with: pick)
            }
        } else if canChoose {
            message = prompt
            armTimer { [weak self] in
                guard let self else { return }
                let legal = self.state.legalActions(for: self.mySide).filter { $0 != .forfeit }
                if let pick = legal.randomElement() { await self.choose(pick) }
            }
        }
        if outcome != nil {
            timer?.cancel()
            turnDeadline = nil
        }
    }

    /// When time runs out the choice is made at random, like an idle player in link battles.
    private func armTimer(_ fire: @escaping @MainActor () async -> Void) {
        timer?.cancel()
        guard let turnTimeLimit, !abandoned else { return }
        let seconds = Double(turnTimeLimit.components.seconds) + Double(turnTimeLimit.components.attoseconds) / 1e18
        turnDeadline = clock().addingTimeInterval(seconds)
        timer = Task { @MainActor in
            try? await Task.sleep(for: turnTimeLimit)
            guard !Task.isCancelled else { return }
            await fire()
        }
    }

    // MARK: Playback

    private func animate(_ events: [BattleEvent]) async {
        isAnimating = true
        defer { isAnimating = false }
        for event in events {
            if abandoned { return }
            display.apply(event)
            let lines = self.lines(for: event)
            if lines.isEmpty, case .damaged = event { try? await Task.sleep(for: pace / 2) }
            for line in lines { await say(line) }
        }
    }

    private func say(_ line: String) async {
        message = line
        log.append(line)
        try? await Task.sleep(for: pace)
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
