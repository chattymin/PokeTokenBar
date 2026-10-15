import XCTest
@testable import PokeTokenBar

/// Generation (region) ranges are derived purely from the National Dex number — no PokéAPI call.
final class PokedexRegionTests: XCTestCase {

    // MARK: region(forDexNumber:)

    func testRegionBoundariesMapToExpectedRegion() {
        XCTAssertEqual(PokedexRegion.region(forDexNumber: 1), .kanto)
        XCTAssertEqual(PokedexRegion.region(forDexNumber: 151), .kanto)
        XCTAssertEqual(PokedexRegion.region(forDexNumber: 152), .johto)
        XCTAssertEqual(PokedexRegion.region(forDexNumber: 251), .johto)
        XCTAssertEqual(PokedexRegion.region(forDexNumber: 252), .hoenn)
        XCTAssertEqual(PokedexRegion.region(forDexNumber: 386), .hoenn)
        XCTAssertEqual(PokedexRegion.region(forDexNumber: 387), .sinnoh)
        XCTAssertEqual(PokedexRegion.region(forDexNumber: 493), .sinnoh)
        XCTAssertEqual(PokedexRegion.region(forDexNumber: 494), .unova)
        XCTAssertEqual(PokedexRegion.region(forDexNumber: 649), .unova)
    }

    func testRegionIsNilOutsideGen1Through5() {
        XCTAssertNil(PokedexRegion.region(forDexNumber: 0))
        XCTAssertNil(PokedexRegion.region(forDexNumber: -5))
        XCTAssertNil(PokedexRegion.region(forDexNumber: 650))
        XCTAssertNil(PokedexRegion.region(forDexNumber: 10_000))
    }

    func testRegionTotalsMatchGenerationCounts() {
        XCTAssertEqual(PokedexRegion.kanto.total, 151)
        XCTAssertEqual(PokedexRegion.johto.total, 100)
        XCTAssertEqual(PokedexRegion.hoenn.total, 135)
        XCTAssertEqual(PokedexRegion.sinnoh.total, 107)
        XCTAssertEqual(PokedexRegion.unova.total, 156)
    }

    func testIdentifiableIdsAreStable() {
        XCTAssertEqual(PokedexRegion.hoenn.id, "hoenn")
        XCTAssertEqual(DexCompletion(region: .sinnoh, owned: 3, shinyOwned: 0).id, "sinnoh")
    }

    func testNationalTotalIsSumOfAllRegions() {
        XCTAssertEqual(PokedexRegion.allCases.map(\.total).reduce(0, +), PokedexRegion.nationalTotal)
        XCTAssertEqual(PokedexRegion.nationalTotal, 649)
    }

    func testRegionRangesAreContiguousAndNonOverlapping() {
        let ordered = PokedexRegion.allCases
        for (lower, upper) in zip(ordered, ordered.dropFirst()) {
            XCTAssertEqual(lower.dexRange.upperBound + 1, upper.dexRange.lowerBound)
        }
        XCTAssertEqual(ordered.first?.dexRange.lowerBound, 1)
        XCTAssertEqual(ordered.last?.dexRange.upperBound, PokedexRegion.nationalTotal)
    }

    // MARK: regionCompletions

    func testPartialRegionCompletionCountsOwnedInRange() {
        let owned: [(id: Int, isShiny: Bool)] = [
            (1, false), (4, false), (7, false),   // Kanto
            (152, false),                          // Johto
            (999, false),                          // out of range, ignored
        ]
        let completions = DexProgress.regionCompletions(owned: owned)
        let kanto = completions.first { $0.region == .kanto }
        XCTAssertEqual(kanto?.owned, 3)
        XCTAssertEqual(kanto?.total, 151)
        XCTAssertFalse(kanto?.isComplete ?? true)
        let johto = completions.first { $0.region == .johto }
        XCTAssertEqual(johto?.owned, 1)
    }

    func testDuplicateOwnedIdsAreNotDoubleCounted() {
        let owned: [(id: Int, isShiny: Bool)] = [(25, false), (25, true), (26, false)]
        let kanto = DexProgress.regionCompletions(owned: owned).first { $0.region == .kanto }
        XCTAssertEqual(kanto?.owned, 2)
    }

    func testCompleteRegionReportsIsComplete() {
        let owned = PokedexRegion.johto.dexRange.map { (id: $0, isShiny: false) }
        let johto = DexProgress.regionCompletions(owned: owned).first { $0.region == .johto }
        XCTAssertEqual(johto?.owned, 100)
        XCTAssertTrue(johto?.isComplete ?? false)
        XCTAssertFalse(johto?.isShinyComplete ?? true)
    }

    func testShinyCompleteRequiresEverySpeciesShiny() {
        var owned = PokedexRegion.johto.dexRange.map { (id: $0, isShiny: true) }
        owned[0].isShiny = false
        let johto = DexProgress.regionCompletions(owned: owned).first { $0.region == .johto }
        XCTAssertTrue(johto?.isComplete ?? false)
        XCTAssertFalse(johto?.isShinyComplete ?? true)
        XCTAssertEqual(johto?.shinyOwned, 99)
    }

