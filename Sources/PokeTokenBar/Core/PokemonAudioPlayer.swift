import AVFoundation
import Foundation
import Observation

/// Companion interactions that can emit a short synthesized interface cue.
public enum PokemonSoundEffect: String, CaseIterable, Sendable {
    case tap = "tap"
    case hatch = "hatch"
    case shiny = "shiny"
    case levelUp = "levelUp"
    case evolve = "evolve"
    case buy = "buy"
}

/// Generates original, non-referential retro interface cues in memory.
/// No audio files or third-party melodies are bundled with the app.
final class SoundSynthesizer: @unchecked Sendable {
    static let shared = SoundSynthesizer()
    private let sampleRate: Double = 44100.0

    func makeBuffer(for effect: PokemonSoundEffect) -> AVAudioPCMBuffer {
        switch effect {
        case .tap:
            return synthesize(notes: [
                (659.25, 0.00, 0.04, 0.18),
                (987.77, 0.03, 0.05, 0.14)
            ], totalDur: 0.09)

        case .buy:
            return synthesize(notes: [
                (392.00, 0.00, 0.08, 0.20),
                (523.25, 0.09, 0.08, 0.22),
                (783.99, 0.18, 0.20, 0.24),
                (196.00, 0.00, 0.36, 0.10)
            ], totalDur: 0.42)

        case .levelUp:
            return synthesize(notes: [
                (440.00, 0.00, 0.08, 0.20),
                (554.37, 0.07, 0.08, 0.22),
                (739.99, 0.14, 0.10, 0.24),
                (1108.73, 0.23, 0.24, 0.20)
            ], totalDur: 0.50)

        case .hatch:
            return synthesize(notes: [
                (329.63, 0.00, 0.12, 0.18),
                (493.88, 0.10, 0.12, 0.20),
                (659.25, 0.20, 0.12, 0.22),
                (987.77, 0.30, 0.28, 0.24),
                (246.94, 0.00, 0.52, 0.09)
            ], totalDur: 0.62)

        case .evolve:
            return synthesize(notes: [
                (293.66, 0.00, 0.14, 0.18),
                (440.00, 0.10, 0.14, 0.20),
                (659.25, 0.20, 0.14, 0.22),
                (880.00, 0.30, 0.14, 0.24),
                (1174.66, 0.40, 0.34, 0.22),
                (146.83, 0.00, 0.68, 0.08)
            ], totalDur: 0.78)

        case .shiny:
            return synthesize(notes: [
                (1046.50, 0.00, 0.08, 0.14),
                (1661.22, 0.04, 0.10, 0.16),
                (2349.32, 0.09, 0.16, 0.18),
                (1318.51, 0.14, 0.20, 0.10)
            ], totalDur: 0.38)
        }
    }

    private func synthesize(notes: [(Double, Double, Double, Double)], totalDur: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * totalDur)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            var sample = 0.0
            for (freq, start, dur, gain) in notes {
                if t >= start && t < start + dur {
                    let noteT = t - start
                    let envelope = min(1.0, noteT * 200.0) * exp(-noteT * 5.0)
                    // A compact pulse with two harmonics keeps the cue audible at low volume.
                    let wave = sin(2.0 * .pi * freq * noteT)
                             + 0.28 * sin(2.0 * .pi * (freq * 2.0) * noteT)
                             + 0.10 * sin(2.0 * .pi * (freq * 3.0) * noteT)
                    sample += wave * envelope * gain
                }
            }
            data[i] = Float(max(-1.0, min(1.0, sample)))
        }
        return buffer
    }
}

/// 포켓몬 사운드 효과음 플레이어.
@MainActor
@Observable
final class PokemonAudioPlayer {
    static let shared = PokemonAudioPlayer()

    var isEnabled: Bool = true {
        didSet {
            if !isEnabled { stop() }
        }
    }

    @ObservationIgnored
    private var _rawVolume: Float = 0.8

    var volume: Float {
        get {
            access(keyPath: \.volume)
            return _rawVolume
        }
        set {
            withMutation(keyPath: \.volume) {
                let clamped = max(0.0, min(1.0, newValue))
                _rawVolume = clamped
                playerNode?.volume = clamped
            }
        }
    }

    let canPlayHardwareAudio: Bool
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var cachedBuffers: [PokemonSoundEffect: AVAudioPCMBuffer] = [:]
    @ObservationIgnored private var idleStopTask: Task<Void, Never>?

    /// 테스트 및 UI 상태 검증용 최근 재생 정보
    private(set) var lastPlayedEffect: PokemonSoundEffect?

    init(canPlayHardwareAudio: Bool = true) {
        self.canPlayHardwareAudio = canPlayHardwareAudio
        if canPlayHardwareAudio {
            let eng = AVAudioEngine()
            let node = AVAudioPlayerNode()
            eng.attach(node)
            let format = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)!
            eng.connect(node, to: eng.mainMixerNode, format: format)
            // 상시 I/O 스레드 회전 및 AirPods 배터리 드레인 방지를 위해 시작 시점에는 가동하지 않고
            // 실제 효과음 재생 요청 시점(play)에 지연 기동(lazy start)한다.
            self.engine = eng
            self.playerNode = node

            for effect in PokemonSoundEffect.allCases {
                cachedBuffers[effect] = SoundSynthesizer.shared.makeBuffer(for: effect)
            }

            NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: eng,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleConfigurationChange()
                }
            }
        }
    }

    deinit {
        idleStopTask?.cancel()
    }

    /// 오디오 출력 라우트(AirPods, 외장 디스플레이 등) 변경 시 노드 연결 그래프를 복구한다.
    private func handleConfigurationChange() {
        guard canPlayHardwareAudio, let engine, let playerNode else { return }
        if engine.isRunning {
            engine.stop()
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)!
        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    /// 지정된 효과음을 재생한다.
    func play(_ effect: PokemonSoundEffect) {
        guard isEnabled, volume > 0 else { return }
        lastPlayedEffect = effect
        guard canPlayHardwareAudio else { return }

        guard let playerNode, let engine, let buffer = cachedBuffers[effect] else { return }

        idleStopTask?.cancel()

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                AppLog.write("audio engine start failed: \(error)")
                return
            }
        }

        playerNode.stop()
        playerNode.volume = volume
        playerNode.scheduleBuffer(buffer, at: nil)
        playerNode.play()

        // 버퍼 재생 완료 후 2초간 추가 재생이 없으면 엔진을 pause하여 CoreAudio I/O 스레드를 절전 상태로 전환한다.
        // 블루투스/AirPods가 연결되어 있어도 스트림이 꺼져 배터리가 불필요하게 소모되지 않는다.
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        idleStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((duration + 2.0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if self?.playerNode?.isPlaying == false {
                self?.engine?.pause()
            }
        }
    }

    /// 현재 재생 중인 효과음을 중지하고 오디오 엔진을 즉시 절전(pause)한다.
    func stop() {
        idleStopTask?.cancel()
        playerNode?.stop()
        lastPlayedEffect = nil
        if engine?.isRunning == true {
            engine?.pause()
        }
    }
}
