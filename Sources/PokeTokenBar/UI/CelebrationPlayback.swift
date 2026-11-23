import AppKit
import SwiftUI

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
    struct Sprite: Hashable {
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
        /// 시작할 때의 "동작 줄이기" — 타이밍과 그림이 같은 값을 쓰도록 한 번 정해 둔다.
        var reduceMotion = false
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
                        consumeAt: consumeAt, duration: duration, reduceMotion: reduceMotion)
    }

    /// 보던 화면이 전부 사라졌다 — 재생을 버린다. 공개 전이면 연출은 큐에 남아 다음 시작이 처음부터 다시
    /// 재생하고, 공개 뒤면 이미 꺼냈으므로 남은 꼬리만 잃는다.
    mutating func reset() { active = nil }

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
            case .evolve(_, _, _, _, let fromName, let rarity): return .subject(name: fromName, rarity: rarity)
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
        case .evolve(let from, _, let shiny, let form, _, _)?:
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
        case .evolve(let fromID, let toID, let shiny, let form, _, _):
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

// MARK: - 공유 재생(헤더 + 플로팅 펫)

/// 연출 재생 한 벌 — 팝오버 헤더와 플로팅 펫이 **함께** 본다. 화면마다 따로 재생하면 같은 연출을 두 번 보거나
/// 한쪽이 먼저 큐에서 꺼내 다른 쪽이 결과만 보게 된다. 그래서 "무엇을, 언제부터" 를 store 가 가진 이 객체
/// 하나에 두고, 보이는 화면은 같은 시작 시각 기준 경과 시간으로 같은 장면을 그린다.
///
/// - 보이는 화면(`attach`)이 하나라도 있어야 시작한다. 아무도 안 보면 큐에 남아 기다린다.
/// - 꺼내는 시각은 `CelebrationPlayer` 규칙 그대로(공개 순간·끝) — 정확히 한 번.
/// - 보던 화면이 전부 사라지면(`detach`) 재생을 버린다(`CelebrationPlayer.reset`).
/// 저장하지 않는 상태다(앱을 다시 켜면 큐도 비어 있다).
@MainActor
@Observable
final class CelebrationStage {
    private(set) var player = CelebrationPlayer()
    @ObservationIgnored private weak var store: CompanionStore?
    @ObservationIgnored private var viewers: Set<UUID> = []
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored var clock: () -> Date = Date.init
    @ObservationIgnored var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// 테스트는 false 로 두고 `tick()` 을 직접 부른다(가짜 시계로 결정적으로).
    @ObservationIgnored var schedulesTimers = true
    /// 효과음 — 번들 앱에서만(테스트·개발 빌드가 소리를 내지 않게), 설정에서 끌 수 있다(기본 켬).
    @ObservationIgnored var playsSounds: () -> Bool = {
        AppEnv.isBundledApp && (UserDefaults.standard.object(forKey: UsageStore.celebrationSoundsKey) as? Bool ?? true)
    }
    @ObservationIgnored private let sounds = CelebrationSoundPlayer()

    init(store: CompanionStore) { self.store = store }

    var active: CelebrationPlayer.Active? { player.active }
    var viewerCount: Int { viewers.count }

    /// 지금 칸에 보일 "평소" 모습 — 재생 중이 아니면 큐 맨 앞 연출의 직전 모습(결과를 먼저 말하지 않게).
    var currentSprite: CelebrationPlayer.Sprite {
        guard let store else { return CelebrationPlayer.Sprite() }
        return CelebrationPlayer.Sprite(speciesID: store.currentSpeciesID, shiny: store.currentIsShiny,
                                        form: store.currentForm, back: store.facesBack)
    }

    var idleSprite: CelebrationPlayer.Sprite {
        guard let store else { return currentSprite }
        return player.idleSprite(queue: store, current: currentSprite)
    }

    func attach(_ id: UUID) {
        viewers.insert(id)
        kick()
    }

    func detach(_ id: UUID) {
        viewers.remove(id)
        guard viewers.isEmpty else { return }
        timer?.cancel()
        timer = nil
        player.reset()
        sounds.stop()
    }

    /// 보는 화면이 있고 쉬고 있으면 큐 맨 앞을 시작한다. 새 연출이 쌓였을 때도 부른다.
    func kick() {
        guard !viewers.isEmpty, let store else { return }
        if player.active == nil {
            player.startIfIdle(queue: store, current: currentSprite, reduceMotion: reduceMotion(), now: clock())
        }
        // 연출 하나당 한 번(serial) — 이미 울리는 중이면 그대로 둔다.
        if let a = player.active, playsSounds() { sounds.play(a, elapsed: clock().timeIntervalSince(a.start)) }
        schedule()
    }

    /// 큐를 store 가 통째로 바꿨다(세이브 불러오기·놓아주기). 공개 전에 재생 중이던 연출이 큐에서 사라졌으면
    /// 그 장면을 버리고 새 맨 앞으로 — 남의 연출을 끝까지 그리지 않는다.
    func queueReplaced() {
        guard let store, let a = player.active, !a.consumed,
              store.pendingCelebrations.first != a.celebration else { return }
        player.reset()
        sounds.stop()
        kick()
    }

    /// 마감(공개·끝)에 깨어나 단계를 넘긴다.
    func tick() {
        guard let store else { return }
        let events = player.advance(queue: store, now: clock())
        if events.contains(.finished) { kick() } else { schedule() }
    }