    // MARK: badges

    func testNoBadgesWhenNothingComplete() {
        let owned: [(id: Int, isShiny: Bool)] = [(1, false), (2, false)]
        XCTAssertTrue(DexProgress.earnedBadges(owned: owned, unownFormsCollected: 0).isEmpty)
    }

    func testCompletingARegionEarnsItsBadgeOnly() {
        let owned = PokedexRegion.kanto.dexRange.map { (id: $0, isShiny: false) }
        let badges = DexProgress.earnedBadges(owned: owned, unownFormsCollected: 0)
        XCTAssertTrue(badges.contains(.region(.kanto)))
        XCTAssertFalse(badges.contains(.regionShiny(.kanto)))
        XCTAssertFalse(badges.contains(.national))
    }

    func testShinyRegionEarnsBothRegionAndShinyBadges() {
        let owned = PokedexRegion.kanto.dexRange.map { (id: $0, isShiny: true) }
        let badges = DexProgress.earnedBadges(owned: owned, unownFormsCollected: 0)
        XCTAssertTrue(badges.contains(.region(.kanto)))
        XCTAssertTrue(badges.contains(.regionShiny(.kanto)))
    }

    func testUnownBadgeEarnedAtTwentyEightForms() {
        let total = UnownForm.allCases.count
        XCTAssertFalse(DexProgress.earnedBadges(owned: [], unownFormsCollected: total - 1).contains(.unown))
        XCTAssertTrue(DexProgress.earnedBadges(owned: [], unownFormsCollected: total).contains(.unown))
    }

    func testNationalBadgeRequiresEverySpecies() {
        let full = PokedexRegion.nationalRange.map { (id: $0, isShiny: false) }
        let badges = DexProgress.earnedBadges(owned: full, unownFormsCollected: 0)
        XCTAssertTrue(badges.contains(.national))
        XCTAssertFalse(badges.contains(.nationalShiny))
        XCTAssertTrue(PokedexRegion.allCases.allSatisfy { badges.contains(.region($0)) })
    }

    func testNationalShinyBadgeRequiresEverySpeciesShiny() {
        let full = PokedexRegion.nationalRange.map { (id: $0, isShiny: true) }
        let badges = DexProgress.earnedBadges(owned: full, unownFormsCollected: 0)
        XCTAssertTrue(badges.contains(.national))
        XCTAssertTrue(badges.contains(.nationalShiny))
    }

    // Region complete but national incomplete — the B-only branch the defect protocol asks for.
    func testRegionCompleteDoesNotImplyNational() {
        let owned = PokedexRegion.kanto.dexRange.map { (id: $0, isShiny: false) }
        let badges = DexProgress.earnedBadges(owned: owned, unownFormsCollected: 0)
        XCTAssertTrue(badges.contains(.region(.kanto)))
        XCTAssertFalse(badges.contains(.national))
    }

    // MARK: newlyEarnedBadges — notify-once semantics

    func testNewlyEarnedReturnsEveryBadgeWhenNothingNotified() {
        let earned: [DexBadge] = [.region(.kanto), .national]
        let new = DexProgress.newlyEarnedBadges(earned: earned, alreadyNotified: [])
        XCTAssertEqual(new, earned)
    }

    func testNewlyEarnedExcludesAlreadyNotifiedBadges() {
        let earned: [DexBadge] = [.region(.kanto), .national]
        let new = DexProgress.newlyEarnedBadges(earned: earned, alreadyNotified: ["region.kanto"])
        XCTAssertEqual(new, [.national])
    }

    func testNewlyEarnedIsEmptyWhenAllNotified() {
        let earned: [DexBadge] = [.region(.kanto), .national]
        let notified = Set(earned.map(\.notificationKey))
        XCTAssertTrue(DexProgress.newlyEarnedBadges(earned: earned, alreadyNotified: notified).isEmpty)
    }

    func testBadgeNotificationKeysAreStableAndUnique() {
        let badges: [DexBadge] = [
            .region(.kanto), .regionShiny(.kanto), .region(.unova),
            .unown, .national, .nationalShiny,
        ]
        let keys = badges.map(\.notificationKey)
        XCTAssertEqual(Set(keys).count, keys.count)
        // Keys are persisted, so they must not drift.
        XCTAssertEqual(DexBadge.region(.kanto).notificationKey, "region.kanto")
        XCTAssertEqual(DexBadge.regionShiny(.kanto).notificationKey, "regionShiny.kanto")
        XCTAssertEqual(DexBadge.unown.notificationKey, "unown")
        XCTAssertEqual(DexBadge.national.notificationKey, "national")
        XCTAssertEqual(DexBadge.nationalShiny.notificationKey, "nationalShiny")
    }
}
