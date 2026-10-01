import XCTest
@testable import PokeTokenBar

private enum MegaProviderError: Error { case unavailable }

private struct OfflineMegaProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw MegaProviderError.unavailable }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw MegaProviderError.unavailable }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw MegaProviderError.unavailable }
}

private final class MegaClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
final class MegaEvolutionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func tempURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-mega-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("companion-state.json")
    }

    private func defaults(_ name: String) -> UserDefaults {
        let suite = "ptb-mega-tests-\(name)-\(UUID().uuidString)"
        let value = UserDefaults(suiteName: suite)!
        value.removePersistentDomain(forName: suite)
        return value
    }

    private func stateWithFinal(_ finalID: Int = 3, shiny: Bool = false) -> CompanionState {
        var state = CompanionState()
        state.installBaselineSet = true
        state.usedSinceInstall = MegaStone.price
        let baseID: Int
        let chain: [Int]
        switch finalID {
        case 3: baseID = 1; chain = [1, 2, 3]
        case 6: baseID = 4; chain = [4, 5, 6]
        default: baseID = 7; chain = [7, 8, 9]
        }
        state.dex = [DexEntry(baseID: baseID, finalID: finalID, chainOrder: chain,
                              rarity: .common, caughtAt: now, isShiny: shiny)]
        state.representativeSpeciesID = finalID
        return state
    }

    private func stateWithOwnedSpecies(_ speciesID: Int, shiny: Bool = false) -> CompanionState {
        var state = CompanionState()
        state.installBaselineSet = true
        state.usedSinceInstall = MegaStone.price
        state.dex = [DexEntry(baseID: speciesID, finalID: speciesID, chainOrder: [speciesID],
                              rarity: .common, caughtAt: now, isShiny: shiny)]
        state.representativeSpeciesID = speciesID
        return state
    }

    private func store(_ state: CompanionState, clock: MegaClock, name: String) throws -> CompanionStore {
        let url = tempURL(name)
        try JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: OfflineMegaProvider(), clock: { clock.now },
                              fileURL: url, defaults: defaults(name))
    }

    func testMegaStonePurchaseIsPermanentAndRejectsDuplicatesOrInsufficientFunds() throws {
        let clock = MegaClock(now)
        var state = stateWithFinal()
        state.usedSinceInstall = MegaStone.price - 1
        let insufficientStore = try store(state, clock: clock, name: "purchase")

        XCTAssertFalse(insufficientStore.canBuy(.venusaurite))
        XCTAssertFalse(insufficientStore.buy(.venusaurite))

        var enoughState = state
        enoughState.usedSinceInstall = MegaStone.price * 2
        let fundedStore = try store(enoughState, clock: clock, name: "purchase-funded")
        XCTAssertTrue(fundedStore.canBuy(.venusaurite))
        XCTAssertTrue(fundedStore.buy(.venusaurite))
        XCTAssertEqual(fundedStore.megaStoneCount(.venusaurite), 1)
        XCTAssertTrue(fundedStore.bagMegaStones.contains(.venusaurite))
        XCTAssertTrue(fundedStore.purchasableMegaStones.contains(.venusaurite),
                      "An owned stone remains visible for its registered species")
        XCTAssertFalse(fundedStore.canBuy(.venusaurite), "A permanent stone cannot be bought twice")
        XCTAssertFalse(fundedStore.buy(.venusaurite))
        XCTAssertEqual(fundedStore.megaStoneCount(.venusaurite), 1)
        XCTAssertEqual(fundedStore.state.spentTokens, MegaStone.price)
    }

    func testMegaStoneShopRequiresRegisteredFinalSpeciesBeforePurchase() throws {
        let clock = MegaClock(now)
        var partial = CompanionState()
        partial.installBaselineSet = true
        partial.usedSinceInstall = MegaStone.price * 2
        partial.dex = [DexEntry(baseID: 1, finalID: 2, chainOrder: [1, 2],
                                rarity: .common, caughtAt: now)]
        let partialStore = try store(partial, clock: clock, name: "shop-eligibility-partial")

        XCTAssertFalse(partialStore.purchasableMegaStones.contains(.venusaurite))
        XCTAssertFalse(partialStore.canBuy(.venusaurite))
        XCTAssertFalse(partialStore.buy(.venusaurite))
        XCTAssertEqual(partialStore.state.spentTokens, 0,
                       "A stone for an unregistered species cannot spend tokens")
        XCTAssertEqual(partialStore.megaStoneCount(.venusaurite), 0)

        var eligible = partial
        eligible.dex.append(DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3],
                                     rarity: .common, caughtAt: now))
        let eligibleStore = try store(eligible, clock: clock, name: "shop-eligibility-final")

        XCTAssertTrue(eligibleStore.purchasableMegaStones.contains(.venusaurite))
        XCTAssertTrue(eligibleStore.canBuy(.venusaurite))
        XCTAssertTrue(eligibleStore.buy(.venusaurite))
        XCTAssertTrue(eligibleStore.bagMegaStones.contains(.venusaurite))
    }

    func testMegaPriceUsesShopDifficulty() throws {
        let clock = MegaClock(now)
        let store = try store(stateWithFinal(), clock: clock, name: "difficulty")
        XCTAssertEqual(MegaStone.price, 500_000_000)
        store.setShopDifficulty(0.5)
        XCTAssertEqual(store.price(of: MegaStone.venusaurite), 250_000_000)
        store.setShopDifficulty(2)
        XCTAssertEqual(store.price(of: MegaStone.venusaurite), 1_000_000_000)
    }

    func testMegaEvolutionRequiresOwnedFinalSpecies() throws {
        let clock = MegaClock(now)
        var partial = CompanionState()
        partial.usedSinceInstall = MegaStone.price
        partial.dex = [DexEntry(baseID: 1, finalID: 2, chainOrder: [1, 2],
                                rarity: .common, caughtAt: now)]
        partial.inventory[MegaStone.venusaurite.inventoryKey] = 1
        let partialStore = try store(partial, clock: clock, name: "eligibility")

        XCTAssertFalse(partialStore.canMegaEvolve(.venusaurite))
        XCTAssertFalse(partialStore.startMegaEvolution(.venusaurite))

        var eligible = partial
        eligible.dex.append(DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3],
                                     rarity: .common, caughtAt: now))
        let eligibleStore = try store(eligible, clock: clock, name: "eligibility-final")
        XCTAssertTrue(eligibleStore.canMegaEvolve(.venusaurite))
        XCTAssertTrue(eligibleStore.startMegaEvolution(.venusaurite))
    }

    func testMegaActivationImmediatelyChangesDisplayAndSelectsShiny() throws {
        let clock = MegaClock(now)
        var state = stateWithFinal(shiny: false)
        state.dex.append(DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3],
                                  rarity: .common, caughtAt: now, isShiny: true))
        state.inventory[MegaStone.venusaurite.inventoryKey] = 1
        let store = try store(state, clock: clock, name: "shiny")
        let originalSubject = store.representativeSubject

        XCTAssertTrue(store.startMegaEvolution(.venusaurite))
        XCTAssertEqual(store.activeMegaEvolution?.stone, .venusaurite)
        XCTAssertEqual(store.activeMegaEvolution?.megaSpeciesID, 10033)
        XCTAssertEqual(store.representativeSubject.speciesID, 10033)
        XCTAssertTrue(store.representativeSubject.isShiny)
        XCTAssertEqual(store.state.representativeSpeciesID, 3,
                       "Mega activation must leave the underlying representative untouched")

        XCTAssertTrue(store.endMegaEvolution())
        XCTAssertNil(store.activeMegaEvolution)
        XCTAssertEqual(store.representativeSubject, originalSubject)
    }

    func testMegaActivationFollowsRequestedAppearanceAndRequiresMatchingCatch() throws {
        let clock = MegaClock(now)

        var normalOnly = stateWithFinal(shiny: false)
        normalOnly.inventory[MegaStone.venusaurite.inventoryKey] = 1
        let normalStore = try store(normalOnly, clock: clock, name: "appearance-normal")
        XCTAssertTrue(normalStore.canMegaEvolve(.venusaurite, isShiny: false))
        XCTAssertFalse(normalStore.canMegaEvolve(.venusaurite, isShiny: true))
        XCTAssertFalse(normalStore.startMegaEvolution(.venusaurite, isShiny: true))
        XCTAssertTrue(normalStore.startMegaEvolution(.venusaurite, isShiny: false))
        XCTAssertFalse(normalStore.activeMegaEvolution?.isShiny == true)

        var shinyOnly = stateWithFinal(shiny: true)
        shinyOnly.inventory[MegaStone.venusaurite.inventoryKey] = 1
        let shinyStore = try store(shinyOnly, clock: clock, name: "appearance-shiny")
        XCTAssertFalse(shinyStore.canMegaEvolve(.venusaurite, isShiny: false))
        XCTAssertTrue(shinyStore.canMegaEvolve(.venusaurite, isShiny: true))
        XCTAssertTrue(shinyStore.startMegaEvolution(.venusaurite, isShiny: true))
        XCTAssertTrue(shinyStore.activeMegaEvolution?.isShiny == true)
    }

    func testActiveMegaCanSwitchBetweenOwnedNormalAndShinyAppearances() throws {
        let clock = MegaClock(now)
        var state = stateWithFinal(shiny: false)
        state.dex.append(DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3],
                                  rarity: .common, caughtAt: now, isShiny: true))
        state.inventory[MegaStone.venusaurite.inventoryKey] = 1
        let store = try store(state, clock: clock, name: "active-appearance-toggle")

        XCTAssertTrue(store.startMegaEvolution(.venusaurite, isShiny: true))
        XCTAssertTrue(store.activeMegaEvolution?.isShiny == true)
        XCTAssertTrue(store.representativeSubject.isShiny)

        XCTAssertTrue(store.startMegaEvolution(.venusaurite, isShiny: false))
        XCTAssertFalse(store.activeMegaEvolution?.isShiny == true)
        XCTAssertFalse(store.representativeSubject.isShiny)

        XCTAssertTrue(store.startMegaEvolution(.venusaurite, isShiny: true))
        XCTAssertTrue(store.activeMegaEvolution?.isShiny == true)
        XCTAssertTrue(store.representativeSubject.isShiny)
    }

    func testRepresentativeAppearanceSelectionPersistsAndRejectsUnownedColor() throws {
        let clock = MegaClock(now)
        var state = stateWithFinal(shiny: false)
        state.dex.append(DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3],
                                  rarity: .common, caughtAt: now, isShiny: true))
        let url = tempURL("representative-appearance")
        try JSONEncoder().encode(state).write(to: url)
        let first = CompanionStore(provider: OfflineMegaProvider(), clock: { clock.now },
                                    fileURL: url, defaults: defaults("representative-appearance"))

        XCTAssertTrue(first.setRepresentativeSpeciesID(3, isShiny: false))
        XCTAssertFalse(first.representativeSubject.isShiny)
        XCTAssertTrue(first.setRepresentativeAppearance(isShiny: true))
        XCTAssertTrue(first.representativeSubject.isShiny)

        let second = CompanionStore(provider: OfflineMegaProvider(), clock: { clock.now },
                                     fileURL: url, defaults: defaults("representative-appearance-reload"))
        XCTAssertEqual(second.representativeIsShiny, true)
        XCTAssertTrue(second.representativeSubject.isShiny)

        XCTAssertTrue(second.setRepresentativeAppearance(isShiny: false))
        XCTAssertFalse(second.representativeSubject.isShiny)

        let shinyOnly = stateWithFinal(shiny: true)
        var unownedAppearanceState = shinyOnly
        unownedAppearanceState.representativeSpeciesID = nil
        let unownedURL = tempURL("representative-appearance-unowned")
        try JSONEncoder().encode(unownedAppearanceState).write(to: unownedURL)
        let shinyOnlyStore = CompanionStore(provider: OfflineMegaProvider(), clock: { clock.now },
                                             fileURL: unownedURL,
                                             defaults: defaults("representative-appearance-unowned"))
        XCTAssertFalse(shinyOnlyStore.setRepresentativeSpeciesID(3, isShiny: false))
        XCTAssertNil(shinyOnlyStore.representativeSpeciesID)
    }

    func testMultiFormStoneOwnershipActivatesEachMewtwoFormIndependently() throws {
        let clock = MegaClock(now)
        var state = stateWithOwnedSpecies(150)
        state.dex.append(DexEntry(baseID: 150, finalID: 150, chainOrder: [150],
                                  rarity: .common, caughtAt: now, isShiny: true))
        state.inventory[MegaStone.mewtwoniteX.inventoryKey] = 1
        state.inventory[MegaStone.mewtwoniteY.inventoryKey] = 1
        let store = try store(state, clock: clock, name: "mewtwo-forms")

        XCTAssertTrue(store.canMegaEvolve(.mewtwoniteX, isShiny: false))
        XCTAssertTrue(store.canMegaEvolve(.mewtwoniteY, isShiny: true))
        XCTAssertTrue(store.startMegaEvolution(.mewtwoniteX, isShiny: false))
        XCTAssertEqual(store.activeMegaEvolution?.megaSpeciesID, 10043)
        XCTAssertFalse(store.activeMegaEvolution?.isShiny == true)

        XCTAssertTrue(store.startMegaEvolution(.mewtwoniteY, isShiny: true))
        XCTAssertEqual(store.activeMegaEvolution?.megaSpeciesID, 10044)
        XCTAssertTrue(store.activeMegaEvolution?.isShiny == true)
        XCTAssertEqual(store.megaStoneCount(.mewtwoniteX), 1)
        XCTAssertEqual(store.megaStoneCount(.mewtwoniteY), 1)
    }

    func testExplicitRepresentativeChangeEndsMegaOverlay() throws {
        let clock = MegaClock(now)
        var state = stateWithFinal(3)
        state.dex.append(DexEntry(baseID: 4, finalID: 6, chainOrder: [4, 5, 6],
                                  rarity: .common, caughtAt: now))
        state.inventory[MegaStone.venusaurite.inventoryKey] = 1
        let store = try store(state, clock: clock, name: "manual-change")

        XCTAssertTrue(store.startMegaEvolution(.venusaurite))
        XCTAssertTrue(store.setRepresentativeSpeciesID(6))
        XCTAssertNil(store.activeMegaEvolution)
        XCTAssertEqual(store.representativeSubject.speciesID, 6)
    }

    func testStartingAnotherStoneReplacesTheSingleActiveOverlay() throws {
        let clock = MegaClock(now)
        var state = stateWithFinal(3)
        state.dex.append(DexEntry(baseID: 4, finalID: 6, chainOrder: [4, 5, 6],
                                  rarity: .common, caughtAt: now))
        state.inventory[MegaStone.venusaurite.inventoryKey] = 1
        state.inventory[MegaStone.charizarditeX.inventoryKey] = 1
        let store = try store(state, clock: clock, name: "replace-overlay")

        XCTAssertTrue(store.startMegaEvolution(.venusaurite))
        XCTAssertTrue(store.startMegaEvolution(.charizarditeX))
        XCTAssertEqual(store.activeMegaEvolution?.stone, .charizarditeX)
        XCTAssertEqual(store.representativeSubject.speciesID, 10034)
        XCTAssertEqual(store.state.representativeSpeciesID, 3,
                       "Replacing the overlay must keep the user's underlying representative")
        XCTAssertTrue(store.endMegaEvolution())
        XCTAssertEqual(store.representativeSubject.speciesID, 3,
                       "Turning off a cross-species menu overlay restores the prior representative")
    }

    func testMegaEvolutionPersistsAcrossStoreRestartWithoutExpiry() throws {
        let clock = MegaClock(now)
        var state = stateWithFinal()
        state.inventory[MegaStone.venusaurite.inventoryKey] = 1
        let url = tempURL("restart")
        try JSONEncoder().encode(state).write(to: url)
        let first = CompanionStore(provider: OfflineMegaProvider(), clock: { clock.now },
                                    fileURL: url, defaults: defaults("restart-1"))
        XCTAssertTrue(first.startMegaEvolution(.venusaurite))

        clock.now = now.addingTimeInterval(365 * 24 * 60 * 60)
        let second = CompanionStore(provider: OfflineMegaProvider(), clock: { clock.now },
                                    fileURL: url, defaults: defaults("restart-2"))
        XCTAssertEqual(second.activeMegaEvolution?.stone, .venusaurite)
        XCTAssertEqual(second.representativeSubject.speciesID, 10033)
        XCTAssertEqual(second.megaStoneCount(.venusaurite), 1,
                       "A permanent unlock remains available while its overlay is active")
    }

    func testLegacyExpiredDatesAreIgnoredAndNewStateOmitsThem() throws {
        var state = stateWithFinal()
        state.activeMegaEvolution = MegaEvolutionState(stone: .venusaurite, isShiny: true)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
                                   as? [String: Any])
        object["activeMegaEvolution"] = [
            "stone": MegaStone.venusaurite.rawValue,
            "isShiny": true,
            "megaSpeciesID": 99999,
            "startedAt": 0,
            "expiresAt": 1
        ]
        let oldData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(CompanionState.self, from: oldData)

        XCTAssertEqual(decoded.activeMegaEvolution?.stone, .venusaurite)
        XCTAssertTrue(decoded.activeMegaEvolution?.isShiny == true)
        XCTAssertEqual(decoded.activeMegaEvolution?.megaSpeciesID, 10033)

        let newJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded))
        let encoded = try XCTUnwrap(newJSON as? [String: Any])
        let active = try XCTUnwrap(encoded["activeMegaEvolution"] as? [String: Any])
        XCTAssertNil(active["megaSpeciesID"])
        XCTAssertNil(active["startedAt"])
        XCTAssertNil(active["expiresAt"])
        XCTAssertEqual(Set(active.keys), Set(["stone", "isShiny"]))
    }

    func testSaveTransferPreservesActiveOverlayWithNoUnlockBitButRejectsUnownedSpecies() throws {
        var state = stateWithFinal()
        state.inventory[MegaStone.venusaurite.inventoryKey] = 0
        state.activeMegaEvolution = MegaEvolutionState(stone: .venusaurite, isShiny: false)
        let data = try SaveTransfer.encode(state: state, appVersion: "test", deviceName: "test", now: now)
        let envelope = try SaveTransfer.decode(data)
        XCTAssertEqual(envelope.state.inventory[MegaStone.venusaurite.inventoryKey], 1,
                       "An active legacy overlay proves the stone was already unlocked")
        XCTAssertEqual(envelope.state.activeMegaEvolution?.stone, .venusaurite)

        let withoutFinal = CompanionState()
        let unownedData = try SaveTransfer.encode(state: withoutFinal, appVersion: "test", deviceName: "test", now: now)
        let unownedEnvelope = try SaveTransfer.decode(unownedData)
        XCTAssertNil(unownedEnvelope.state.activeMegaEvolution)
        XCTAssertEqual(unownedEnvelope.state.inventory[MegaStone.venusaurite.inventoryKey] ?? 0, 0,
                       "Corrupt active state must not grant a stone for an unowned species")
    }

    func testSaveTransferNormalizesActiveMegaToOwnedAppearance() throws {
        var normalOnly = stateWithFinal(shiny: false)
        normalOnly.inventory[MegaStone.venusaurite.inventoryKey] = 1
        normalOnly.activeMegaEvolution = MegaEvolutionState(stone: .venusaurite, isShiny: true)
        let normalData = try SaveTransfer.encode(state: normalOnly, appVersion: "test",
                                                 deviceName: "test", now: now)
        let normalizedNormal = try SaveTransfer.decode(normalData).state
        XCTAssertFalse(normalizedNormal.activeMegaEvolution?.isShiny == true,
                       "A shiny Mega overlay must fall back to the owned normal appearance")

        var shinyOnly = stateWithFinal(shiny: true)
        shinyOnly.inventory[MegaStone.venusaurite.inventoryKey] = 1
        shinyOnly.activeMegaEvolution = MegaEvolutionState(stone: .venusaurite, isShiny: false)
        let shinyData = try SaveTransfer.encode(state: shinyOnly, appVersion: "test",
                                                deviceName: "test", now: now)
        let normalizedShiny = try SaveTransfer.decode(shinyData).state
        XCTAssertTrue(normalizedShiny.activeMegaEvolution?.isShiny == true,
                      "A normal Mega overlay must fall back to the owned shiny appearance")
    }

    func testLegacyActiveOverlayRecoversPermanentUnlockAfterEnding() throws {
        let clock = MegaClock(now)
        var state = stateWithFinal()
        state.inventory[MegaStone.venusaurite.inventoryKey] = 0
        state.activeMegaEvolution = MegaEvolutionState(stone: .venusaurite, isShiny: false)
        let store = try store(state, clock: clock, name: "legacy-active")

        XCTAssertTrue(store.bagMegaStones.contains(.venusaurite))
        XCTAssertEqual(store.representativeSubject.speciesID, MegaStone.venusaurite.megaSpeciesID)
        XCTAssertEqual(store.megaStoneCount(.venusaurite), 1,
                       "An old active consumable save migrates to a permanent unlock")
        XCTAssertTrue(store.canMegaEvolve(.venusaurite))
        XCTAssertTrue(store.endMegaEvolution())
        XCTAssertNil(store.activeMegaEvolution)
        XCTAssertTrue(store.startMegaEvolution(.venusaurite))
    }

    func testLegacyPermanentStoneSaveMigratesToOnePermanentUnlock() throws {
        var legacy = stateWithFinal()
        legacy.megaStones = [.venusaurite]
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(CompanionState.self, from: data)

        XCTAssertEqual(decoded.inventory[MegaStone.venusaurite.inventoryKey], 1)
        XCTAssertTrue(decoded.megaStones.isEmpty)
    }

    func testPreviousQuantityMigratesToOnePermanentUnlock() throws {
        var previous = stateWithFinal()
        previous.inventory[MegaStone.venusaurite.inventoryKey] = 4
        let data = try JSONEncoder().encode(previous)
        let decoded = try JSONDecoder().decode(CompanionState.self, from: data)

        XCTAssertEqual(decoded.inventory[MegaStone.venusaurite.inventoryKey], 1)
    }

    func testMegaActivationCanBeReusedWithoutConsumingUnlock() throws {
        let clock = MegaClock(now)
        var state = stateWithFinal()
        let emptyStore = try store(state, clock: clock, name: "activation-empty")
        let before = emptyStore.state
        XCTAssertFalse(emptyStore.startMegaEvolution(.venusaurite))
        XCTAssertEqual(emptyStore.state.spentTokens, before.spentTokens)
        XCTAssertEqual(emptyStore.state.inventory, before.inventory)

        state.inventory[MegaStone.venusaurite.inventoryKey] = 1
        let store = try store(state, clock: clock, name: "activation-reuse")
        XCTAssertTrue(store.startMegaEvolution(.venusaurite))
        XCTAssertEqual(store.megaStoneCount(.venusaurite), 1)
        XCTAssertTrue(store.endMegaEvolution())
        XCTAssertTrue(store.startMegaEvolution(.venusaurite))
        XCTAssertEqual(store.megaStoneCount(.venusaurite), 1)
    }

    func testMegaStoneDescriptionsDoNotExposeInterpolationPlaceholdersOrTimeLimit() {
        for language in AppLanguage.allCases {
            for stone in MegaStone.allCases {
                let localization = L(language)
                let description = localization.megaStoneDescription(stone)
                XCTAssertFalse(localization.megaStoneName(stone).isEmpty)
                XCTAssertFalse(localization.megaFormName(stone).isEmpty)
                XCTAssertFalse(description.contains("megaStoneName"), "\(language): \(description)")
                XCTAssertFalse(description.contains("megaFormName"), "\(language): \(description)")
                XCTAssertFalse(description.contains("24"), "\(language): \(description)")
            }
        }
        XCTAssertTrue(L(.en).megaStoneDescription(.venusaurite).contains("Permanently"))
        for language in AppLanguage.allCases {
            XCTAssertFalse(L(language).megaStoneNoEligiblePokemon.isEmpty)
        }
    }

    func testMegaStoneCatalogCoversAllLegacyCollectibleForms() {
        let expected: [(MegaStone, Int, Int, String)] = [
            (.venusaurite, 3, 10033, "venusaurite"),
            (.charizarditeX, 6, 10034, "charizardite-x"),
            (.charizarditeY, 6, 10035, "charizardite-y"),
            (.blastoisinite, 9, 10036, "blastoisinite"),
            (.alakazite, 65, 10037, "alakazite"),
            (.gengarite, 94, 10038, "gengarite"),
            (.kangaskhanite, 115, 10039, "kangaskhanite"),
            (.pinsirite, 127, 10040, "pinsirite"),
            (.gyaradosite, 130, 10041, "gyaradosite"),
            (.aerodactylite, 142, 10042, "aerodactylite"),
            (.mewtwoniteX, 150, 10043, "mewtwonite-x"),
            (.mewtwoniteY, 150, 10044, "mewtwonite-y"),
            (.ampharosite, 181, 10045, "ampharosite"),
            (.scizorite, 212, 10046, "scizorite"),
            (.heracronite, 214, 10047, "heracronite"),
            (.houndoominite, 229, 10048, "houndoominite"),
            (.tyranitarite, 248, 10049, "tyranitarite"),
            (.blazikenite, 257, 10050, "blazikenite"),
            (.gardevoirite, 282, 10051, "gardevoirite"),
            (.mawilite, 303, 10052, "mawilite"),
            (.aggronite, 306, 10053, "aggronite"),
            (.medichamite, 308, 10054, "medichamite"),
            (.manectite, 310, 10055, "manectite"),
            (.banettite, 354, 10056, "banettite"),
            (.absolite, 359, 10057, "absolite"),
            (.garchompite, 445, 10058, "garchompite"),
            (.lucarionite, 448, 10059, "lucarionite"),
            (.abomasite, 460, 10060, "abomasite"),
            (.latiasite, 380, 10062, "latiasite"),
            (.latiosite, 381, 10063, "latiosite"),
            (.swampertite, 260, 10064, "swampertite"),
            (.sceptilite, 254, 10065, "sceptilite"),
            (.sablenite, 302, 10066, "sablenite"),
            (.altarianite, 334, 10067, "altarianite"),
            (.galladite, 475, 10068, "galladite"),
            (.audinite, 531, 10069, "audinite"),
            (.sharpedonite, 319, 10070, "sharpedonite"),
            (.slowbronite, 80, 10071, "slowbronite"),
            (.steelixite, 208, 10072, "steelixite"),
            (.pidgeotite, 18, 10073, "pidgeotite"),
            (.glalitite, 362, 10074, "glalitite"),
            (.metagrossite, 376, 10076, "metagrossite"),
            (.cameruptite, 323, 10087, "cameruptite"),
            (.lopunnite, 428, 10088, "lopunnite"),
            (.salamencite, 373, 10089, "salamencite"),
            (.beedrillite, 15, 10090, "beedrillite")
        ]

        XCTAssertEqual(MegaStone.allCases.count, expected.count)
        XCTAssertEqual(Set(MegaStone.allCases), Set(expected.map { $0.0 }))
        XCTAssertEqual(Set(expected.map { $0.2 }).count, expected.count,
                       "Each supported stone must point at a unique Mega form")
        for (stone, baseID, megaID, spriteName) in expected {
            XCTAssertEqual(stone.eligibleSpeciesID, baseID, "\(stone)")
            XCTAssertEqual(stone.megaSpeciesID, megaID, "\(stone)")
            XCTAssertEqual(stone.spriteName, spriteName, "\(stone)")
        }
    }

    func testMegaStaticSpriteMappingUsesPokeAPINumericFormIDs() {
        for stone in MegaStone.allCases {
            let url = SpriteStore.spriteURL(speciesID: stone.megaSpeciesID, animated: false, shiny: false)
            XCTAssertEqual(url.absoluteString,
                           "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/\(stone.megaSpeciesID).png")
            XCTAssertTrue(PokemonAssets.hasAnimatedSprite(speciesID: stone.megaSpeciesID))
            XCTAssertEqual(SpriteStore.spriteURL(speciesID: stone.megaSpeciesID,
                                                 animated: true, shiny: false).absoluteString,
                           "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/showdown/\(stone.megaSpeciesID).gif")
        }
        let shiny = SpriteStore.spriteURL(speciesID: MegaStone.charizarditeX.megaSpeciesID,
                                          animated: false, shiny: true)
        XCTAssertTrue(shiny.absoluteString.contains("/shiny/10034.png"))
        let shinyAnimated = SpriteStore.spriteURL(speciesID: MegaStone.charizarditeX.megaSpeciesID,
                                                  animated: true, shiny: true)
        XCTAssertEqual(shinyAnimated.absoluteString,
                       "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/showdown/shiny/10034.gif")
        XCTAssertTrue(PokemonAssets.hasAnimatedSprite(speciesID: 649))
        XCTAssertFalse(PokemonAssets.hasAnimatedSprite(speciesID: 650))
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 25, animated: true, shiny: false).absoluteString,
                       "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/25.gif")
        XCTAssertEqual(MegaStone.venusaurite.spriteName, "venusaurite")
        XCTAssertEqual(MegaStone.charizarditeX.spriteName, "charizardite-x")
        XCTAssertEqual(MegaStone.charizarditeY.spriteName, "charizardite-y")
        XCTAssertEqual(MegaStone.blastoisinite.spriteName, "blastoisinite")
        for stone in MegaStone.allCases {
            XCTAssertEqual(SpriteStore.itemURL(name: stone.spriteName)?.absoluteString,
                           "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items/\(stone.spriteName).png")
        }
    }
}
