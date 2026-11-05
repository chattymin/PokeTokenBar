import XCTest
import SwiftUI
@testable import PokeTokenBar

/// Renders the new per-generation Pokédex header (region progress chips + completion medals) from the
/// *production* `RegionTally` / `DexBadgeMedal` views with sample completion data — so PR/landing images
/// stay in sync with the real UI. Skipped unless `PTB_SCREENSHOT_DIR` is set (release/PR-asset only).
///
///     PTB_SCREENSHOT_DIR=/tmp/ptb-shots swift test --filter GenerationDexScreenshotTests
final class GenerationDexScreenshotTests: XCTestCase {

    /// Sample mid-to-late game: Kanto/Hoenn done, Johto done shiny, Sinnoh in progress (selected), Unova started.
    private func sampleCompletions() -> [DexCompletion] {
        [
            DexCompletion(region: .kanto, owned: 151, shinyOwned: 0),
            DexCompletion(region: .johto, owned: 100, shinyOwned: 100),
            DexCompletion(region: .hoenn, owned: 135, shinyOwned: 0),
            DexCompletion(region: .sinnoh, owned: 62, shinyOwned: 4),
            DexCompletion(region: .unova, owned: 9, shinyOwned: 0),
        ]
    }

    @MainActor
    func testGenerateGenerationDexScreenshots() throws {
        guard let directory = ProcessInfo.processInfo.environment["PTB_SCREENSHOT_DIR"] else {
            throw XCTSkip("PTB_SCREENSHOT_DIR 미지정 — 에셋 생성은 릴리스/PR 때만 실행한다")
        }
        for (language, scheme, generation, suffix) in [
            (AppLanguage.en, ColorScheme.dark, false, "-before"),
            (.en, .dark, true, ""),
            (.en, .light, true, "-light"),
            (.ko, .dark, true, "-ko"),
            (.ja, .dark, true, "-ja"),
        ] {
            let data = try render(language: language, scheme: scheme, showGeneration: generation)
            let url = URL(fileURLWithPath: directory)
                .appendingPathComponent("screenshot-generation-dex\(suffix).png")
            try data.write(to: url)
            print("wrote \(url.path) (\(data.count) bytes)")
        }
    }

    @MainActor
    private func render(language: AppLanguage, scheme: ColorScheme, showGeneration: Bool) throws -> Data {
        let l = L(language)
        let completions = sampleCompletions()
        let selected = PokedexRegion.sinnoh
        // Earned non-regional medals the header strip collects (National not complete here; Unown is).
        let medals: [(String, String)] = [("🔤", l.dexBadgeLabel(.unown))]

        let bg = scheme == .dark
            ? Color(red: 41 / 255, green: 41 / 255, blue: 42 / 255)
            : Color(red: 246 / 255, green: 246 / 255, blue: 247 / 255)

        let rarities: [(Rarity, Int)] = [(.common, 210), (.uncommon, 140), (.rare, 78), (.legendary, 29)]

        let content = VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(l.dexTitle).font(.callout.weight(.semibold))
                Text(l.dexSpeciesTotal(457)).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if showGeneration {
                    HStack(spacing: 3) {
                        ForEach(medals, id: \.0) { emoji, help in
                            DexBadgeMedal(emoji: emoji, help: help)
                        }
                    }
                }
            }
            // Region progress chips — the headline of this feature (new row).
            if showGeneration {
                HStack(spacing: 5) {
                    ForEach(completions) { c in
                        RegionTally(label: l.regionName(c.region), completion: c, isSelected: c.region == selected)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            // Existing rarity filter chips, kept in both states for a fair before/after.
            HStack(spacing: 4) {
                ForEach(rarities, id: \.0) { r, count in
                    RarityTally(label: l.rarityLabel(r), count: count, color: rarityColor(r))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            if showGeneration {
                Text(l.dexRegionProgressLabel(selected, owned: 62, total: 107))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, PopoverMetrics.padding)
        .padding(.vertical, 16)
        .frame(width: 560, alignment: .leading)
        .background(bg)
        .environment(\.colorScheme, scheme)
        .environment(\.locale, language.displayLocale)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
