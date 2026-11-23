import AppKit

// 연출 효과음 — 도트 그림체에 맞춘 칩튠 소리를 코드로 합성한다(포켓몬 원본 소리는 저작권 때문에 쓰지 않고,
// 소리 파일도 저장소에 넣지 않는다).
//
// 구조: 연출마다 "언제 무슨 소리"의 순수한 큐 표(`cues`)를 만들고, 연출 전체 길이의 소리 한 덩어리로 미리
// 합성해(`render`) 재생을 한 번만 건다. 타이머로 소리마다 따로 울리면 메인 스레드가 바쁠 때 박자가 어긋난다 —
// 한 덩어리면 그림과 같은 시각표를 샘플 단위로 지킨다. 큐 표와 합성은 순수 함수라 테스트가 검사한다.

enum CelebrationSound {
    enum Sound: Equatable {
        /// 알이 흔들릴 때의 "톡".
        case tap
        /// 금이 갈 때의 "빠직".
        case crack
        /// 껍질이 터지는 "팝".
        case pop
        /// 공개 화음 — 음 개수가 등급 신호다(커먼 2 … 전설 5 + 긴 여운).
        case chime(notes: Int)
        /// 진화 실루엣이 바뀔 때의 짧은 음 — 바뀔수록 높아진다.
        case blip(step: Int)
        /// 진화 공개 팡파르.
        case fanfare
        /// 몬스터볼이 날아오는 바람 소리.
        case whoosh
        /// 붉은 빛으로 빨려 드는 소리(올라가는 음).
        case zap
        /// 볼이 닫히는·포획이 확정되는 "딸깍".
        case click
        /// 볼이 바닥에 떨어지는 소리.
        case thud
        /// 볼이 흔들릴 때의 "똑".
        case tick
        /// 포획 확정 뒤의 반짝 소리.
        case twinkle
        /// 메타몽 정체가 드러나는 "뾰잉".
        case boing
    }

    struct Cue: Equatable {
        let at: TimeInterval
        let sound: Sound
    }

    static let sampleRate = 44_100.0
    /// 전체 음량 — 메뉴바 앱이 갑자기 크게 울리지 않게 낮게.
    static let masterVolume: Float = 0.22

    // MARK: 큐 표(순수)

    static func cues(for kind: CelebrationPlayer.Kind, reduceMotion: Bool) -> [Cue] {
        var out: [Cue] = []
        switch kind {
        case .hatch(let p, _, _):
            let reveal = HatchEffect.revealTime(p, reduceMotion: reduceMotion)
            if !reduceMotion {
                out += HatchEffect.wobbleStarts(p).map { Cue(at: $0 + HatchEffect.wobbleLength * 0.2, sound: .tap) }
                out += HatchEffect.crackTimes(p).map { Cue(at: $0, sound: .crack) }
            }
            out.append(Cue(at: reveal, sound: .pop))
            out.append(Cue(at: reveal + 0.05, sound: .chime(notes: 2 + p.rarity.sortRank)))
        case .evolve:
            let reveal = EvolutionEffect.revealTime(reduceMotion: reduceMotion)
            if !reduceMotion {
                for (k, t) in evolutionSwaps().enumerated() { out.append(Cue(at: t, sound: .blip(step: k))) }
            }
            out.append(Cue(at: reveal, sound: .fanfare))
        case .graduate:
            if reduceMotion {
                out.append(Cue(at: 0.8, sound: .click))
            } else {
                out.append(Cue(at: 0, sound: .whoosh))
                out.append(Cue(at: 0.3, sound: .pop))
                out.append(Cue(at: 0.72, sound: .zap))
                out.append(Cue(at: 1.22, sound: .click))
                out.append(Cue(at: 1.48, sound: .thud))
                out += GraduationEffect.wobbleStarts.map { Cue(at: $0 + 0.04, sound: .tick) }
                out.append(Cue(at: GraduationEffect.clickAt, sound: .click))
                out.append(Cue(at: GraduationEffect.clickAt + 0.08, sound: .twinkle))
            }
        case .dittoReveal:
            out.append(Cue(at: DittoRevealEffect.revealAt, sound: .boing))
        }
        return out.sorted { $0.at < $1.at }
    }

