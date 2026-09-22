import AppKit
import AVFoundation
import SwiftUI

enum SoundEffectType: String, CaseIterable, Identifiable {
    case hatch = "알 부화 & 포획 팡파레"
    case evolve = "진화 완료 팡파레"
    case buy = "포켓몬 센터 치료 멜로디"
    case levelUp = "레벨업 팡파레"
    case shiny = "이로치 반짝임"
    case tap = "동반자 터치 (A버튼)"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .hatch: return "oval.portrait.fill"
        case .evolve: return "star.circle.fill"
        case .buy: return "cross.case.fill"
        case .levelUp: return "arrow.up.circle.fill"
        case .shiny: return "sparkles"
        case .tap: return "hand.tap.fill"
        }
    }

    var originBadge: String {
        switch self {
        case .hatch: return "원작 100% 공식"
        case .evolve: return "원작 100% 공식"
        case .buy: return "원작 100% 공식"
        case .levelUp: return "원작 100% 공식"
        case .shiny: return "2세대 원작 공식"
        case .tap: return "본가 메뉴 선택음"
        }
    }

    var description: String {
        switch self {
        case .hatch: return "알 부화 / 도감 신규 포켓몬 등록 시 나오는 'Gotcha! Pokémon was caught!' 시그니처 팡파레 (1.4초)"
        case .evolve: return "포켓몬 진화가 완료되었을 때 승리와 성취감을 주는 전통 5음 진화 팡파레 (1.2초)"
        case .buy: return "전 세계 포켓몬 팬 누구나 아는 간호순 포켓몬 센터 치료 완료음 '따-따-따-따-단!' (1.05초)"
        case .levelUp: return "본가 게임에서 레벨업할 때 나오는 경쾌한 레벨업 징글 (0.95초)"
        case .shiny: return "골드/실버부터 이로치(색이 다른 포켓몬) 조우 시 퍼지는 별빛 반짝임 챠임 (0.85초)"
        case .tap: return "메뉴바에서 포켓몬을 클릭할 때 나는 가볍고 부드러운 A버튼 픽 사운드 (0.08초)"
        }
    }
}

final class SoundSynthesizer {
    static let shared = SoundSynthesizer()
    private let sampleRate: Double = 44100.0

    func makeBuffer(for type: SoundEffectType) -> AVAudioPCMBuffer {
        switch type {
        case .tap:
            return synthesize(notes: [(587.33, 0.0, 0.08, 0.22)], totalDur: 0.08)

        case .buy:
            // 포켓몬 센터 치료음 ("따-따-따-따-단!")
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
            // 포켓몬 레벨업 팡파레
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
            // 포켓몬 겟 / 알 부화 ("Gotcha! Pokémon was caught!")
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

@MainActor
final class PreviewAudioEngine: ObservableObject {
    @Published var volume: Double = 0.8
    @Published var lastPlayed: SoundEffectType?
    @Published var statusMessage: String = "사운드를 클릭하여 들어보세요."

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var cachedBuffers: [SoundEffectType: AVAudioPCMBuffer] = [:]

    init() {
        let eng = AVAudioEngine()
        let node = AVAudioPlayerNode()
        eng.attach(node)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)!
        eng.connect(node, to: eng.mainMixerNode, format: format)
        try? eng.start()
        self.engine = eng
        self.playerNode = node

        for type in SoundEffectType.allCases {
            cachedBuffers[type] = SoundSynthesizer.shared.makeBuffer(for: type)
        }
    }

    func play(_ type: SoundEffectType) {
        guard let playerNode, let engine else { return }
        guard let buffer = cachedBuffers[type] else { return }

        if !engine.isRunning {
            try? engine.start()
        }

        playerNode.stop()
        playerNode.volume = Float(volume)
        lastPlayed = type
        statusMessage = "재생 중: \(type.rawValue)"

        playerNode.scheduleBuffer(buffer, at: nil) { [weak self] in
            Task { @MainActor in
                self?.statusMessage = "재생 완료: \(type.rawValue)"
            }
        }
        playerNode.play()
    }
}

struct PreviewView: View {
    @StateObject private var audio = PreviewAudioEngine()
    @State private var sampleSprite: NSImage?

    var body: some View {
        VStack(spacing: 18) {
            // 상단 헤더
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text("🔴")
                    Text("원작 100% 공식 시그니처 포켓몬 팡파레 미리듣기")
                        .font(.title3.weight(.bold))
                }
                Text("전 세계 포켓몬 팬 누구나 0.5초 만에 알아듣는 본작의 시그니처 멜로디를 부드러운 감성 톤으로 재현했습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)

            // 볼륨 슬라이더
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $audio.volume, in: 0...1, step: 0.05)
                    .frame(width: 220)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                Text("\(Int(audio.volume * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // 효과음 카드 그리드
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(SoundEffectType.allCases) { effect in
                    Button {
                        audio.play(effect)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(audio.lastPlayed == effect ? Color.red : Color.secondary.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: effect.icon)
                                    .font(.title3)
                                    .foregroundStyle(audio.lastPlayed == effect ? .white : .primary)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(effect.rawValue)
                                        .font(.system(size: 13, weight: .bold))
                                    Spacer()
                                    Text(effect.originBadge)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.15))
                                        .foregroundStyle(.red)
                                        .clipShape(Capsule())
                                }
                                Text(effect.description)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(audio.lastPlayed == effect ? Color.red.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(audio.lastPlayed == effect ? Color.red : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Divider().padding(.horizontal, 20)

            // 하단 인터랙션 테스트 (동반자 터치 연동)
            HStack(spacing: 16) {
                if let img = sampleSprite {
                    Image(nsImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 54, height: 54)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("동반자 인터랙션 테스트")
                        .font(.system(size: 12, weight: .semibold))
                    Text("메뉴바에서 포켓몬을 클릭했을 때 부드러운 A버튼 픽 소리가 납니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("클릭하여 터치음 재생") {
                    audio.play(.tap)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 20)

            // 상태 표시줄
            Text(audio.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
        .frame(width: 580, height: 510)
        .onAppear {
            loadSampleSprite()
        }
    }

    private func loadSampleSprite() {
        Task {
            let url = URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/25.png")!
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let img = NSImage(data: data) {
                await MainActor.run {
                    self.sampleSprite = img
                }
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 580, height: 510),
    styleMask: [.titled, .closable, .miniaturizable],
    backing: .buffered,
    defer: false
)
window.center()
window.title = "PokeTokenBar - 원작 공식 시그니처 팡파레 미리듣기"
window.contentView = NSHostingView(rootView: PreviewView())
window.makeKeyAndOrderFront(nil)

app.activate(ignoringOtherApps: true)
app.run()
