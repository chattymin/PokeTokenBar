import AppKit
import XCTest
@testable import PokeTokenBar

/// The card's copy button: a banner of the Pokémon raised, on the pasteboard only (the owner, 2026-11-09: "uniquement
/// le presse-papier").
@MainActor
final class CatchBannerTests: XCTestCase {
    private let hatched = Date(timeIntervalSince1970: 1_794_394_800)

    private func store(active: MonState?) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "d"
        st.claimedTodayTokensByProvider = ["test": 0]
        st.language = .fr
        st.active = active
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("catch-banner-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: StubProvider(value: EvoLine(baseID: 480, tree: EvoNode(speciesID: 480, children: []),
                                                                    rarity: .legendary, names: [:])),
                              clock: { Date(timeIntervalSince1970: 1_794_398_400) }, fileURL: url,
                              rng: SeededRNG(seed: 3), difficulty: 0.1)
    }

    /// A Uxie: Psychic, Naive, IVs 31 × 5 and 0 (155/186), hatched at `hatched`.
    private func uxie() -> MonState {
        var mon = MonState(baseID: 480, pathIDs: [480], stageIndex: 0, usedAtStage: 7_000_000, rarity: .legendary,
                           totalForms: 1, nature: .naive)
        var profile = PokemonProfile.generate(seed: 480)
        for path in CompanionStore.ivKeyPaths { profile.ivs[keyPath: path] = 31 }
        profile.ivs.speed = 0
        mon.profile = profile
        mon.raising = RaisingRecord(hatchedAt: hatched)
        return mon
    }

    private func stillSprite() -> NSImage {
        let image = NSImage(size: NSSize(width: 63, height: 78))
        image.lockFocus()
        NSColor.systemPink.setFill()
        NSRect(x: 10, y: 10, width: 40, height: 50).fill()
        image.unlockFocus()
        return image
    }

    func testTheBannerSaysWhoItIs() throws {
        let s = try store(active: uxie())
        let info = try XCTUnwrap(CatchBanner.info(s))
        XCTAssertEqual(info.number, 480)
        XCTAssertEqual(info.rarity, .legendary)
        XCTAssertEqual(info.types, ["psychic"])
        XCTAssertEqual(info.nature, .naive)
        XCTAssertEqual(info.ivTotal, 155)
        XCTAssertEqual(info.hatchedAt, hatched)
        XCTAssertTrue(info.dexLine.hasPrefix("Espèces "), info.dexLine)
        XCTAssertFalse(info.isShiny)
    }

    func testAnEggHasNoBanner() throws {
        let s = try store(active: nil)
        XCTAssertNil(CatchBanner.info(s))
    }

    /// The image: opaque to its corners (the popover's background around the card), three pixels a point.
    func testTheImageIsOpaqueAndSharp() async throws {
        let s = try store(active: uxie())
        let sprite = stillSprite()
        let rendered = await CatchImage.render(s, colorScheme: .light, sprite: { _, _, _ in sprite })
        let image = try XCTUnwrap(rendered)
        XCTAssertEqual(image.width, Int((CatchBanner.width + 2 * CatchBanner.margin) * CatchImage.scale))
        let rep = NSBitmapImageRep(cgImage: image)
        for (x, y) in [(0, 0), (image.width - 1, 0), (0, image.height - 1), (image.width - 1, image.height - 1)] {
            XCTAssertEqual(rep.colorAt(x: x, y: y)?.alphaComponent ?? 0, 1, accuracy: 0.001, "corner \(x),\(y)")
        }
    }

    /// PNG and TIFF on the pasteboard, the same picture in both; nothing else.
    func testTheCopyGoesToThePasteboardOnly() async throws {
        let s = try store(active: uxie())
        let sprite = stillSprite()
        let rendered = await CatchImage.render(s, colorScheme: .dark, sprite: { _, _, _ in sprite })
        let image = try XCTUnwrap(rendered)
        let board = NSPasteboard(name: NSPasteboard.Name("catch-banner-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        XCTAssertTrue(CatchImage.copy(image, to: board))
        let types = board.types ?? []
        XCTAssertTrue(types.contains(.png) && types.contains(.tiff), "\(types)")
        // macOS adds the legacy names of the same two ("Apple PNG pasteboard type"), nothing else.
        XCTAssertTrue(types.allSatisfy { $0.rawValue.lowercased().contains("png") || $0.rawValue.lowercased().contains("tiff") },
                      "\(types)")
        let png = try XCTUnwrap(board.data(forType: .png).flatMap(NSBitmapImageRep.init(data:)))
        XCTAssertEqual(png.pixelsWide, image.width)
        XCTAssertEqual(png.pixelsHigh, image.height)
    }

    func testTheButtonSpeaksEveryLanguage() {
        for language in AppLanguage.allCases {
            let l = L(language)
            for text in [l.catchImageCopyHint, l.catchImageCopied] {
                XCTAssertFalse(text.isEmpty, "\(language)")
                XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "\(language)")
            }
        }
        XCTAssertNotEqual(L(.fr).catchImageCopyHint, L(.en).catchImageCopyHint)
    }

    /// The owner, 2026-11-16: Home's dungeon cards are copied as they stand, at the popover's width, three pixels a
    /// point, without their buttons (an AppKit button draws as a placeholder in an image).
    func testADungeonCardIsCopiedAsItStands() throws {
        let s = try store(active: nil)
        let loot = ExpeditionLoot(candies: 3)
        s.changeDungeons {
            $0.lastResult = ExpeditionResult(dungeon: .viridianForest, won: true, startedAt: Date(), endedAt: Date(), tokens: 1, battles: 2,
                                             boss: ExpeditionBoss(speciesID: 12, form: nil, isShiny: false), caught: true, loot: loot,
                                             firstVictory: false, unlocked: [], unlockedMove: nil, log: [])
        }
        let card = ExpeditionResultCard(store: s, nav: PopoverNavigation())
        let image = try XCTUnwrap(CardSnapshotButton<ExpeditionResultCard>.render(card, colorScheme: .dark))
        XCTAssertEqual(image.width, Int(((PopoverMetrics.scrollContentWidth + 2 * CatchBanner.margin) * CatchImage.scale).rounded()))
        XCTAssertGreaterThan(image.height, image.width / 3, "the card, not an empty frame")
        for language in AppLanguage.allCases { XCTAssertFalse(L(language).cardImageCopyHint.isEmpty) }
        XCTAssertNotEqual(L(.fr).cardImageCopyHint, L(.en).cardImageCopyHint)
    }
}
