import AVFoundation
import Foundation
import Observation

/// 포켓몬 효과음 종류 (원작 공식 멜로디 기반 고음질 레트로 SFX)
public enum PokemonSoundEffect: String, CaseIterable, Sendable {
    case tap = "tap"
    case hatch = "hatch"
    case shiny = "shiny"
    case levelUp = "levelUp"
    case evolve = "evolve"
    case buy = "buy"
}

/// 사운드 플레이어 인터페이스 (테스트 및 목 주입용)
@MainActor
protocol PokemonAudioPlaying: AnyObject {
    var isEnabled: Bool { get set }
    var volume: Float { get set }
    func play(_ effect: PokemonSoundEffect)
}

/// 포켓몬 본가 공식 시그니처 팡파레와 징글을 재현하는 절차적 사운드 합성기.
/// 외부 저작권 음원 파일 없이, 44.1kHz PCM 버퍼를 메모리에서 실시간으로 정밀 합성하여 무지연(0ms) 재생.
final class SoundSynthesizer: @unchecked Sendable {
    static let shared = SoundSynthesizer()
    private let sampleRate: Double = 44100.0

    func makeBuffer(for effect: PokemonSoundEffect) -> AVAudioPCMBuffer {
        switch effect {
        case .tap:
            // 포켓몬 본가 A버튼 선택음 (0.08초 부드러운 팝)
            return synthesize(notes: [(587.33, 0.0, 0.08, 0.22)], totalDur: 0.08)

        case .buy:
            // 포켓몬 센터 치료 완료 멜로디 ("따-따-따-따-단!")
            // Lead: B5, B5, B5, G#5, E6
            let lead: [(Double, Double, Double, Double)] = [
                (987.77, 0.00, 0.11, 0.30),
                (987.77, 0.13, 0.11, 0.30),
                (987.77, 0.26, 0.11, 0.30),
                (830.61, 0.39, 0.13, 0.32),
                (1318.51, 0.53, 0.45, 0.35)
            ]
            let bass: [(Double, Double, Double, Double)] = [
                (329.63, 0.00, 0.11, 0.18),
                (329.63, 0.13, 0.11, 0.18),
                (329.63, 0.26, 0.11, 0.18),
                (415.30, 0.39, 0.13, 0.20),
                (659.25, 0.53, 0.45, 0.22)
            ]
            return synthesize(notes: lead + bass, totalDur: 1.05)

        case .levelUp:
            // 포켓몬 본가 레벨업 팡파레 (F5, C5, F5, C5, D#5, E5, F5)
            let notes: [(Double, Double, Double, Double)] = [
                (698.46, 0.00, 0.10, 0.28),
                (523.25, 0.11, 0.08, 0.26),
                (698.46, 0.20, 0.08, 0.26),
                (523.25, 0.29, 0.08, 0.26),
                (622.25, 0.38, 0.09, 0.28),
                (659.25, 0.48, 0.09, 0.28),
                (698.46, 0.58, 0.35, 0.34)
            ]
            return synthesize(notes: notes, totalDur: 0.95)

        case .hatch:
            // 포켓몬 겟 / 도감 등록 팡파레 ("Gotcha! Pokémon was caught!")
            // A5, F5, C5, A#5, G5, A5
            let lead: [(Double, Double, Double, Double)] = [
                (880.00, 0.00, 0.14, 0.28),
                (698.46, 0.14, 0.14, 0.26),
                (523.25, 0.28, 0.22, 0.26),
                (932.33, 0.52, 0.07, 0.28),
                (932.33, 0.60, 0.07, 0.28),
                (932.33, 0.68, 0.07, 0.28),
                (783.99, 0.76, 0.09, 0.28),
                (932.33, 0.86, 0.09, 0.30),
                (880.00, 0.96, 0.40, 0.34)
            ]
            let harmony: [(Double, Double, Double, Double)] = [
                (523.25, 0.00, 0.14, 0.18),
                (440.00, 0.14, 0.14, 0.16),
                (349.23, 0.28, 0.22, 0.16),
                (622.25, 0.52, 0.07, 0.18),
                (622.25, 0.60, 0.07, 0.18),
                (622.25, 0.68, 0.07, 0.18),
                (523.25, 0.76, 0.09, 0.18),
                (622.25, 0.86, 0.09, 0.20),
                (698.46, 0.96, 0.40, 0.22)
            ]
            return synthesize(notes: lead + harmony, totalDur: 1.40)

        case .evolve:
            // 포켓몬 진화 완료 승리 팡파레
            // E5 -> B5 -> A5 -> D#6 -> E6
            let lead: [(Double, Double, Double, Double)] = [
                (659.25, 0.00, 0.12, 0.28),
                (987.77, 0.13, 0.12, 0.30),
                (880.00, 0.26, 0.14, 0.30),
                (1244.51, 0.41, 0.15, 0.32),
                (1318.51, 0.57, 0.55, 0.36)
            ]
            let harmony: [(Double, Double, Double, Double)] = [
                (329.63, 0.00, 0.12, 0.20),
                (493.88, 0.13, 0.12, 0.22),
                (440.00, 0.26, 0.14, 0.22),
                (622.25, 0.41, 0.15, 0.24),
                (659.25, 0.57, 0.55, 0.26)
            ]
            return synthesize(notes: lead + harmony, totalDur: 1.20)

        case .shiny:
            // 이로치(색이 다른 포켓몬) 조우 시의 별빛 반짝임 챠임
            let notes: [(Double, Double, Double, Double)] = [
                (1046.50, 0.0, 0.15, 0.20),
                (1318.51, 0.06, 0.15, 0.22),
                (1567.98, 0.12, 0.18, 0.25),
                (2093.00, 0.18, 0.45, 0.28),
                (2637.02, 0.24, 0.55, 0.22)
            ]
            return synthesize(notes: notes, totalDur: 0.85)
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
                    // 포켓몬 레트로 느낌의 따뜻한 펄스 + 배음
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
final class PokemonAudioPlayer: PokemonAudioPlaying {
    static let shared = PokemonAudioPlayer()

    var isEnabled: Bool = true

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
            try? engine.start()
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
        if engine?.isRunning == true {
            engine?.pause()
        }
    }
}
