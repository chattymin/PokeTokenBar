import XCTest
@testable import PokeTokenBar

private func move(_ name: String, power: Int? = 40, pp: Int = 20) -> BattleMove {
    BattleMove(name: name, type: "normal", power: power, accuracy: nil, pp: pp, priority: 0,
               damageClass: .physical, target: "selected-pokemon", category: "damage")
}

private func mon(_ id: String, hp: Int = 100, speed: Int = 50, level: Int = 50,
                 moves: [BattleMove] = [move("tackle"), move("slam", power: 80)]) -> BattlePokemon {
    BattlePokemon(instanceID: id, speciesID: 25, names: ["en": id.capitalized], level: level, isShiny: false,
                  unownForm: nil, gender: nil, nature: nil, abilityName: nil, types: ["normal"],
                  stats: BattleStats(hp: hp, attack: 60, defense: 50, specialAttack: 60, specialDefense: 50, speed: speed),
                  moves: moves)
}

private func team(_ tag: String, count: Int = 3) throws -> BattleTeam {
    try BattleTeam(members: (0..<count).map { mon("\(tag)\($0)", hp: 90 + $0 * 7, speed: 40 + $0 * 9) })
}

final class BattleWireTests: XCTestCase {
    func testMessagesRoundTrip() throws {
        let messages: [BattleWireMessage] = [
            .hello(protocolVersion: 1, trainer: "Ash"), .team(try team("a")), .nonce(42),
            .action(turn: 3, action: .switchTo(2), digest: "abc"), .replacement(turn: 4, index: 1), .forfeit,
        ]
        for message in messages {
            XCTAssertEqual(try BattleWireMessage.decode(try message.encoded()), message)
        }
    }

    func testOversizedAndMalformedMessagesAreRejected() {
        XCTAssertThrowsError(try BattleWireMessage.decode(Data(count: BattleWireMessage.maxSize + 1)))
        XCTAssertThrowsError(try BattleWireMessage.decode(Data("{\"nope\":{}}".utf8)))
    }

    /// A peer's team skips the local init, so decoding must enforce the same rules and value ranges.
    func testPeerTeamsAreValidatedOnDecode() throws {
        func decodes(_ members: [BattlePokemon]) -> Bool {
            struct Raw: Encodable { let members: [BattlePokemon] }
            let data = try! JSONEncoder().encode(Raw(members: members))
            return (try? JSONDecoder().decode(BattleTeam.self, from: data)) != nil
        }
        XCTAssertTrue(decodes([mon("a")]))
        XCTAssertFalse(decodes([]))
        XCTAssertFalse(decodes((0..<7).map { mon("m\($0)") }))
        XCTAssertFalse(decodes([mon("dup"), mon("dup")]))
        XCTAssertFalse(decodes([mon("a", hp: 0)]), "a zero-HP member would start fainted")
        XCTAssertFalse(decodes([mon("a", level: 150)]))
        XCTAssertFalse(decodes([mon("a", moves: [move("x", power: 999)])]))
        XCTAssertFalse(decodes([mon("a", moves: [move("x", pp: 0)])]))
        XCTAssertFalse(decodes([mon("a", moves: (0..<5).map { move("m\($0)") })]))
        XCTAssertTrue(decodes([mon("a", moves: [])]), "no moves is legal: the engine falls back to Struggle")
    }

    func testDigestChangesWithAnyStateChange() throws {
        var state = BattleState(teamA: try team("a"), teamB: try team("b"), seed: 1)
        let before = state.digest
        XCTAssertEqual(before, BattleState(teamA: try team("a"), teamB: try team("b"), seed: 1).digest)
        XCTAssertNotEqual(before, BattleState(teamA: try team("a"), teamB: try team("b"), seed: 2).digest,
                          "the RNG is part of the digest")
        _ = try state.resolveTurn(.move(0), .move(0))
        XCTAssertNotEqual(state.digest, before)
    }

