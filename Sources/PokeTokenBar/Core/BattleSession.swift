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
    var status: [[BattleStatus?]]
    var isOut: [Bool] = [false, false]

    init(_ state: BattleState) {
        hp = BattleSide.allCases.map { side in state[side].team.map(\.hp) }
        status = BattleSide.allCases.map { side in state[side].team.map(\.status) }
    }

    mutating func apply(_ event: BattleEvent) {
        switch event {
        case .sentOut(let side, let index):
            active[side.rawValue] = index
            isOut[side.rawValue] = true
        case .damaged(let side, _, let value, _, _), .healed(let side, _, let value), .recoil(let side, _, let value),
             .hurtByConfusion(let side, _, let value), .residual(let side, _, _, let value),
             .effectDamage(let side, _, _, let value), .effectHeal(let side, _, _, let value), .futureHit(let side, _, let value):
            hp[side.rawValue][active[side.rawValue]] = value
        case .statusCured(let side):
            status[side.rawValue][active[side.rawValue]] = nil
        case .teamCured(let side):
            status[side.rawValue] = status[side.rawValue].map { _ in nil }
        case .healingWishCameTrue(let side):
            status[side.rawValue][active[side.rawValue]] = nil
        case .statusApplied(let side, let applied):
            status[side.rawValue][active[side.rawValue]] = applied
        case .wokeUp(let side), .thawed(let side):
            status[side.rawValue][active[side.rawValue]] = nil
        case .rested(let side, let value):
            hp[side.rawValue][active[side.rawValue]] = value
            status[side.rawValue][active[side.rawValue]] = .sleep
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
            // Send before applying: after U-turn or Baton Pass the replacement finishes the turn, and the
            // peer checks the message against the turn it is still waiting in.
            try await opponent.sendReplacement(index, in: state)
            await animate(try state.replace(mySide, with: index))
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
        } else if canChoose, let forced = state.forcedMove(for: mySide) {
            // Charging, recharging and rampages pick themselves; the choice still travels to the peer.
            message = prompt
            Task { [weak self] in await self?.choose(.move(forced)) }
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

    private func team(_ side: BattleSide) -> String { side == mySide ? l.battleYourTeam : l.battleOpposingTeam }

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
        case .statusApplied(let side, let status): return [l.battleStatusApplied(subject(side), status)]
        case .confused(let side): return [l.battleBecameConfused(subject(side))]
        case .cantMove(let side, let reason): return [l.battleCantMove(subject(side), reason)]
        case .wokeUp(let side): return [l.battleWokeUp(subject(side))]
        case .thawed(let side): return [l.battleThawed(subject(side))]
        case .isConfused(let side): return [l.battleIsConfused(subject(side))]
        case .snappedOut(let side): return [l.battleSnappedOut(subject(side))]
        case .hurtByConfusion: return [l.battleHurtByConfusion]
        case .residual(let side, let status, _, _): return [l.battleResidual(subject(side), status)]
        case .protecting(let side): return [l.battleProtecting(subject(side))]
        case .bracing(let side): return [l.battleBracing(subject(side))]
        case .blocked(let side): return [l.battleBlocked(subject(side))]
        case .endured(let side): return [l.battleEndured(subject(side))]
        case .rested(let side, _): return [l.battleRested(subject(side))]
        case .fainted(let side, _): return [l.battleFainted(subject(side))]
        case .withdrew(let side): return [l.battleWithdrew(name(side, display.active[side.rawValue]), mine: side == mySide)]
        case .hitCount(let count): return [l.battleHitCount(count)]
        case .oneHitKO: return [l.battleOneHitKO]
        case .effectDamage(let side, let kind, _, _): return l.battleEffectDamage(subject(side), kind).map { [$0] } ?? []
        case .effectHeal(let side, let kind, _, _): return l.battleEffectHeal(subject(side), kind).map { [$0] } ?? []
        case .stagesReset(let side): return [l.battleStagesReset(side.map(subject))]
        case .nothingHappened: return [l.battleNothingHappened]
        case .statusCured(let side): return [l.battleStatusCured(subject(side))]
        case .teamCured(let side): return [l.battleTeamCured(team(side))]
        case .charging(let side, let kind): return [l.battleCharging(subject(side), kind)]
        case .storingEnergy(let side): return [l.battleStoringEnergy(subject(side))]
        case .unleashedEnergy(let side): return [l.battleUnleashedEnergy(subject(side))]
        case .fellForFeint(let side): return [l.battleFellForFeint(subject(side))]
        case .foresaw(let side): return [l.battleForesaw(subject(side))]
        case .futureHit(let side, _, _): return [l.battleFutureHit(subject(side))]
        case .draggedOut(let side): return [l.battleDraggedOut(subject(side))]
        case .hazardsCleared(let side): return [l.battleHazardsCleared(team(side))]
        case .fellDown(let side): return [l.battleFellDown(subject(side))]
        case .pumped(let side): return [l.battlePumped(subject(side))]
        case .screenStarted(let side, let barrier): return [l.battleBarrierStarted(team(side), barrier)]
        case .screenEnded(let side, let barrier): return [l.battleBarrierEnded(team(side), moveName(barrier.moveName))]
        case .weatherStarted(let weather): return [l.battleWeather(weather, started: true)]
        case .weatherEnded(let weather): return [l.battleWeather(weather, started: false)]
        case .sportStarted(let type): return [l.battleSport(type)]
        case .trickRoom(let started): return [l.battleTrickRoom(started: started)]
        case .gravity(let started): return [l.battleGravity(started: started)]
        case .uproar(let side, let started): return [l.battleUproar(subject(side), started: started)]
        case .taunted(let side): return [l.battleTaunted(subject(side), ended: false)]
        case .tauntEnded(let side): return [l.battleTaunted(subject(side), ended: true)]
        case .encored(let side): return [l.battleEncored(subject(side), ended: false)]
        case .encoreEnded(let side): return [l.battleEncored(subject(side), ended: true)]
        case .disabled(let side, let move): return [l.battleDisabled(subject(side), moveName(move))]
        case .disableEnded(let side): return [l.battleDisableEnded(subject(side))]
        case .tormented(let side): return [l.battleTormented(subject(side))]
        case .imprisoning(let side): return [l.battleImprisoning(subject(side))]
        case .healBlocked(let side): return [l.battleHealBlocked(subject(side), ended: false)]
        case .healBlockEnded(let side): return [l.battleHealBlocked(subject(side), ended: true)]
        case .seeded(let side): return [l.battleSeeded(subject(side))]
        case .drowsy(let side): return [l.battleDrowsy(subject(side))]
        case .identified(let side): return [l.battleIdentified(subject(side))]
        case .trapped(let side): return [l.battleTrapped(subject(side))]
        case .stockpiled(let side, let count): return [l.battleStockpiled(subject(side), count)]
        case .copiedStages(let side): return [l.battleCopiedStages(subject(side))]
        case .tookAim(let side): return [l.battleTookAim(subject(side))]
        case .destinyBond(let side): return [l.battleDestinyBond(subject(side))]
        case .tookDownWithIt(let side): return [l.battleTookDownWithIt(subject(side))]
        case .healingWishCameTrue(let side): return [l.battleHealingWish(subject(side))]
        case .infatuated(let side): return [l.battleInfatuated(subject(side))]
        case .levitating(let side): return [l.battleLevitating(subject(side))]
        case .perishSong: return [l.battlePerishSong]
        case .perishCount(let side, let count): return [l.battlePerishCount(subject(side), count)]
        case .guarding(let side): return [l.battleGuarding(subject(side))]
        case .hazardSet(let side, let hazard): return [l.battleHazardSet(team(side), hazard)]
        case .transformed(let side, let into): return [l.battleTransformed(subject(side), into: subject(into))]
        case .typeChanged(let side, let type): return [l.battleTypeChanged(subject(side), typeName(type))]
        case .learnedMove(let side, let move): return [l.battleLearnedMove(subject(side), moveName(move))]
        case .sharedPain: return [l.battleSharedPain]
        case .maximizedAttack(let side): return [l.battleMaximizedAttack(subject(side))]
        case .madeWish(let side): return [l.battleMadeWish(subject(side))]
        case .nightmareStarted(let side): return [l.battleNightmare(subject(side))]
        case .spite(let side, let move, let amount): return [l.battleSpite(subject(side), moveName(move), amount)]
        case .grudge(let side): return [l.battleGrudge(subject(side))]
        case .grudgeTriggered(let side, let move): return [l.battleGrudgeTriggered(subject(side), moveName(move))]
        case .swappedStages(let side): return [l.battleSwappedStages(subject(side))]
        case .sharedStats(let side): return [l.battleSharedStats(subject(side))]
        case .lighter(let side): return [l.battleLighter(subject(side))]
        case .hurledIntoAir(let side): return [l.battleHurledIntoAir(subject(side))]
        case .magicCoat(let side): return [l.battleMagicCoat(subject(side))]
        case .bounced(let side, let move): return [l.battleBounced(subject(side), moveName(move))]
        case .chargingPower(let side): return [l.battleChargingPower(subject(side))]
        case .magnitude(let level): return [l.battleMagnitude(level)]
        case .aquaRing(let side): return [l.battleAquaRing(subject(side))]
        case .rooted(let side): return [l.battleRooted(subject(side))]
        case .forfeited(let side): return [side == mySide ? l.battleYouForfeited : l.battleOpponentForfeited]
        case .ended: return []
        }
    }
}
