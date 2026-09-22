import Foundation
import XCTest
@testable import PokeTokenBar

@MainActor
final class PokemonAudioPlayerTests: XCTestCase {
    func testPlayerHonorsEnabledState() {
        let player = PokemonAudioPlayer(canPlayHardwareAudio: false)
        player.isEnabled = false

        player.play(.tap)
        XCTAssertNil(player.lastPlayedEffect, "Disabled player must not trigger playback")

        player.play(.evolve)
        XCTAssertNil(player.lastPlayedEffect, "Disabled player must not trigger playback")

        player.isEnabled = true
        player.play(.tap)
        XCTAssertEqual(player.lastPlayedEffect, .tap)

        player.play(.evolve)
        XCTAssertEqual(player.lastPlayedEffect, .evolve)
    }

    func testVolumeClampingAndZeroSuppression() {
        let player = PokemonAudioPlayer(canPlayHardwareAudio: false)

        player.volume = 1.5
        XCTAssertEqual(player.volume, 1.0, "Volume must clamp to 1.0")

        player.volume = -0.5
        XCTAssertEqual(player.volume, 0.0, "Volume must clamp to 0.0")

        // When volume is 0, play should not trigger
        player.play(.levelUp)
        XCTAssertNil(player.lastPlayedEffect, "Muted player should suppress playback")

        player.volume = 0.5
        player.play(.levelUp)
        XCTAssertEqual(player.lastPlayedEffect, .levelUp)
    }

    func testAllSoundEffectsCanBePlayed() {
        let player = PokemonAudioPlayer(canPlayHardwareAudio: false)

        for effect in PokemonSoundEffect.allCases {
            player.play(effect)
            XCTAssertEqual(player.lastPlayedEffect, effect)
        }
    }

    func testSoundSynthesizerGeneratesValidBuffers() {
        let synth = SoundSynthesizer.shared
        for effect in PokemonSoundEffect.allCases {
            let buffer = synth.makeBuffer(for: effect)
            XCTAssertGreaterThan(buffer.frameLength, 0, "Buffer for \(effect) must have non-zero frames")
            XCTAssertEqual(buffer.format.sampleRate, 44100.0)
            XCTAssertEqual(buffer.format.channelCount, 1)

            // Duration bounds verification (all SFX should be <= 1.5s for snappy UI feel)
            let duration = Double(buffer.frameLength) / buffer.format.sampleRate
            XCTAssertLessThanOrEqual(duration, 1.5, "Effect \(effect) duration \(duration)s exceeds 1.5s limit")
            XCTAssertGreaterThanOrEqual(duration, 0.05, "Effect \(effect) duration \(duration)s is too short")
        }
    }

    func testStopExecution() {
        let player = PokemonAudioPlayer(canPlayHardwareAudio: false)
        player.play(.hatch)
        XCTAssertEqual(player.lastPlayedEffect, .hatch)

        // Stopping should be safe and idempotent
        player.stop()
        player.stop()
    }
}
