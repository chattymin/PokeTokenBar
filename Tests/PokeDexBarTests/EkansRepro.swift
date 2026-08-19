import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// 제보 재현 — **이로치 레벨 1 아보(23)** 의 상세 화면.
@MainActor
final class EkansReproTests: XCTestCase {
    func testOpeningTheReportedIndividualDoesNotCrash() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = PlayerStore(fileURL: FileManager.default.temporaryDirectory
                                    .appendingPathComponent("ekans-\(UUID().uuidString).json"),
                                rng: SeededRNG(seed: 1), now: { now },
                                defaults: UserDefaults(suiteName: UUID().uuidString)!)
        // 제보 그대로: species=23 shiny=true level=1 grade=common line=loaded
        let ekans = Individual(baseID: 23, speciesID: 23, pathIDs: [23], shiny: true,
                               nature: .hardy, exp: 0, obtainedAt: now,
                               grade: .common, growthRate: .mediumFast)
        store.mutate { $0.box.append(ekans) }

        let line = EvoLine(baseID: 23,
                           tree: EvoNode(speciesID: 23,
                                         children: [EvoNode(speciesID: 24, children: [],
                                                            requirementRaw: .level(22))]),
                           rarity: .common,
                           names: [23: ["ko": "아보", "en": "Ekans"],
                                   24: ["ko": "아보크", "en": "Arbok"]])

        let host = NSHostingView(rootView: IndividualDetailView(
            store: store, individual: ekans, line: line, onNeedLine: { _ in }, onBack: {})
            .frame(width: PopoverMetrics.width))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }
}