    func testTrainerNamesAreSanitizedAndDefaultsAreAnonymous() {
        XCTAssertEqual(BattleTrainer.sanitized("  Ash\nKetchum\u{0007}  "), "AshKetchum")
        XCTAssertEqual(BattleTrainer.sanitized(String(repeating: "x", count: 99)).count, BattleTrainer.maxNameLength)
        XCTAssertEqual(BattleTrainer.defaultName(random: 0), "Trainer 1000")
        XCTAssertEqual(BattleTrainer.defaultName(random: 8999), "Trainer 9999")
    }
}

@MainActor
final class BattleMailboxTests: XCTestCase {
    func testBuffersInOrderWaitsTimesOutAndCloses() async throws {
        let mailbox = BattleMailbox()
        mailbox.deliver(.nonce(1))
        mailbox.deliver(.nonce(2))
        let first = try await mailbox.next(timeout: .seconds(1))
        let second = try await mailbox.next(timeout: .seconds(1))
        XCTAssertEqual([first, second], [.nonce(1), .nonce(2)])

        Task { @MainActor in mailbox.deliver(.nonce(3)) }
        let waited = try await mailbox.next(timeout: .seconds(1))
        XCTAssertEqual(waited, .nonce(3))

        do {
            _ = try await mailbox.next(timeout: .milliseconds(20))
            XCTFail("expected a timeout")
        } catch { XCTAssertEqual(error as? BattleLinkError, .timedOut) }

        let late = try await {
            Task { @MainActor in mailbox.deliver(.nonce(4)) }
            return try await mailbox.next(timeout: .seconds(1))
        }()
        XCTAssertEqual(late, .nonce(4), "an expired wait's timer must not cancel the next wait")

        Task { @MainActor in mailbox.close(.disconnected) }
        do {
            _ = try await mailbox.next(timeout: .seconds(1))
            XCTFail("expected close")
        } catch { XCTAssertEqual(error as? BattleLinkError, .disconnected) }
        mailbox.deliver(.nonce(5))
        do {
            _ = try await mailbox.next(timeout: .seconds(1))
            XCTFail("a closed mailbox stays closed")
        } catch { XCTAssertEqual(error as? BattleLinkError, .disconnected) }
    }
}

@MainActor
final class NetworkBattleTests: XCTestCase {
    private struct Pair {
        let challenger: BattleSession
        let guest: BattleSession
        let challengerLink: BattleLink
        let guestLink: BattleLink
    }

    private func connectedPair(teamA: BattleTeam, teamB: BattleTeam, turnTimeLimit: Duration? = nil,
                               patience: Duration = .seconds(5)) async throws -> Pair {
        let (left, right) = LoopbackTransport.pair()
        let challengerLink = BattleLink(transport: left), guestLink = BattleLink(transport: right)
        async let a = BattleHandshake.run(challengerLink, isChallenger: true, trainer: "Red", team: teamA, nonce: 11)
        async let b = BattleHandshake.run(guestLink, isChallenger: false, trainer: "Blue", team: teamB, nonce: 22)
        let (matchA, matchB) = try await (a, b)
        XCTAssertEqual(matchA.seed, matchB.seed)
        XCTAssertEqual(matchA.mySide, .a)
        XCTAssertEqual(matchB.mySide, .b)
        XCTAssertEqual(matchA.opponentName, "Blue")
        XCTAssertEqual(matchB.opponentTeam, teamA)

        func session(_ match: BattleMatch, _ link: BattleLink) -> BattleSession {
            let s = BattleSession(myTeam: match.myTeam, opponentTeam: match.opponentTeam, seed: match.seed,
                                  opponent: NetworkOpponent(link: link, patience: patience), language: .en,
                                  mySide: match.mySide, opponentName: match.opponentName,
                                  turnTimeLimit: turnTimeLimit, pace: .zero)
            link.onInterrupt = { [weak s] error in s?.opponentInterrupted(error) }
            return s
        }
        return Pair(challenger: session(matchA, challengerLink), guest: session(matchB, guestLink),
                    challengerLink: challengerLink, guestLink: guestLink)
    }