    private func schedule() {
        timer?.cancel()
        timer = nil
        guard schedulesTimers, let deadline = player.nextDeadline else { return }
        timer = Task { @MainActor [weak self] in
            let wait = deadline.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            self?.tick()
        }
    }
}

extension CompanionStore {
    /// 메뉴바·플로팅 펫이 그릴 대표 모습 — 자동 추적(대표 미지정)이면 아직 공개 전인 연출의 직전 모습(알·옛 단계·
    /// 위장체)을 붙든다. 팝오버도 펫도 안 보는 동안엔 연출이 기다리므로, 그때까지 결과를 먼저 보여 주지 않는다.
    /// 클릭 판정(알 기도/팝오버) 같은 동작은 실제 `representativeSubject` 를 그대로 쓴다.
    var heldRepresentativeSubject: RepresentativeSubject {
        guard state.representativeSpeciesID == nil, let front = pendingCelebrations.first else {
            return representativeSubject
        }
        let current = CelebrationPlayer.Sprite(speciesID: currentSpeciesID, shiny: currentIsShiny, form: currentForm)
        let held = CelebrationPlayer.spriteBefore(front, current: current)
        return RepresentativeSubject(speciesID: held.speciesID, isShiny: held.shiny, form: held.form)
    }

    /// 플로팅 펫이 연출을 함께 재생하나 — 대표를 고정해 두었으면 펫은 지금 개체를 안 보여 주므로 빠진다.
    var floatingPetPlaysCelebrations: Bool { state.representativeSpeciesID == nil }
}

/// 헤더 무대 — 연출이 76pt 칸 안에서만 일어나면 아무리 공들여도 몇 픽셀 안에서 끝났다(사용자: "허접하다").
/// 재생이 시작되면 알·포켓몬이 칸에서 빠져나와 헤더 가운데 쪽(공개 전엔 가려져 있는 정보 칸 위)으로 옮겨
/// 1.5배로 커져 연출하고, 끝날 때 칸으로 돌아와 평소 모습과 이어진다. 동작 줄이기면 칸에서 그대로 한다.
enum CelebrationStageLayout {
    static let scale: CGFloat = 1.5
    /// 칸 중심 → 무대 중심(pt). 왼쪽으로 넘치는 빛이 팝오버 가장자리에 잘리지 않을 만큼 오른쪽·아래로.
    static let travel = CGSize(width: 96, height: 34)
    static let enter: TimeInterval = 0.32
    static let exit: TimeInterval = 0.38

    /// 0 = 칸(평소 크기), 1 = 무대. 들어갈 땐 살짝 넘쳤다 자리 잡고, 끝나기 직전 칸으로 돌아온다.
    static func progress(at t: TimeInterval, duration: TimeInterval, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        let enterP = CelebrationFX.easeOutBack(t / enter, overshoot: 1.1)
        let exitP = 1 - CelebrationFX.smoothstep(duration - exit, duration, t)
        return min(enterP, exitP)
    }
}

/// 재생 중인 연출 한 장면을 화면에 그린다 — 헤더·플로팅 펫 공용. 스프라이트 뷰는 연출마다 한 번 만들고
/// (TimelineView 가 매 프레임 클로저를 다시 돌려도 SpriteView.init 의 캐시 조회가 매 프레임 돌지 않게),
/// 경과 시간은 공유 시작 시각에서 잰다 — 두 화면이 같은 순간을 그린다.
@MainActor
struct CelebrationStageView: View {
    let active: CelebrationPlayer.Active
    var size: CGFloat
    var layer: CelebrationLayer
    var spriteStore: SpriteStore = .shared
    /// 플로팅 펫의 프레임 하한(배터리 규율) — 헤더는 0.
    var minFrameDelay: TimeInterval = 0
    var bob = true
    /// 헤더 무대(`CelebrationStageLayout`) — 칸에서 빠져나와 크게 연출하고 칸으로 돌아온다. `size` 는 무대 크기.
    var staged = false

    var body: some View {
        // 빛 층도 스프라이트가 필요할 수 있다(부화의 윗뚜껑 = 알 그림) — 층마다 한 번씩만 만든다.
        let sprites: [CelebrationPlayer.Sprite: AnyView] = Dictionary(Set(active.kind.sprites).map { s in
                (s, AnyView(SpriteView(speciesID: s.speciesID, size: size, bob: bob, animated: true, shiny: s.shiny,
                                       minFrameDelay: minFrameDelay, spriteStore: spriteStore, form: s.form,
                                       back: s.back)))
            }, uniquingKeysWith: { a, _ in a })
        let start = active.start
        let kind = active.kind
        let reduce = active.reduceMotion
        let duration = active.duration
        let staged = staged
        TimelineView(.animation) { context in
            let elapsed = max(0, context.date.timeIntervalSince(start))
            let p = staged ? CelebrationStageLayout.progress(at: elapsed, duration: duration, reduceMotion: reduce) : 1
            CelebrationSequenceView(kind: kind, elapsed: elapsed, size: size, reduceMotion: reduce, layer: layer,
                                    sprites: sprites)
                .scaleEffect(staged ? (1 + (CelebrationStageLayout.scale - 1) * p) / CelebrationStageLayout.scale : 1)
                .offset(x: CelebrationStageLayout.travel.width * p, y: CelebrationStageLayout.travel.height * p)
        }
    }
}
