import XCTest
@testable import PokeTokenBar

private struct GiftOfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class GiftTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func store(used: Int = 1_000_000_000, at url: URL? = nil) -> CompanionStore {
        let url = url ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("gift-\(UUID().uuidString).json")
        if !FileManager.default.fileExists(atPath: url.path) {
            let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":0,"
                + "\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[]}"
            try? Data(json.utf8).write(to: url)
        }
        return CompanionStore(provider: GiftOfflineProvider(), clock: { self.now }, fileURL: url)
    }

    func testOnlyConsumablesAreGiftable() {
        XCTAssertTrue(ItemKind.rareCandy.isGiftable)
        XCTAssertTrue(ItemKind.mint.isGiftable)
        XCTAssertFalse(ItemKind.shinyCharm.isGiftable)
    }

    func testOfferReservesWithoutSpendingAndCancelRestoresBalance() {
        let s = store()
        let gift = s.beginGift(.rareCandy, code: "ABC234")
        XCTAssertNotNil(gift)
        XCTAssertEqual(gift?.expiresAt, now.addingTimeInterval(60),
                       "the default pairing window must remain one minute")
        XCTAssertEqual(s.state.spentTokens, 0, "creating an offer must not debit the sender")
        XCTAssertEqual(s.availableTokens, 1_000_000_000 - RareCandy.price)

        s.cancelGift(id: gift!.id)
        XCTAssertEqual(s.availableTokens, 1_000_000_000)
        XCTAssertEqual(s.state.spentTokens, 0)
    }

    func testCannotOfferPassiveItemOrSpendReservedBalance() {
        let s = store(used: RareCandy.price)
        XCTAssertNil(s.beginGift(.shinyCharm, code: "ABC234"))
        XCTAssertNotNil(s.beginGift(.rareCandy, code: "ABC234"))
        XCTAssertFalse(s.buy(.mint), "ordinary shop purchases must respect the gift reservation")
        XCTAssertEqual(s.state.spentTokens, 0)
    }

    func testExpiredReservationIsDiscarded() {
        let s = store()
        XCTAssertNotNil(s.beginGift(.mint, code: "ABC234", lifetime: -1))
        s.discardExpiredGift()
        XCTAssertNil(s.state.pendingGift)
        XCTAssertEqual(s.availableTokens, 1_000_000_000)
    }

    func testGiftCountdownRoundsUpAndStopsAtZero() {
        let expiry = now.addingTimeInterval(60)
        XCTAssertEqual(GiftCountdown.text(until: expiry, now: now), "01:00")
        XCTAssertEqual(GiftCountdown.text(until: expiry, now: now.addingTimeInterval(0.1)), "01:00")
        XCTAssertEqual(GiftCountdown.text(until: expiry, now: now.addingTimeInterval(1)), "00:59")
        XCTAssertEqual(GiftCountdown.text(until: expiry, now: now.addingTimeInterval(61)), "00:00")
    }

    func testReceiptCreditsOnceAcrossRestart() {
        let receiverURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gift-receiver-\(UUID().uuidString).json")
        let sender = store()
        let gift = sender.beginGift(.mint, code: "ABC234")!
        let first = store(used: 0, at: receiverURL)

        XCTAssertEqual(first.receiveGift(gift), .received)
        XCTAssertEqual(first.itemCount(.mint), 1)
        let reloaded = store(used: 0, at: receiverURL)
        XCTAssertEqual(reloaded.receiveGift(gift), .alreadyReceived)
        XCTAssertEqual(reloaded.itemCount(.mint), 1, "a retried receipt must not duplicate inventory")
    }

    func testSenderDebitsOnlyAfterReceiptAndOnlyOnce() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gift-sender-\(UUID().uuidString).json")
        let s = store(at: url)
        let gift = s.beginGift(.rareCandy, code: "ABC234")!
        XCTAssertEqual(s.state.spentTokens, 0)

        XCTAssertTrue(s.completeGift(id: gift.id))
        XCTAssertEqual(s.state.spentTokens, RareCandy.price)
        let reloaded = store(at: url)
        XCTAssertTrue(reloaded.completeGift(id: gift.id))
        XCTAssertEqual(reloaded.state.spentTokens, RareCandy.price, "a retried ACK must not debit twice")
    }

    func testExpiredOrTamperedOfferIsRejected() {
        let s = store(used: 0)
        let expired = PendingGift(id: UUID(), code: "ABC234", kind: .mint,
                                  price: Mint.price, expiresAt: now.addingTimeInterval(-1))
        let wrongPrice = PendingGift(id: UUID(), code: "ABC234", kind: .mint,
                                     price: 1, expiresAt: now.addingTimeInterval(60))
        XCTAssertEqual(s.receiveGift(expired), .invalid)
        XCTAssertEqual(s.receiveGift(wrongPrice), .invalid)
        XCTAssertEqual(s.itemCount(.mint), 0)
    }

    func testLivePairingCodeIsNotExported() throws {
        let s = store()
        XCTAssertNotNil(s.beginGift(.mint, code: "ABC234"))
        let data = try s.exportedSaveData(appVersion: "test", deviceName: "Mac")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("ABC234"))
        XCTAssertNil(try SaveTransfer.decode(data).state.pendingGift)
    }

    /// Regression: the sender used to call `send(committed)` and immediately tear down every
    /// connection. The receiver had already stored the item, but never saw the final frame and
    /// displayed a false failure. Cleanup must remain deferred until send completion fires.
    func testFinalConnectionCleanupWaitsForSendCompletion() {
        var sendCompletion: (@MainActor () -> Void)?
        var didCleanUp = false

        GiftTransferFinalization.afterSendStarts({ completion in
            sendCompletion = completion
        }, cleanup: {
            didCleanUp = true
        })

        XCTAssertFalse(didCleanUp, "connection teardown must not race the committed frame")
        XCTAssertNotNil(sendCompletion)
        sendCompletion?()
        XCTAssertTrue(didCleanUp)
    }
}
