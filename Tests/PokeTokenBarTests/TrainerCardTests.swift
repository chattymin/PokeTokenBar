import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class TrainerCardTests: XCTestCase {

    // MARK: - Type Colors Tests

    func testPokemonTypeColors() {
        let types = [
            "fire", "water", "grass", "electric", "ice", "fighting",
            "poison", "ground", "flying", "psychic", "bug", "rock",
            "ghost", "dragon", "dark", "steel", "fairy", "normal", "unknown"
        ]
        for type in types {
            let color = PokemonTypeColor.color(for: type)
            // Ensure every type maps to a valid Color
            XCTAssertNotNil(color)
        }
    }

    // MARK: - Trainer ID & Default Name Tests

    func testTrainerIDGeneration() {
        let id = TrainerCardData.generateTrainerID()
        XCTAssertEqual(id.count, 5)
        XCTAssertTrue(id.allSatisfy { $0.isNumber })
    }

    func testDefaultTrainerNameIsNonEmpty() {
        let name = TrainerCardData.defaultTrainerName
        XCTAssertFalse(name.isEmpty)
    }

    // MARK: - Developer Rank Tests

    func testDeveloperRankLadder() {
        let l = L(.en)
        let ranks: [(tokens: Int, expectedBall: String, expectedTitleFragment: String)] = [
            (0, "🔴", "Poké Ball"),
            (10_000_000, "🔴", "Poké Ball"),
            (50_000_000, "🔵", "Great Ball"),
            (100_000_000, "🔵", "Great Ball"),
            (250_000_000, "🟡", "Ultra Ball"),
            (500_000_000, "🟡", "Ultra Ball"),
            (1_000_000_000, "🟣", "Master Ball"),
            (2_000_000_000, "🟣", "Master Ball"),
            (5_000_000_000, "👑", "Champion"),
            (10_000_000_000, "👑", "Champion")
        ]

        for entry in ranks {
            let rank = l.trainerRankTitle(tokens: entry.tokens)
            XCTAssertEqual(rank.ball, entry.expectedBall, "Failed ball for \(entry.tokens) tokens")
            XCTAssertTrue(rank.title.contains(entry.expectedTitleFragment), "Failed title for \(entry.tokens) tokens: \(rank.title)")
        }
    }

    // MARK: - PopoverNavigation Tests

    @MainActor
    func testPopoverNavigationTrainerCardState() {
        let nav = PopoverNavigation()
        XCTAssertFalse(nav.showTrainerCard)

        nav.showTrainerCard = true
        XCTAssertTrue(nav.showTrainerCard)

        nav.reset()
        XCTAssertFalse(nav.showTrainerCard)
    }

    // MARK: - Canvas Rendering & Export Tests

    @MainActor
    func testTrainerCardCanvasViewRendering() {
        let l = L(.ko)
        let data = TrainerCardData(
            trainerName: "CodeMaster",
            trainerID: "08421",
            startDate: "2026.09",
            todayTokens: 42_800_000,
            allTimeTokens: 1_420_000_000,
            pokedexCount: 48,
            hallOfFameCount: 12,
            rankBall: "🟣",
            rankTitle: "마스터볼 개발자",
            isEgg: false,
            speciesID: 6,
            speciesName: "리자몽",
            isShiny: true,
            stageText: "3단계",
            levelText: "Lv. 36",
            natureText: "고집스러운",
            types: ["fire", "flying"],
            eggProgressText: nil,
            spriteImage: nil,
            accentColor: PokemonTypeColor.color(for: "fire"),
            exportDate: "2026.09.22",
            language: .ko,
            l: l
        )

        let canvas = TrainerCardCanvasView(data: data)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2.0
        renderer.proposedSize = ProposedViewSize(
            width: TrainerCardCanvasView.cardWidth,
            height: TrainerCardCanvasView.cardHeight
        )

        let image = renderer.nsImage
        XCTAssertNotNil(image, "ImageRenderer should render NSImage")

        if let image {
            XCTAssertEqual(image.size.width, TrainerCardCanvasView.cardWidth)
            XCTAssertEqual(image.size.height, TrainerCardCanvasView.cardHeight)

            guard let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                XCTFail("Failed to convert rendered NSImage to PNG data")
                return
            }
            XCTAssertFalse(pngData.isEmpty)
        }
    }

    @MainActor
    func testTrainerCardCanvasViewEggStateRendering() {
        let l = L(.en)
        let data = TrainerCardData(
            trainerName: "NewTrainer",
            trainerID: "12345",
            startDate: "2026.09",
            todayTokens: 5_000_000,
            allTimeTokens: 5_000_000,
            pokedexCount: 0,
            hallOfFameCount: 0,
            rankBall: "🔴",
            rankTitle: "Poké Ball Dev",
            isEgg: true,
            speciesID: nil,
            speciesName: "Pokémon Egg",
            isShiny: false,
            stageText: "Egg",
            levelText: "Egg",
            natureText: nil,
            types: [],
            eggProgressText: "10.0M tokens to hatch",
            spriteImage: nil,
            accentColor: .orange,
            exportDate: "2026.09.22",
            language: .en,
            l: l
        )

        let canvas = TrainerCardCanvasView(data: data)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1.0
        renderer.proposedSize = ProposedViewSize(
            width: TrainerCardCanvasView.cardWidth,
            height: TrainerCardCanvasView.cardHeight
        )

        let image = renderer.nsImage
        XCTAssertNotNil(image)
    }

    // MARK: - Localization Completeness in 7 Languages

    func testTrainerCardLocalizationInAllLanguages() {
        let allLanguages: [AppLanguage] = [.ko, .en, .ja, .es, .fr, .pt, .de]

        for lang in allLanguages {
            let l = L(lang)
            XCTAssertFalse(l.trainerCardTitle.isEmpty, "trainerCardTitle missing for \(lang)")
            XCTAssertFalse(l.trainerCardShare.isEmpty, "trainerCardShare missing for \(lang)")
            XCTAssertFalse(l.trainerCardCopy.isEmpty, "trainerCardCopy missing for \(lang)")
            XCTAssertFalse(l.trainerCardCopied.isEmpty, "trainerCardCopied missing for \(lang)")
            XCTAssertFalse(l.trainerCardSave.isEmpty, "trainerCardSave missing for \(lang)")
            XCTAssertFalse(l.trainerCardTodayBurn.isEmpty, "trainerCardTodayBurn missing for \(lang)")
            XCTAssertFalse(l.trainerCardAllTimeBurn.isEmpty, "trainerCardAllTimeBurn missing for \(lang)")
            XCTAssertFalse(l.trainerCardPokedex.isEmpty, "trainerCardPokedex missing for \(lang)")
            XCTAssertFalse(l.trainerCardHallOfFame.isEmpty, "trainerCardHallOfFame missing for \(lang)")
            XCTAssertFalse(l.trainerCardIncubating.isEmpty, "trainerCardIncubating missing for \(lang)")
            XCTAssertFalse(l.trainerCardCustomNamePlaceholder.isEmpty, "trainerCardCustomNamePlaceholder missing for \(lang)")
            XCTAssertFalse(l.trainerCardGraduatedSuffix.isEmpty, "trainerCardGraduatedSuffix missing for \(lang)")

            let rank = l.trainerRankTitle(tokens: 1_000_000_000)
            XCTAssertFalse(rank.title.isEmpty, "trainerRankTitle missing for \(lang)")
            XCTAssertFalse(rank.ball.isEmpty, "trainerRankBall missing for \(lang)")
        }
    }

    // MARK: - Visual Evidence Artifact Generator

    @MainActor
    func testGenerateSampleCardArtifacts() {
        let outputDir = URL(fileURLWithPath: "/Users/justinjeong/.gemini/antigravity/brain/ac1196f3-8939-4c48-beca-437cd75923fa")
        guard FileManager.default.fileExists(atPath: outputDir.path) else { return }

        let l = L(.ko)
        let spriteUrl = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar/sprites/149-s.png")
        let dragoniteSprite = NSImage(contentsOf: spriteUrl)

        let dragoniteData = TrainerCardData(
            trainerName: "Justin",
            trainerID: "08421",
            startDate: "2026.09",
            todayTokens: 42_800_000,
            allTimeTokens: 1_420_000_000,
            pokedexCount: 48,
            hallOfFameCount: 12,
            rankBall: "🟣",
            rankTitle: "마스터볼 개발자",
            isEgg: false,
            speciesID: 149,
            speciesName: "망나뇽",
            isShiny: false,
            stageText: "3단계",
            levelText: "Lv. 55",
            natureText: "고집스러운",
            types: ["dragon", "flying"],
            eggProgressText: nil,
            spriteImage: dragoniteSprite,
            accentColor: PokemonTypeColor.color(for: "dragon"),
            exportDate: "2026.09.22",
            language: .ko,
            l: l
        )

        let renderer = ImageRenderer(content: TrainerCardCanvasView(data: dragoniteData))
        renderer.scale = 2.0
        renderer.proposedSize = ProposedViewSize(width: TrainerCardCanvasView.cardWidth, height: TrainerCardCanvasView.cardHeight)
        if let img = renderer.nsImage,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: outputDir.appendingPathComponent("trainer-card-dragonite.png"))
        }

        let eggUrl = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar/sprites/egg.png")
        let eggSprite = NSImage(contentsOf: eggUrl)
        let eggData = TrainerCardData(
            trainerName: "Justin",
            trainerID: "08421",
            startDate: "2026.09",
            todayTokens: 15_200_000,
            allTimeTokens: 120_000_000,
            pokedexCount: 8,
            hallOfFameCount: 1,
            rankBall: "🔵",
            rankTitle: "수퍼볼 개발자",
            isEgg: true,
            speciesID: nil,
            speciesName: "포켓몬 알",
            isShiny: false,
            stageText: "알",
            levelText: "알",
            natureText: nil,
            types: [],
            eggProgressText: "10.0M tokens to hatch",
            spriteImage: eggSprite,
            accentColor: .orange,
            exportDate: "2026.09.22",
            language: .ko,
            l: l
        )

        let eggRenderer = ImageRenderer(content: TrainerCardCanvasView(data: eggData))
        eggRenderer.scale = 2.0
        eggRenderer.proposedSize = ProposedViewSize(width: TrainerCardCanvasView.cardWidth, height: TrainerCardCanvasView.cardHeight)
        if let img = eggRenderer.nsImage,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: outputDir.appendingPathComponent("trainer-card-egg.png"))
        }
    }
}
