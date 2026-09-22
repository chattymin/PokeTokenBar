import Foundation
import XCTest
@testable import PokeTokenBar

@MainActor
final class UsageStoreSoundSettingsTests: XCTestCase {
    func testSoundSettingsDefaults() {
        let suiteName = "sound-settings-defaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(autoRefresh: false, defaults: defaults)

        XCTAssertTrue(store.soundEffectsEnabled, "Sound effects should be enabled by default")
        XCTAssertEqual(store.soundVolume, 0.8, accuracy: 0.001, "Default volume should be 0.8")
        XCTAssertTrue(PokemonAudioPlayer.shared.isEnabled)
        XCTAssertEqual(PokemonAudioPlayer.shared.volume, 0.8, accuracy: 0.001)
    }

    func testSoundSettingsPersistenceAndPropagation() {
        let suiteName = "sound-settings-persistence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(autoRefresh: false, defaults: defaults)

        store.soundEffectsEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "soundEffectsEnabled"))
        XCTAssertFalse(PokemonAudioPlayer.shared.isEnabled)

        store.soundVolume = 0.45
        XCTAssertEqual(defaults.double(forKey: "soundVolume"), 0.45, accuracy: 0.001)
        XCTAssertEqual(PokemonAudioPlayer.shared.volume, 0.45, accuracy: 0.001)

        // Create a new store instance with the same defaults to verify restoration
        let restoredStore = UsageStore(autoRefresh: false, defaults: defaults)
        XCTAssertFalse(restoredStore.soundEffectsEnabled)
        XCTAssertEqual(restoredStore.soundVolume, 0.45, accuracy: 0.001)
    }
}
