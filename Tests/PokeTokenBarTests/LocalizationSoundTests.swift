import Foundation
import XCTest
@testable import PokeTokenBar

final class LocalizationSoundTests: XCTestCase {
    func testAllLanguagesHaveNonEmptySoundStrings() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertFalse(
                l.soundSection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "soundSection must not be empty for \(lang)"
            )
            XCTAssertFalse(
                l.soundEffectsLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "soundEffectsLabel must not be empty for \(lang)"
            )
            XCTAssertFalse(
                l.soundVolumeLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "soundVolumeLabel must not be empty for \(lang)"
            )
            XCTAssertFalse(
                l.soundTestLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "soundTestLabel must not be empty for \(lang)"
            )
        }
    }
}