    /// 진화 실루엣이 옛↔새로 바뀌는 순간들(mix 가 0.5 를 지나는 시각) — 그림이 "탁" 바뀌는 때에 소리를 맞춘다.
    static func evolutionSwaps() -> [TimeInterval] {
        var out: [TimeInterval] = []
        var previous = EvolutionEffect.frame(at: EvolutionEffect.whitenEnd).mix
        for t in stride(from: EvolutionEffect.whitenEnd, through: EvolutionEffect.alternateEnd, by: 0.005) {
            let m = EvolutionEffect.frame(at: t).mix
            if (previous - 0.5) * (m - 0.5) < 0 { out.append(t) }
            previous = m
        }
        return out
    }

    // MARK: 합성(순수)

    /// 큐 표 전체를 `length` 초짜리 소리 한 덩어리로(-1…1).
    static func render(_ cues: [Cue], length: TimeInterval) -> [Float] {
        let count = Int(length * sampleRate)
        var mix = [Float](repeating: 0, count: max(0, count))
        for cue in cues {
            let start = Int(cue.at * sampleRate)
            for (k, v) in samples(cue.sound).enumerated() where start + k < count && start + k >= 0 {
                mix[start + k] += v
            }
        }
        return mix.map { max(-1, min(1, $0 * masterVolume)) }
    }

    /// 펜타토닉 음계(C 장조) — n 번째 음의 주파수.
    static func note(_ n: Int) -> Double {
        let steps = [0, 2, 4, 7, 9]
        let semis = 12 * (n / steps.count) + steps[n % steps.count]
        return 1046.5 * pow(2, Double(semis) / 12)   // C6 부터
    }

    static func samples(_ sound: Sound) -> [Float] {
        switch sound {
        case .tap:
            return tone(0.05, from: 260, to: 170, wave: .triangle, decay: 40)
        case .crack:
            return add(noise(0.04, seed: 3, decay: 70, highpass: true), tone(0.018, from: 1900, to: 1500, wave: .square(0.25), decay: 90, gain: 0.5))
        case .pop:
            return tone(0.07, from: 380, to: 1250, wave: .square(0.5), decay: 30, gain: 0.8)
        case .chime(let notes):
            var out: [Float] = []
            for i in 0..<notes {
                let last = i == notes - 1
                let dur = last ? (notes >= 5 ? 0.6 : 0.26) : 0.1
                let n = tone(dur, from: note(i * 2), to: note(i * 2), wave: .square(0.25), decay: last ? 5 : 18,
                             vibrato: last && notes >= 5 ? 6 : 0, gain: 0.7)
                out = add(out, n, offset: Int(Double(i) * 0.075 * sampleRate))
            }
            return out
        case .blip(let step):
            let f = note(step)
            return tone(0.06, from: f, to: f, wave: .square(0.5), decay: 35, gain: 0.45)
        case .fanfare:
            var out: [Float] = []
            for (i, n) in [0, 2, 3, 5].enumerated() {
                out = add(out, tone(0.09, from: note(n), to: note(n), wave: .square(0.25), decay: 12, gain: 0.6),
                          offset: Int(Double(i) * 0.07 * sampleRate))
            }
            let hold = add(tone(0.55, from: note(5), to: note(5), wave: .triangle, decay: 4, vibrato: 5),
                           tone(0.55, from: note(7), to: note(7), wave: .square(0.25), decay: 5, gain: 0.35))
            return add(out, hold, offset: Int(0.28 * sampleRate))
        case .whoosh:
            return noise(0.3, seed: 9, decay: 0, swell: true, gain: 0.5)
        case .zap:
            return tone(0.45, from: 300, to: 1500, wave: .square(0.5), decay: 3, vibrato: 18, gain: 0.35)
        case .click:
            return add(tone(0.02, from: 2100, to: 1800, wave: .square(0.5), decay: 120, gain: 0.7),
                       noise(0.012, seed: 5, decay: 200, highpass: true, gain: 0.6))
        case .thud:
            return tone(0.13, from: 110, to: 55, wave: .triangle, decay: 22, gain: 1.2)
        case .tick:
            return tone(0.04, from: 340, to: 300, wave: .triangle, decay: 55, gain: 0.8)
        case .twinkle:
            return add(tone(0.08, from: note(7), to: note(7), wave: .square(0.25), decay: 25, gain: 0.5),
                       tone(0.18, from: note(9), to: note(9), wave: .square(0.25), decay: 14, gain: 0.5),
                       offset: Int(0.07 * sampleRate))
        case .boing:
            return tone(0.26, from: 620, to: 240, wave: .square(0.5), decay: 8, vibrato: 14, gain: 0.5)
        }
    }

