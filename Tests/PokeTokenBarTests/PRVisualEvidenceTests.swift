import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class PRVisualEvidenceTests: XCTestCase {
    func testGenerateStreakBadgeEvidence() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_PR_STREAK_SCREENSHOT"] else {
            throw XCTSkip("PTB_PR_STREAK_SCREENSHOT is not set")
        }
        let suite = "PRStreakEvidence-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }

        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        state.streak = StreakState(days: 7, lastDay: LocalUsageReader.todayKey())
        state.streakFeatureSeeded = true
        state.active = MonState(baseID: 1, pathIDs: [1, 2, 3], stageIndex: 0,
                                usedAtStage: 42_000_000, rarity: .common, totalForms: 3)
        try JSONEncoder().encode(state).write(to: stateURL)

        let provider = StreakEvidenceProvider()
        let store = CompanionStore(provider: provider, fileURL: stateURL, defaults: defaults)
        store.update(todayTokensByProvider: [:], todayDate: LocalUsageReader.todayKey(),
                     monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: false)
        try await Task.sleep(for: .milliseconds(100))
        let content = CompanionHeader(store: store)
            .padding(16)
            .frame(width: PopoverMetrics.width, alignment: .leading)
            .background(Color(red: 41 / 255, green: 41 / 255, blue: 42 / 255))
            .environment(\.colorScheme, .dark)

        let host = NSHostingController(rootView: content)
        host.view.setFrameSize(NSSize(width: PopoverMetrics.width, height: host.view.fittingSize.height))
        let window = NSWindow(contentRect: host.view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host.view
        host.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let bounds = host.view.bounds
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width) * 2,
            pixelsHigh: Int(bounds.height) * 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = bounds.size
        host.view.cacheDisplay(in: bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: output))
    }
}

private struct StreakEvidenceProvider: PokeProviding {
    func line(baseSpeciesID _: Int) async throws -> EvoLine {
        EvoLine(baseID: 1,
                tree: EvoNode(speciesID: 1, children: [
                    EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])
                ]),
                rarity: .common,
                names: [1: ["en": "Bulbasaur"], 2: ["en": "Ivysaur"], 3: ["en": "Venusaur"]])
    }

    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 1, captureRate: 45)] }
}
