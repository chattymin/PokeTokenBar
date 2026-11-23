import Foundation

/// 연출 큐 — 헤더가 들여다보고 꺼내는 쪽. `CompanionStore` 가 구현하고, 테스트는 같은 store 로 돌린다.
@MainActor
protocol CelebrationQueue: AnyObject {
    var pendingCelebrations: [CompanionStore.Celebration] { get }
    @discardableResult func consumeCelebration() -> CompanionStore.Celebration?
}

extension CompanionStore: CelebrationQueue {}

/// 홈 헤더의 연출 재생 규칙(순수) — 무엇을 다음에 재생하나, 언제 큐에서 꺼내나, 정보 칸을 언제까지
/// 가리나, 공개 전·공개 때 칸에 어떤 스프라이트를 그리나.
///
/// 뷰에서 떼어 낸 이유: 재생 상태는 헤더의 `@State` 에 사는데, 팝오버를 닫으면(`contentViewController = nil`)
/// 또는 상점·가방·도감 탭으로 가면 헤더가 통째로 사라진다. 재생을 **시작할 때** 큐에서 꺼내던 첫 구현은
/// 전설 부화 1초 만에 팝오버를 닫으면 다시 열었을 때 알 깨기 없이 새 포켓몬 이름·배지가 그대로 보였다.
/// 그래서 큐에서는 **공개 순간**(부화·진화·리빌) 또는 **끝**(졸업)에 꺼낸다. 그 전에 끊기면 다음 마운트가
/// 처음부터 다시 재생하고, 그 뒤에 끊기면 남은 꼬리만 잃는다. 이 규칙을 테스트로 고정하려고 순수 타입으로 뒀다.
struct CelebrationPlayer: Equatable {
    typealias Celebration = CompanionStore.Celebration

    /// 칸에 그릴 스프라이트 하나(종 nil = 알).
    struct Sprite: Equatable {
        var speciesID: Int?
        var shiny = false
        var form: PokemonForm?
        /// "항상 뒷모습" 설정 — 연출 중에도 평소 칸과 같은 방향으로 그린다(알은 뒷모습이 없어 무시된다).
        var back = false
    }

    enum Kind: Equatable {
        case hatch(HatchEffect.Profile, egg: Sprite, reveal: Sprite)
        case evolve(from: Sprite, to: Sprite)
        case graduate(Sprite, egg: Sprite)
        case dittoReveal(disguise: Sprite, ditto: Sprite)
    }

    /// 정보 칸을 가리는 동안 그 자리에 보일 것 — 알 문구, 또는 공개 전 모습의 이름(과 등급).
    enum Concealment: Equatable {
        case egg
        case subject(name: String, rarity: Rarity?)
    }

    /// 재생 중인 연출 한 건. `celebration` 은 큐 맨 앞에 **아직 남아 있는** 그 항목이다.
    struct Active: Equatable {
        let serial: Int
        let celebration: Celebration
        let kind: Kind
        let start: Date
        /// 큐에서 꺼내는 시각(시작 기준) — 부화·진화·리빌은 공개 순간, 졸업은 끝.
        let consumeAt: TimeInterval
        let duration: TimeInterval
        var consumed = false
    }

    /// 재생 단계가 넘어갈 때 헤더가 할 일.
    enum Event: Equatable {
        /// 공개 순간(큐에서 꺼냄) — 이로치 ✨·🎭 버스트를 띄운다.
        case revealed(Celebration)
        /// 끝 — 다음 연출로.
        case finished
    }

    private(set) var active: Active?
    private var serial = 0

    /// 비어 있으면 큐 맨 앞을 **꺼내지 않고** 재생을 시작한다.
    @MainActor
    mutating func startIfIdle(queue: some CelebrationQueue, current: Sprite, reduceMotion: Bool, now: Date) {
        guard active == nil, let front = queue.pendingCelebrations.first else { return }
        let next = queue.pendingCelebrations.dropFirst().first
        serial += 1
        let (kind, consumeAt, duration) = Self.plan(front, next: next, current: current, reduceMotion: reduceMotion)
        active = Active(serial: serial, celebration: front, kind: kind, start: now,
                        consumeAt: consumeAt, duration: duration)
    }

    /// 다음으로 깨어나야 할 시각(꺼낼 때 또는 끝날 때). 재생 중이 아니면 nil.
    var nextDeadline: Date? {
        guard let a = active else { return nil }
        return a.start.addingTimeInterval(a.consumed ? a.duration : a.consumeAt)
    }