    /// Drives one player like a person would: pick a move or a replacement whenever it is their turn.
    private static func play(_ session: BattleSession, picks: [Int]) async {
        var turn = 0
        while session.outcome == nil, turn < 300 {
            if session.awaitingReplacement {
                await session.replace(with: session.switchTargets[0])
            } else if session.canChoose {
                let usable = session.state.usableMoves(for: session.mySide)
                await session.choose(usable.isEmpty ? .struggle : .move(usable[picks[turn % picks.count] % usable.count]))
            } else {
                await Task.yield()
                continue
            }
            turn += 1
        }
    }

    func testTwoMachinesPlayTheSameBattleToOppositeOutcomes() async throws {
        let pair = try await connectedPair(teamA: try team("red", count: 4), teamB: try team("blue", count: 3))
        await pair.challenger.start()
        await pair.guest.start()
        async let red: Void = Self.play(pair.challenger, picks: [1, 0, 1])
        async let blue: Void = Self.play(pair.guest, picks: [0, 1])
        _ = await (red, blue)

        XCTAssertEqual(pair.challenger.state, pair.guest.state, "lockstep: both machines hold the identical battle")
        let outcomes = [pair.challenger.outcome, pair.guest.outcome]
        XCTAssertTrue(outcomes == [.won, .lost] || outcomes == [.lost, .won] || outcomes == [.draw, .draw], "\(outcomes)")
        XCTAssertEqual(pair.guest.display.active[BattleSide.b.rawValue], pair.guest.state[.b].active)
        XCTAssertTrue(pair.guest.log.contains("Go! Blue0!"), "the guest sees its own team as its own")
        XCTAssertTrue(pair.challenger.log.contains("The opponent sent out Blue0!"))
    }

    func testForfeitWhileWaitingOnTheOpponentEndsBothSides() async throws {
        let pair = try await connectedPair(teamA: try team("red"), teamB: try team("blue"))
        await pair.challenger.start()
        await pair.guest.start()
        let pending = Task { await pair.challenger.choose(.move(0)) }
        while !pair.challenger.isWaitingForOpponent { await Task.yield() }
        await pair.challenger.forfeit()
        await pending.value
        XCTAssertEqual(pair.challenger.outcome, .lost)
        for _ in 0..<50 where pair.guest.outcome == nil { await Task.yield() }
        XCTAssertEqual(pair.guest.outcome, .won, "the guest hears the forfeit while still picking a move")
        XCTAssertEqual(pair.guest.log.last, "The opponent forfeited!")
    }

    func testDisconnectMidBattleGivesTheRemainingPlayerTheWin() async throws {
        let pair = try await connectedPair(teamA: try team("red"), teamB: try team("blue"))
        await pair.challenger.start()
        await pair.guest.start()
        let pending = Task { await pair.guest.choose(.move(0)) }
        while !pair.guest.isWaitingForOpponent { await Task.yield() }
        pair.challengerLink.transport.close()
        await pending.value
        XCTAssertEqual(pair.guest.outcome, .won)
        XCTAssertEqual(pair.guest.log.last, "The opponent left the battle. You win!")
    }

    func testDivergedStateAbortsWithoutAWinner() async throws {
        let pair = try await connectedPair(teamA: try team("red"), teamB: try team("blue"))
        await pair.challenger.start()
        await pair.guest.start()
        // The peer claims a state digest this machine never had.
        try pair.guestLink.send(.action(turn: 1, action: .move(0), digest: "not-our-state"))
        await pair.challenger.choose(.move(0))
        XCTAssertEqual(pair.challenger.outcome, .aborted)
        XCTAssertEqual(pair.challenger.message, "The battle ended because of a connection problem. No winner.")
    }