    enum Wave { case square(Double), triangle }

    /// 주파수를 `from` → `to` 로 미끄러뜨리는 음. `decay` 는 지수 감쇠 속도(0 = 평평), 끝 5ms 는 페이드(딸깍 잡음 방지).
    static func tone(_ duration: Double, from f0: Double, to f1: Double, wave: Wave, decay: Double,
                     vibrato: Double = 0, gain: Float = 1) -> [Float] {
        let n = Int(duration * sampleRate)
        var phase = 0.0
        return (0..<n).map { i in
            let t = Double(i) / sampleRate
            let u = Double(i) / Double(max(1, n - 1))
            var f = f0 * pow(f1 / f0, u)
            if vibrato > 0 { f *= 1 + 0.02 * sin(2 * .pi * vibrato * t) }
            phase += f / sampleRate
            let p = phase - phase.rounded(.down)
            let v: Double
            switch wave {
            case .square(let duty): v = p < duty ? 1 : -1
            case .triangle: v = 4 * abs(p - 0.5) - 1
            }
            return Float(v * envelope(t, duration: duration, decay: decay)) * gain
        }
    }

    /// 잡음(시드 고정). `highpass` 면 고역만(바삭한 소리), `swell` 이면 커졌다 작아진다(바람 소리).
    static func noise(_ duration: Double, seed: UInt64, decay: Double, highpass: Bool = false, swell: Bool = false,
                      gain: Float = 1) -> [Float] {
        let n = Int(duration * sampleRate)
        var rng = CelebrationFX.Random(seed: seed)
        var previous = 0.0, low = 0.0
        return (0..<n).map { i in
            let t = Double(i) / sampleRate
            let raw = rng.range(-1, 1)
            var v: Double
            if highpass {
                v = raw - previous
                previous = raw
            } else {
                low += (raw - low) * (swell ? 0.05 + 0.25 * t / duration : 0.3)   // 점점 밝아지는 바람
                v = low * 2
            }
            let env = swell ? sin(.pi * t / duration) : envelope(t, duration: duration, decay: decay)
            return Float(v * env) * gain
        }
    }

    static func envelope(_ t: Double, duration: Double, decay: Double) -> Double {
        let attack = min(1, t / 0.002)
        let release = min(1, max(0, (duration - t) / 0.005))
        return attack * release * (decay > 0 ? exp(-decay * t) : 1)
    }

    static func add(_ a: [Float], _ b: [Float], offset: Int = 0) -> [Float] {
        var out = a
        if out.count < offset + b.count { out += [Float](repeating: 0, count: offset + b.count - out.count) }
        for (k, v) in b.enumerated() { out[offset + k] += v }
        return out
    }

    /// 16비트 모노 WAV — `NSSound(data:)` 가 바로 읽는다.
    static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sampleRate))
        u32(UInt32(sampleRate) * 2); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32_767))) }
        return data
    }
}

/// 재생 중인 연출의 소리 — 연출 하나당 한 번(`serial`), 연출이 끊기면 같이 멈춘다.
@MainActor
final class CelebrationSoundPlayer {
    private var sound: NSSound?
    private var serial: Int?

    /// `elapsed` 만큼 이미 지났으면(다시 붙은 화면 등) 그만큼 앞을 잘라 박자를 맞춘다.
    func play(_ active: CelebrationPlayer.Active, elapsed: TimeInterval) {
        guard serial != active.serial else { return }
        stop()
        serial = active.serial
        let cues = CelebrationSound.cues(for: active.kind, reduceMotion: active.reduceMotion)
            .compactMap { cue -> CelebrationSound.Cue? in
                cue.at >= elapsed ? CelebrationSound.Cue(at: cue.at - elapsed, sound: cue.sound) : nil
            }
        guard !cues.isEmpty else { return }
        let samples = CelebrationSound.render(cues, length: max(0.1, active.duration - elapsed + 0.7))
        let s = NSSound(data: CelebrationSound.wav(samples))
        sound = s
        s?.play()
    }

    func stop() {
        sound?.stop()
        sound = nil
        serial = nil
    }
}