    /// `now` 까지 지난 단계를 처리한다. 꺼낼 때는 큐 맨 앞이 여전히 그 연출일 때만 꺼낸다 — 그 사이
    /// 세이브 불러오기 등으로 큐가 바뀌었으면 남의 연출을 꺼내지 않는다.
    @MainActor
    mutating func advance(queue: some CelebrationQueue, now: Date) -> [Event] {
        guard var a = active else { return [] }
        var events: [Event] = []
        // 1ms 여유: Date 는 기준 시각부터의 Double 초라 "시작 + 3.8" 을 다시 빼면 3.7999… 가 된다 — 마감에 맞춰
        // 깨어난 task 가 한 틱 더 기다리지 않게.
        let t = now.timeIntervalSince(a.start) + 0.001
        if !a.consumed, t >= a.consumeAt {
            a.consumed = true
            if queue.pendingCelebrations.first == a.celebration {
                queue.consumeCelebration()
                events.append(.revealed(a.celebration))
            }
        }
        if a.consumed, t >= a.duration {
            active = nil
            events.append(.finished)
        } else {
            active = a
        }
        return events
    }

    /// 지금 정보 칸을 가려야 하나. 재생 중인 연출은 공개 전까지 큐에 남아 있으므로 큐만 보면 된다 —
    /// 맨 앞부터 처음 만나는 "결과를 말해 버리는" 연출(부화·진화·리빌)의 직전 모습을 보인다.
    static func concealment(_ pending: [Celebration]) -> Concealment? {
        for c in pending {
            switch c {
            case .hatch: return .egg
            case .evolve(_, _, _, _, let fromName): return .subject(name: fromName, rarity: nil)
            case .dittoReveal(_, let disguise): return .subject(name: disguise.name, rarity: disguise.rarity)
            case .graduate: continue
            }
        }
        return nil
    }

    /// 재생 중이 아닐 때 칸에 보일 모습 — 큐 맨 앞 연출의 "직전 모습"(store 는 이미 결과 상태다).
    @MainActor
    func idleSprite(queue: some CelebrationQueue, current: Sprite) -> Sprite {
        Self.spriteBefore(queue.pendingCelebrations.first, current: current)
    }

    /// 연출 c 가 시작되기 **직전**의 칸 모습. 부화 공개 모습을 정하는 데도 쓴다: 부화 뒤 같은 갱신에
    /// 진화·리빌·졸업이 이어졌으면 갓 부화한 모습은 지금 상태가 아니라 그 다음 연출의 직전 모습이다.
    static func spriteBefore(_ c: Celebration?, current: Sprite) -> Sprite {
        switch c {
        case .hatch?:
            return Sprite(speciesID: nil, back: current.back)
        case .evolve(let from, _, let shiny, let form, _)?:
            return Sprite(speciesID: from, shiny: shiny, form: form, back: current.back)
        case .graduate(let id, let shiny, let form)?:
            return Sprite(speciesID: id, shiny: shiny, form: form, back: current.back)
        case .dittoReveal(_, let disguise)?:
            return Sprite(speciesID: disguise.speciesID, shiny: false, form: disguise.form, back: current.back)
        case nil:
            return current
        }
    }

    /// 연출 c 의 그림·꺼낼 시각·길이.
    static func plan(_ c: Celebration, next: Celebration?, current: Sprite,
                     reduceMotion: Bool) -> (Kind, consumeAt: TimeInterval, duration: TimeInterval) {
        let egg = Sprite(speciesID: nil, back: current.back)
        switch c {
        case .hatch(_, let rarity):
            let profile = HatchEffect.profile(for: rarity)
            return (.hatch(profile, egg: egg, reveal: spriteBefore(next, current: current)),
                    HatchEffect.revealTime(profile, reduceMotion: reduceMotion),
                    HatchEffect.duration(profile, reduceMotion: reduceMotion))
        case .evolve(let fromID, let toID, let shiny, let form, _):
            return (.evolve(from: Sprite(speciesID: fromID, shiny: shiny, form: form, back: current.back),
                            to: Sprite(speciesID: toID, shiny: shiny, form: form, back: current.back)),
                    EvolutionEffect.revealTime(reduceMotion: reduceMotion),
                    EvolutionEffect.duration(reduceMotion: reduceMotion))
        case .graduate(let id, let shiny, let form):
            let duration = GraduationEffect.duration(reduceMotion: reduceMotion)
            return (.graduate(Sprite(speciesID: id, shiny: shiny, form: form, back: current.back), egg: egg),
                    duration, duration)
        case .dittoReveal(let shiny, let disguise):
            // 리빌 뒤 모습은 언제나 메타몽(단일 형태) — 지금 상태가 그 뒤 졸업해 알이어도 그대로 그린다.
            return (.dittoReveal(
                        disguise: Sprite(speciesID: disguise.speciesID, shiny: false, form: disguise.form,
                                         back: current.back),
                        ditto: Sprite(speciesID: PokemonOdds.dittoSpeciesID, shiny: shiny, back: current.back)),
                    DittoRevealEffect.revealAt, DittoRevealEffect.duration(reduceMotion: reduceMotion))
        }
    }
}