    func testIllegalMoveFromThePeerAbortsInsteadOfCrashing() async throws {
        let pair = try await connectedPair(teamA: try team("red"), teamB: try team("blue"))
        await pair.challenger.start()
        let digest = pair.challenger.state.digest
        try pair.guestLink.send(.action(turn: 1, action: .move(9), digest: digest))
        await pair.challenger.choose(.move(0))
        XCTAssertEqual(pair.challenger.outcome, .aborted)
    }

    func testSilentPeerTimesOut() async throws {
        let pair = try await connectedPair(teamA: try team("red"), teamB: try team("blue"), patience: .milliseconds(50))
        await pair.challenger.start()
        await pair.challenger.choose(.move(0))
        XCTAssertEqual(pair.challenger.outcome, .won)
        XCTAssertEqual(pair.challenger.log.last, "The opponent left the battle. You win!")
    }

    func testIdlePlayerGetsARandomMoveWhenTheTurnTimerRunsOut() async throws {
        let pair = try await connectedPair(teamA: try team("red"), teamB: try team("blue"), turnTimeLimit: .milliseconds(60))
        await pair.challenger.start()
        await pair.guest.start()
        XCTAssertNotNil(pair.challenger.turnDeadline)
        for _ in 0..<400 where pair.challenger.state.turn == 1 || pair.guest.state.turn == 1 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertGreaterThan(pair.challenger.state.turn, 1, "the challenger's timer picked a move")
        XCTAssertGreaterThan(pair.guest.state.turn, 1, "the guest's timer picked a move and the turn resolved on both")
        XCTAssertNotEqual(pair.challenger.outcome, .aborted, "timed-out picks travel like normal ones")
        pair.challenger.abandon()
        pair.guest.abandon()
    }

    func testGarbageFromThePeerAbortsTheBattle() async throws {
        let pair = try await connectedPair(teamA: try team("red"), teamB: try team("blue"))
        await pair.challenger.start()
        try pair.guestLink.transport.send(Data("definitely not json".utf8))
        for _ in 0..<50 where pair.challenger.outcome == nil { await Task.yield() }
        XCTAssertEqual(pair.challenger.outcome, .aborted)
        XCTAssertEqual(pair.challenger.message, "The battle ended because of a connection problem. No winner.")
    }

    /// A forfeit that lands while our turn is still animating must not be lost.
    func testForfeitArrivingDuringPlaybackIsAppliedAfterwards() async throws {
        let (left, right) = LoopbackTransport.pair()
        let link = BattleLink(transport: left), peer = BattleLink(transport: right)
        let session = BattleSession(myTeam: try team("red"), opponentTeam: try team("blue"), seed: 3,
                                    opponent: NetworkOpponent(link: link, patience: .seconds(5)), language: .en,
                                    pace: .milliseconds(15))
        link.onInterrupt = { [weak session] error in session?.opponentInterrupted(error) }
        await session.start()
        try peer.send(.action(turn: 1, action: .move(0), digest: session.state.digest))
        try peer.send(.forfeit)
        await session.choose(.move(0))
        XCTAssertGreaterThan(session.state.turn, 1, "the turn itself still resolved")
        XCTAssertEqual(session.outcome, .won)
        XCTAssertEqual(session.log.last, "The opponent forfeited!")
    }

    func testVersionMismatchIsReportedDuringHandshake() async throws {
        let (left, right) = LoopbackTransport.pair()
        let mine = BattleLink(transport: left), theirs = BattleLink(transport: right)
        try theirs.send(.hello(protocolVersion: 99, trainer: "Future"))
        do {
            _ = try await BattleHandshake.run(mine, isChallenger: true, trainer: "Red", team: try team("a"), nonce: 1)
            XCTFail("expected a version error")
        } catch {
            XCTAssertEqual(error as? BattleLinkError, .incompatibleVersion(99))
        }
    }
}
