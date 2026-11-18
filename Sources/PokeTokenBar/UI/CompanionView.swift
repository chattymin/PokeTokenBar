import SwiftUI

func rarityColor(_ r: Rarity?) -> Color {
    switch r {
    case .uncommon: return .green
    case .rare: return .blue
    case .legendary: return .orange
    default: return .gray
    }
}

/// 희귀도 캡슐을 늘어놓는 순서(귀한 것부터) — 포획 로그 요약 헤더와 도감 헤더가 공유한다.
/// 순수 표시 순서다. 목록 정렬에는 쓰지 않는다.
let rarityDisplayOrder: [Rarity] = [.legendary, .rare, .uncommon, .common]

/// 아이템 아이콘 — 실제 스프라이트(런타임 로드+캐시) 우선, 로딩 전/미제공/실패 시 이모지 폴백.
@MainActor
struct ItemIconView: View {
    let kind: ItemKind
    var size: CGFloat = 30
    @State private var img: NSImage?

    init(kind: ItemKind, size: CGFloat = 30) {
        self.kind = kind
        self.size = size
        // 캐시에 있으면 즉시(동기) 표시: 재렌더 플래시 방지. The egg items are the eggs the app draws for them: the
        // Legend Plate's eggs look like the Shop's eggs of their rarity.
        let drawnEgg: EggKind? = switch kind {
        case .typeNullEgg: .typeNull
        case .legendaryEgg: .tier(.legendary)
        case .birthdayEgg: .birthday
        case .pokemonEgg: .plain
        case .uncommonEgg: .tier(.uncommon)
        case .rareEgg: .tier(.rare)
        // Forms achievements with no item of their own: the egg they give.
        case .sawsbuckSeasons: .tier(.uncommon)
        case .furfrouTrims, .vivillonPatterns, .unownLetters: .tier(.rare)
        case .fossilEgg: .fossil
        // #135's achievements: the egg they give, when they give one.
        case _ where kind.moreFormsSpecies != nil:
            kind.achievementRewards.contains { $0.kind == .rareEgg } ? .tier(.rare)
                : kind.achievementRewards.contains { $0.kind == .uncommonEgg } ? .tier(.uncommon) : nil
        default: EventEgg(item: kind).map { .event($0) }
        }
        // A Dungeons medal: its tier's first dungeon, drawn.
        let medal = kind.dungeonTier.flatMap { DungeonMedals.dungeons($0).first }.flatMap(DungeonSprites.trimmedImage)
            .map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        _img = State(initialValue: medal ?? drawnEgg.map(EggRenderer.still)
                     ?? kind.spriteName.flatMap { SpriteLoader.cachedItemImage(name: $0) })
    }

    var body: some View {
        Group {
            if let img {
                // 아이템 PNG 는 대체로 정사각(30×30)이라 늘려도 티가 안 났지만, 소스가 외부(PokeAPI
                // items)라 비정사각이 섞이면 그대로 왜곡된다 — 스프라이트와 같은 SpriteFit 규율.
                let fit = SpriteFit.size(for: img.size, box: size)
                Image(nsImage: img).resizable().interpolation(.none)
                    .frame(width: fit.width, height: fit.height)
                    .frame(width: size, height: size)
            } else {
                Text(kind.fallbackEmoji).font(.system(size: size))
                    .frame(width: size, height: size)
            }
        }
        .task(id: kind.spriteName ?? "") {
            guard img == nil, let name = kind.spriteName else { return }
            img = await SpriteLoader.itemImage(name: name)
        }
    }
}

/// SpriteView 가 그리는 주체(정적 이미지 + 그 이미지가 어느 종의 것인지)의 전이 규칙.
///
/// SwiftUI `.task` 는 호스트 없이 돌릴 수 없어 규칙만 순수 값 전이로 빼 둔다(`GIFDecoder.capFrameRate` 와 같은 방식).
/// 여기 담긴 규칙은 둘 다 "화면에 남은 픽셀이 지금 주체의 것인가"를 지킨다.
struct SpriteSubject: Equatable {
    var image: NSImage?
    /// image 가 어느 speciesID 것인지. nil = 알(또는 로드된 개체 없음).
    var loadedID: Int?
    var loadedShiny = false
    var loadedForm: PokemonForm? = nil

    /// Keep the cached pixels and their identity together, including when a pending load is cancelled.
    func startingLoad(cachedImage: NSImage?, for id: Int, shiny: Bool, form: PokemonForm?) -> SpriteSubject {
        SpriteSubject(image: cachedImage, loadedID: cachedImage == nil ? nil : id,
                      loadedShiny: shiny, loadedForm: PokemonForm.resolved(speciesID: id, form: form))
    }

    /// 주체가 알로 바뀌었다(졸업·새 알). 이전 **개체**의 이미지는 다른 주체의 픽셀이라 버린다.
    /// An egg already shown changes only for another egg's image (a guarantee bought): nil never erases a seeded egg
    /// into the 🥚 glyph.
    func becomingEgg(cachedEgg: NSImage?) -> SpriteSubject {
        if loadedID == nil, cachedEgg == nil || cachedEgg === image { return self }
        return SpriteSubject(image: cachedEgg, loadedID: nil)
    }

    /// 로드된 정적 스프라이트를 반영한 결과. **취소된 로드는 nil — 상태를 아예 건드리지 않는다.**
    /// 취소는 곧 주체가 바뀌었다는 뜻이고, 협조적 취소라 continuation 은 그대로 실행되므로 후속 `.task`
    /// 가 이미 새 주체로 잡아 둔 상태를 뒤늦게 덮어쓸 수 있다. 그러면 알 위에 옛 개체가 되살아나고
    /// (#135 와 같은 증상), 실패한 로드가 `loadedID` 만 남기면 다음에 그 종이 다시 활성일 때
    /// "이미 로드됨"으로 판단해 🥚 글리프가 고정된다.
    /// (nil 로 돌려주는 이유: 같은 값을 되쓰면 @State 무효화가 한 번 더 돌아 항상 떠 있는 펫에 불필요한 재렌더가 생긴다.)
    func applyingLoad(_ image: NSImage?, for id: Int, cancelled: Bool,
                      shiny: Bool = false, form: PokemonForm? = nil) -> SpriteSubject? {
        cancelled ? nil : SpriteSubject(image: image, loadedID: id, loadedShiny: shiny,
                                        loadedForm: PokemonForm.resolved(speciesID: id, form: form))
    }

}

/// 스프라이트 1개(런타임 로드 + 캐시). 없으면 알 글리프. bob 으로 가벼운 상하 움직임.
/// animated=true 면 Gen-V GIF 프레임을 순환(미지원/오프라인이면 정적+bob 으로 폴백).
@MainActor
struct SpriteView: View {
    let speciesID: Int?
    var size: CGFloat = 84
    var bob: Bool = false
    var animated: Bool = false
    var shiny: Bool = false
    /// GIF 프레임 지속의 하한(초). 0=원본 delay 그대로. >0 이면 fps 상한 + wakeup 코얼레싱을 적용해
    /// idle 배터리를 통제한다 — 항상 떠 있는 플로팅 펫과 메뉴바 GIF 가 **같은 규율**을 쓰게.
    /// 규율 = "캡이 존재한다(>0)"이며, 두 표면은 지금 같은 사용자 설정
    /// (`UsageStore.AnimationQuality.frameFloor`)을 읽는다. 값이 표면별로 갈릴 수는 있다 —
    /// 22px 메뉴바보다 큰 펫은 같은 fps 에서도 끊김이 더 보인다.
    /// 팝오버 등 일시적 표시는 0(기본)으로 두어 네이티브 fps 유지.
    var minFrameDelay: TimeInterval = 0
    var form: PokemonForm? = nil
    /// The egg drawn when there is no species: its guarantee decides its look.
    var egg: EggKind = .plain
    var isSilhouette: Bool = false
    /// Draws the Pokémon at one scale with its neighbors (`SpriteFit.sameScaleSize`) instead of filling the box:
    /// for the Pokédex grid and evolution lines, where a Charmander sits next to a Charizard.
    var sameScale: Bool = false
    /// Stands the Pokémon on the bottom of its box, whatever the empty margin under it in its image: for the catch log
    /// and a Pokémon's page. The Pokédex's small boxes keep the image centered.
    var bottomAligned: Bool = false
    private let spriteStore: SpriteStore
    @State private var subject: SpriteSubject
    @State private var up = false
    @State private var frames: [(image: NSImage, delay: TimeInterval)] = []
    @State private var frameIndex = 0
    /// The lowest bottom margin of `frames`, measured once per animation: measured at each frame shown, it measured
    /// and kept every frame image of the GIF (`SpriteFit.bottomMargin`).
    @State private var framesMargin: (count: Int, first: ObjectIdentifier?, margin: CGFloat)?

    init(speciesID: Int?, size: CGFloat = 84, bob: Bool = false, animated: Bool = false,
         shiny: Bool = false, minFrameDelay: TimeInterval = 0, spriteStore: SpriteStore = .shared,
         form: PokemonForm? = nil, egg: EggKind = .plain, isSilhouette: Bool = false, sameScale: Bool = false,
         bottomAligned: Bool = false) {
        self.speciesID = speciesID
        self.sameScale = sameScale
        self.bottomAligned = bottomAligned
        self.spriteStore = spriteStore
        self.size = size
        self.bob = bob
        self.animated = animated
        self.shiny = shiny
        self.minFrameDelay = minFrameDelay
        // Pikachu in its costume, unless a look was asked for.
        let form = PikachuCostume.displayForm(speciesID: speciesID, form: form)
        self.form = form
        self.egg = egg
        self.isSilhouette = isSilhouette
        // 캐시에 있으면 즉시(동기) 표시 — 재렌더 플래시 방지 + 정적 스냅샷에서도 보임.
        // speciesID==nil(알 상태)이면 알 스프라이트를 시드(없으면 body 가 🥚 폴백).
        let resolvedForm = speciesID.flatMap { PokemonForm.resolved(speciesID: $0, form: form) }
        let cached = speciesID.map { SpriteLoader.cachedImage(speciesID: $0, shiny: shiny, directory: spriteStore.directory,
                                                            form: resolvedForm) } ?? EggRenderer.still(egg)
        let cachedFrames = animated ? speciesID.map {
            SpriteLoader.cachedFrames(speciesID: $0, shiny: shiny, directory: spriteStore.directory, form: resolvedForm)
        } ?? EggRenderer.idleFrames(egg) : []
        _frames = State(initialValue: GIFDecoder.capFrameRate(cachedFrames, floor: minFrameDelay))
        _subject = State(initialValue: SpriteSubject(image: cached,
                                                    loadedID: (speciesID != nil && cached != nil) ? speciesID : nil,
                                                    loadedShiny: shiny, loadedForm: resolvedForm))
    }

    private var resolvedForm: PokemonForm? {
        speciesID.flatMap { PokemonForm.resolved(speciesID: $0, form: form) }
    }

    /// GIF 프레임 로드 task 의 정체성 — 바뀌면 재디코드·재솎아내기. **하한을 포함한다**:
    /// 프레임은 하한에 맞춰 솎아낸 결과물이라, 빠지면 fps 설정 변경이 종 교체까지 안 먹는다
    /// (`AppDelegate.menuSpriteKey` 와 같은 이유). 순수·테스트용.
    static func frameTaskID(speciesID: Int?, shiny: Bool, floor: TimeInterval, animated: Bool = true,
                            form: PokemonForm? = nil, egg: EggKind = .plain) -> String {
        let resolved = speciesID.flatMap { PokemonForm.resolved(speciesID: $0, form: form) }
        // An egg is told apart by its kind: buying a guarantee redraws it.
        let subject = speciesID.map(String.init) ?? "egg-\(egg)"
        return "\(subject)-\(shiny)-\(floor)-\(animated)-\(resolved?.rawValue ?? "")"
    }

    /// 디코드된 GIF 프레임 중 실제로 재생할 것 — 취소됐거나 2프레임 미만이면 빈 배열(정적 폴백).
    /// 취소 검사가 여기 있는 이유: `frames` 는 body 에서 `img` 보다 먼저 그려지므로, 취소된 로드가
    /// 뒤늦게 대입되면 새 주체(알) 위에 옛 개체의 GIF 가 정지 상태로 올라온다.
    static func framesToApply(_ decoded: [(image: NSImage, delay: TimeInterval)],
                              cancelled: Bool) -> [(image: NSImage, delay: TimeInterval)] {
        (cancelled || decoded.count < 2) ? [] : decoded
    }

    /// 전이 결과를 @State 로 되돌린다(State 세터는 nonmutating). 값이 그대로면 쓰지 않는다 —
    /// @State 는 같은 값을 써도 무효화가 돌아, 항상 떠 있는 펫에 불필요한 재렌더가 생긴다.
    private func apply(_ next: SpriteSubject) {
        guard next != subject else { return }
        subject = next
    }
    private func loadStaticImage(for id: Int) async {
        let loaded = await SpriteLoader.image(speciesID: id, animated: false, shiny: shiny, store: spriteStore,
                                              form: resolvedForm)
        if let next = subject.applyingLoad(loaded, for: id, cancelled: Task.isCancelled,
                                           shiny: shiny, form: resolvedForm) {
            apply(next)
        }
    }

    /// 정적 스프라이트를 다시 불러야 하는가 — 종이 바뀌었거나 **이로치 여부가 뒤집혔을 때**.
    /// 순수·테스트용(`GIFDecoder.capFrameRate` 와 같은 이유). 종만 비교하던 과거 판정은 도감의 이로치 토글에서
    /// .task 가 다시 돌아도 "이미 그 종을 로드했다"로 판정해 색이 안 바뀌는 회귀를 낳았다.
    static func needsReload(loadedID: Int?, loadedShiny: Bool, id: Int, shiny: Bool,
                            loadedForm: PokemonForm? = nil, form: PokemonForm? = nil) -> Bool {
        loadedID != id || loadedShiny != shiny
            || PokemonForm.resolved(speciesID: id, form: loadedForm)
                != PokemonForm.resolved(speciesID: id, form: form)
    }

    /// size×size 슬롯 안에서 이 이미지가 실제로 차지할 크기 — 원본 비율 유지(SpriteFit).
    /// 순수·테스트용. `.resizable()` 은 프레임을 그대로 채우므로(늘어남) 프레임을 미리 재서 넘긴다.
    /// 정사각 원본(정적 96×96·아이템 30×30)은 size×size 그대로라 기존 레이아웃과 동일하다.
    static func imageSize(for image: NSImage, box: CGFloat, sameScale: Bool = false) -> CGSize {
        sameScale ? SpriteFit.sameScaleSize(for: image.size, box: box) : SpriteFit.size(for: image.size, box: box)
    }

    /// 비율 유지로 잰 이미지 프레임 + 바깥 size×size 슬롯. 바깥 슬롯을 유지하는 이유: 진화 라인·도감
    /// 그리드의 폭 계산(EvoLineView.rowWidth 등)이 칸을 정사각으로 전제한다 — 안쪽만 줄여야 안 흔들린다.
    @ViewBuilder
    private func fitted(_ image: NSImage, margin: CGFloat? = nil) -> some View {
        // The egg (no species) keeps filling its box.
        let fit = Self.imageSize(for: image, box: size, sameScale: sameScale && speciesID != nil)
        let grounded = bottomAligned && speciesID != nil
        // Moved down by the transparent margin under the Pokémon, which then spills harmlessly below the box.
        let drop = grounded ? fit.height * (margin ?? SpriteFit.bottomMargin(of: image)) : 0
        if isSilhouette {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.none)
                .foregroundStyle(Color.black.opacity(0.85))
                .frame(width: fit.width, height: fit.height)
                .offset(y: drop)
                .frame(width: size, height: size, alignment: grounded ? .bottom : .center)
        } else {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .frame(width: fit.width, height: fit.height)
                .offset(y: drop)
                .frame(width: size, height: size, alignment: grounded ? .bottom : .center)
        }
    }

    var body: some View {
        Group {
            if !frames.isEmpty {
                // GIF 애니메이션 경로 — 현재 프레임만 렌더. Gen-V GIF 캔버스는 종마다 비정사각이라
                // (잭키 36×66) 정사각으로 늘리면 뚱뚱해진다 → fitted 로 비율 유지.
                // One margin for the whole animation, its lowest: a frame of its own would make the Pokémon hop.
                fitted(frames[frameIndex % frames.count].image, margin: bottomAligned ? animationMargin : nil)
            } else if let img = subject.image {
                fitted(animated && speciesID != nil ? SpriteLoader.animationPlaceholder(img) : img)
            } else {
                Text("🥚").font(.system(size: size * 0.62)).frame(width: size, height: size)
            }
        }
        // The rarer guarantees' eggs glow in their color.
        .background {
            if speciesID == nil, let glow = egg.glow {
                EggShape().fill(glow.opacity(0.45)).frame(width: size, height: size * 0.82).blur(radius: size * 0.08)
            }
        }
        // GIF 재생 중엔 bob 정지(프레임 자체가 움직임) — 폴백/정적일 때만 상하 움직임
        .offset(y: bob && frames.isEmpty && up ? -3 : 0)
        .task(id: Self.frameTaskID(speciesID: speciesID, shiny: shiny, floor: minFrameDelay,
                                  animated: animated, form: resolvedForm, egg: egg)) {
            // animated 프레임은 id/shiny 변경 시 항상 초기화(이전 개체 프레임 잔상 방지)
            frames = animated ? GIFDecoder.capFrameRate(
                speciesID.map { SpriteLoader.cachedFrames(speciesID: $0, shiny: shiny, directory: spriteStore.directory,
                                                          form: resolvedForm) } ?? EggRenderer.idleFrames(egg),
                floor: minFrameDelay) : []
            frameIndex = 0
            guard let id = speciesID else {
                // 알 상태 — the drawn egg, still and idle loop rendered on the spot.
                // 종 → 알(졸업·새 알)이면 이전 개체 이미지를 버려야 한다 — img 는 뷰 identity 가 살아있는 동안
                // 유지되고 플로팅 펫 패널은 졸업 때 재생성되지 않아, 안 버리면 옛 포켓몬이 계속 떠 있다.
                apply(subject.becomingEgg(cachedEgg: EggRenderer.still(egg)))
                await playFrames()
                return
            }
            // Drop the previous form before any await; cached pixels and metadata change atomically.
            let reloadNeeded = Self.needsReload(loadedID: subject.loadedID, loadedShiny: subject.loadedShiny,
                                                id: id, shiny: shiny, loadedForm: subject.loadedForm,
                                                form: resolvedForm)
            if reloadNeeded {
                let cached = SpriteLoader.cachedImage(speciesID: id, shiny: shiny, directory: spriteStore.directory,
                                                       form: resolvedForm)
                apply(subject.startingLoad(cachedImage: cached, for: id, shiny: shiny, form: resolvedForm))
            }
            // Request animation before a missing static PNG can hold playback behind a network fetch.
            if animated && frames.isEmpty {
                let decoded = await SpriteLoader.recoveringAnimationFrames(
                    speciesID: id, shiny: shiny, store: spriteStore, form: resolvedForm,
                    onUnavailable: { await loadStaticImage(for: id) })
                guard !Task.isCancelled else { return }
                frames = GIFDecoder.capFrameRate(Self.framesToApply(decoded, cancelled: false), floor: minFrameDelay)
            } else if frames.isEmpty {
                // Nonanimated views still fetch the exact PNG variant once.
                await loadStaticImage(for: id)
            }
            await playFrames()
        }
        .onAppear {
            guard bob else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { up = true }
        }
    }

    /// `framesMargin` for the frames shown, measured when they change.
    private var animationMargin: CGFloat? {
        let identity = frames.first.map { ObjectIdentifier($0.image) }
        if let known = framesMargin, known.count == frames.count, known.first == identity { return known.margin }
        return frames.map { SpriteFit.bottomMargin(of: $0.image) }.min()
    }

    private func measureAnimationMargin() {
        guard bottomAligned, !frames.isEmpty else { return }
        let margin = frames.map { SpriteFit.bottomMargin(of: $0.image) }.min() ?? 0
        framesMargin = (frames.count, frames.first.map { ObjectIdentifier($0.image) }, margin)
    }

    /// Plays `frames` until the task ends (another subject, the view gone). Nothing to play: returns.
    private func playFrames() async {
        measureAnimationMargin()
        guard !frames.isEmpty, !Task.isCancelled else { return }
        // delay 기반 프레임 advance. .task 취소 시(speciesID 변경/뷰 소멸) 루프 종료 — 누수 없음
        while !Task.isCancelled {
            let delay = frames[frameIndex % frames.count].delay
            // minFrameDelay>0(플로팅 펫): tolerance 로 wakeup 코얼레싱 — 메뉴바 `Timer.tolerance`
            // 와 같은 규율(항상 뜬 표면의 idle 배터리 통제). 0 이면 코얼레싱 없이 네이티브.
            // 코얼레싱 배수는 메뉴바와 공유한다 — 늦게만 발화하므로 크게 두면 재생이 늘어진다
            // (`AppDelegate.menuFrameTolerance` 주석).
            try? await Task.sleep(
                for: .seconds(delay),
                tolerance: minFrameDelay > 0 ? .seconds(delay * AppDelegate.menuFrameTolerance) : .zero)
            if Task.isCancelled { break }
            frameIndex = (frameIndex + 1) % frames.count
        }
    }
}

/// 진화 라인(초기→최종, 다음 후보 미리보기). done/cur/future.
///
/// 분기 라인은 "현재 경로 + 다음 후보 전부"라 길다(이브이 = 본체 1 + 후보 8 → 40pt 기준 472pt).
/// 폭 제한 없는 HStack 은 팝오버 콘텐츠 폭(332pt)을 넘고, **넘친 자식이 부모 VStack 폭을 부풀려
/// 팝오버 전체가 좌우로 잘린다**(진화줄뿐 아니라 탭바·합계까지). `maxWidth` 를 주면 그 폭 안에서
/// 가로 스크롤한다 — 썸네일 크기는 유지하고, 가장자리 페이드 + 셰브론으로 스크롤 가능함을 알린다.
@MainActor
struct EvoLineView: View {
    let nodes: [EvoLineItem]
    let mysteryLabel: String
    var language: AppLanguage = .systemDefault
    var thumb: CGFloat = 40
    var shiny: Bool = false     // 개체가 shiny 면 라인 전체를 shiny 스프라이트로
    /// With `shiny`, the stages drawn shiny: nil for every one (an individual's own path), else these only (a Pokédex
    /// page's family, each species once caught shiny).
    var shinyStages: Set<Int>? = nil
    /// The several evolutions of a stage wrap onto more lines within `maxWidth` rather than scroll in one row.
    var wrapsBranches = false
    var names: [Int: String]? = nil   // 제공되면 각 스프라이트 밑에 작은 이름 라벨(도감 단계별 이름)
    /// 한 줄이 쓸 수 있는 가로 폭. 기본 .infinity = 제한 없음(스크롤 없이 나열).
    var maxWidth: CGFloat = .infinity
    var form: PokemonForm? = nil
    var nameFontSize: CGFloat = 8
    var nameLineLimit: Int = 1
    var nameMinimumScaleFactor: CGFloat = 0.7
    /// Species number → dex `collectionID` (`CompanionStore.dexLinkTargets`). Together with
    /// `onOpenDexEntry` it makes the sprites of species in the dex open their Pokédex page.
    var dexLinks: [Int: String] = [:]
    var onOpenDexEntry: ((String) -> Void)? = nil
    /// Stands each stage on one ground line (`SpriteView.bottomAligned`): the catch log's lines.
    var bottomAligned: Bool = false

    private static let spacing: CGFloat = 2
    /// 화살표 칸 폭 = 썸네일 × 이 비율. 고정 frame 을 줘 SF Symbol 글리프 폭에 의존하지 않게 한다 —
    /// rowWidth 가 실제 렌더 폭과 어긋나면 스크롤 판정이 틀어진다.
    private static let arrowRatio: CGFloat = 0.25
    /// 이름 라벨이 썸네일보다 넓어질 수 있는 최대치.
    private static let nameSlack: CGFloat = 6
    private static let fadeWidth: CGFloat = 24

    @State private var scrollX: CGFloat = 0        // 현재 가로 스크롤 오프셋
    @State private var contentWidth: CGFloat = 0   // 실제 렌더된 한 줄 폭(측정값)

    /// 한 줄이 차지하는 가로 폭. 레이아웃과 같은 식을 쓰는 순수 함수 — 이름 라벨은 상한만 알 수
    /// 있어(`.frame(maxWidth:)`) names 가 있으면 실제 폭이 이 값 이하일 수 있다.
    static func rowWidth(count: Int, thumb: CGFloat, hasNames: Bool) -> CGFloat {
        guard count > 0 else { return 0 }
        let column = thumb + (hasNames ? nameSlack : 0)
        let arrows = CGFloat(count - 1) * thumb * arrowRatio
        // 아이템 수 = 썸네일 count + 화살표 (count-1) → 사이 간격은 (2*count - 2)개
        let gaps = CGFloat(2 * count - 2) * spacing
        return CGFloat(count) * column + arrows + gaps
    }

    /// 스크롤 컨테이너가 필요한가 — 한 줄이 `maxWidth` 를 넘는가. 순수 함수(오버플로 회귀 테스트 대상).
    /// 안 넘으면 기존과 완전히 동일한 평범한 HStack 을 그린다(대부분의 2~3단계 라인).
    static func needsScroll(count: Int, thumb: CGFloat, hasNames: Bool, maxWidth: CGFloat) -> Bool {
        guard maxWidth.isFinite, maxWidth > 0 else { return false }
        return rowWidth(count: count, thumb: thumb, hasNames: hasNames) > maxWidth
    }

    private var totalColumns: Int {
        nodes.reduce(0) { sum, node in
            switch node.content {
            case .branch(let items): return sum + max(1, items.count)
            default: return sum + 1
            }
        }
    }

    var body: some View {
        if wrapsBranches {
            // Centered in its card: as much room on each side (the owner, 2026-11-17).
            row.frame(maxWidth: maxWidth, alignment: .center)
        } else if Self.needsScroll(count: totalColumns, thumb: thumb,
                                   hasNames: names != nil, maxWidth: maxWidth) {
            scrollableRow
        } else {
            row
        }
    }

    // MARK: 스크롤 라인 + 스크롤 가능 신호

    /// 어느 쪽에 스크롤 여지가 남았는지 — 페이드와 셰브론이 공유하는 순수 판정.
    /// 남은 쪽에만 띄워야 끝에 도달한 뒤 "눌러도 안 움직이는 셰브론"이 남지 않는다.
    static func scrollAffordance(scrollX: CGFloat, contentWidth: CGFloat,
                                 maxWidth: CGFloat) -> (back: Bool, forward: Bool) {
        guard contentWidth > maxWidth + 0.5 else { return (false, false) }
        return (scrollX > 0.5, scrollX < contentWidth - maxWidth - 0.5)
    }

    /// 페이드/셰브론 판정에 쓸 한 줄 폭. 측정 전(첫 프레임)엔 rowWidth 추정치를 쓴다 — 측정값만
    /// 믿으면 팝오버를 연 직후 한 프레임 동안 "스크롤 가능" 신호가 없어 그냥 잘린 것처럼 보인다.
    private var effectiveContentWidth: CGFloat {
        contentWidth > 0 ? contentWidth
                         : Self.rowWidth(count: nodes.count, thumb: thumb, hasNames: names != nil)
    }
    private var canScrollBack: Bool {
        Self.scrollAffordance(scrollX: scrollX, contentWidth: effectiveContentWidth,
                              maxWidth: maxWidth).back
    }
    private var canScrollForward: Bool {
        Self.scrollAffordance(scrollX: scrollX, contentWidth: effectiveContentWidth,
                              maxWidth: maxWidth).forward
    }

    private var scrollableRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                row
                    .background(
                        GeometryReader { geo in
                            let frame = geo.frame(in: .named(Self.scrollSpace))
                            Color.clear
                                .onChange(of: frame.minX, initial: true) { _, minX in scrollX = -minX }
                                .onChange(of: frame.width, initial: true) { _, w in contentWidth = w }
                        }
                    )
            }
            // 페이드+셰브론이 같은 역할을 하고, "스크롤 막대 항상 표시" 설정에선 두꺼운 legacy
            // 스크롤러가 줄 높이까지 먹는다. `.hidden` 은 그 경우를 못 막아 `.never` 여야 한다.
            .scrollIndicators(.never)
            .coordinateSpace(name: Self.scrollSpace)
            .frame(maxWidth: maxWidth, alignment: .leading)
            // 넘치는 쪽 가장자리를 흐리게 — 잘린 게 아니라 "이어진다"는 표시.
            .mask(edgeFade)
            .overlay(alignment: .topLeading) { chevron(forward: false, proxy: proxy) }
            .overlay(alignment: .topTrailing) { chevron(forward: true, proxy: proxy) }
            .animation(.easeInOut(duration: 0.15), value: canScrollBack)
            .animation(.easeInOut(duration: 0.15), value: canScrollForward)
        }
    }

    private static let scrollSpace = "evoLineScroll"

    /// 스크롤 여지가 있는 쪽만 페이드아웃하는 마스크(가운데는 불투명).
    private var edgeFade: some View {
        let f = Self.fadeWidth / maxWidth   // 이 경로는 needsScroll 통과 = maxWidth 유한·양수
        return LinearGradient(
            stops: [
                .init(color: canScrollBack ? .clear : .black, location: 0),
                .init(color: .black, location: f),
                .init(color: .black, location: 1 - f),
                .init(color: canScrollForward ? .clear : .black, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing)
    }

    /// 한 화면씩 넘기는 셰브론. 스크롤 여지가 있는 쪽에만 떠서 신호를 겸한다
    /// (스크롤바를 껐으므로 이게 유일한 시각 단서이자 마우스 사용자의 조작 수단).
    @ViewBuilder
    private func chevron(forward: Bool, proxy: ScrollViewProxy) -> some View {
        if forward ? canScrollForward : canScrollBack {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    // 앵커는 항상 .leading — 콘텐츠 끝을 넘는 요청이 clamp 되어 끝에 정확히 닿는다.
                    // .trailing 은 마지막 칸에서 끝에 못 미쳐 멈췄다(실측).
                    proxy.scrollTo(pageTarget(forward: forward), anchor: .leading)
                }
            } label: {
                Image(systemName: forward ? "chevron.right" : "chevron.left")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(forward ? L(language).evolutionScrollNext : L(language).evolutionScrollPrevious)
            .padding(forward ? .trailing : .leading, 1)
            .padding(.top, max(0, thumb / 2 - 8))   // 16pt 버튼의 중심을 스프라이트 중심에
            .transition(.opacity)
        }
    }

    private func pageTarget(forward: Bool) -> Int {
        Self.pageTarget(forward: forward, scrollX: scrollX, count: nodes.count,
                        thumb: thumb, hasNames: names != nil, maxWidth: maxWidth)
    }

    /// 셰브론 한 번에 이동할 칸 인덱스 — 왼쪽 끝 칸에서 "한 화면에 보이는 칸 수"만큼 앞/뒤로.
    /// 현재 위치 기준이라 누를 때마다 목표가 바뀐다(고정 목표는 재클릭 시 제자리 — 겪은 회귀).
    static func pageTarget(forward: Bool, scrollX: CGFloat, count: Int,
                           thumb: CGFloat, hasNames: Bool, maxWidth: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        let stride = thumb + (hasNames ? nameSlack : 0) + thumb * arrowRatio + spacing * 2
        let visible = max(1, Int(maxWidth / stride))
        let first = max(0, Int((scrollX / stride).rounded()))
        return min(max(0, first + (forward ? visible : -visible)), count - 1)
    }

    // MARK: 라인 본체

    /// Which dex page a node opens. Only species already in the dex link — the `?` placeholder and
    /// uncaught species have no page. Pure function (regression-tested).
    static func dexLinkTarget(for node: EvoLineItem, links: [Int: String]) -> String? {
        guard case .species(let id) = node.content else { return nil }
        return links[id]
    }

    private func dexLinkModifier(forSpeciesID id: Int, isCollected: Bool) -> DexEntryLink {
        let target = (onOpenDexEntry != nil && isCollected) ? dexLinks[id] : nil
        var name: String?
        if let names, let raw = names[id] {
            name = PokemonForm.displayName(raw, speciesID: id, form: form, label: nil)
        }
        return DexEntryLink(target: target, hint: L(language).dexOpenEntryHint,
                            accessibilityName: name, cornerRadius: 6, open: onOpenDexEntry)
    }

    private func dexLinkModifier(for node: EvoLineItem) -> DexEntryLink {
        guard case .species(let id) = node.content else {
            return DexEntryLink(target: nil, hint: "", accessibilityName: nil, cornerRadius: 6, open: onOpenDexEntry)
        }
        return dexLinkModifier(forSpeciesID: id, isCollected: node.state != .uncaught)
    }

    private func drawsShiny(_ speciesID: Int) -> Bool {
        shiny && shinyStages.map { $0.contains(speciesID) } ?? true
    }

    private var row: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { i, node in
                if i > 0 {
                    Image(systemName: "arrow.right").font(.system(size: thumb * 0.2))
                        .foregroundStyle(.tertiary)
                        .frame(width: thumb * Self.arrowRatio)
                        .padding(.top, thumb * 0.4)   // 스프라이트 세로 중앙에 정렬
                }
                switch node.content {
                case .species(let id):
                    let uncaught = node.state == .uncaught
                    VStack(spacing: 1) {
                        SpriteView(speciesID: id, size: thumb, shiny: drawsShiny(id) && !uncaught, form: form,
                                   isSilhouette: uncaught, sameScale: true, bottomAligned: bottomAligned)
                            .opacity(node.state == .future ? 0.32 : 1)
                            .saturation(node.state == .future ? 0.4 : 1)
                            .overlay(alignment: .bottom) {
                                if node.state == .current {
                                    Circle().fill(Color.accentColor).frame(width: 4, height: 4).offset(y: 2)
                                }
                            }
                        if let names {
                            // Labels are one thumbnail wide: only Unown's letter fits, the sprite shows other forms.
                            Text(uncaught ? "???"
                                 : PokemonForm.displayName(names[id] ?? "…", speciesID: id, form: form, label: nil))
                                .font(.system(size: nameFontSize))
                                .foregroundStyle(uncaught ? .tertiary : .secondary)
                                .lineLimit(nameLineLimit).minimumScaleFactor(nameMinimumScaleFactor)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: thumb + Self.nameSlack)
                        }
                    }
                    .frame(width: thumb + (names == nil ? 0 : Self.nameSlack))
                    .modifier(dexLinkModifier(for: node))
                    .id(i)

                case .mystery:
                    VStack(spacing: 1) {
                        Text("?")
                            .font(.system(size: thumb * 0.55, weight: .bold, design: .rounded))
                            .frame(width: thumb, height: thumb)
                            .accessibilityLabel(Text(mysteryLabel))
                            .opacity(0.32)
                    }
                    .frame(width: thumb + (names == nil ? 0 : Self.nameSlack))
                    .id(i)

                case .branch(let items):
                    Group {
                        // A Pokédex page's evolutions wrap under each other rather than scroll in one row.
                        if wrapsBranches {
                            WrappingHStack(spacing: Self.spacing, lineSpacing: 4) {
                                ForEach(items) { item in branchCell(item, node: node) }
                            }
                        } else {
                            HStack(alignment: .top, spacing: Self.spacing) {
                                ForEach(items) { item in branchCell(item, node: node) }
                            }
                        }
                    }
                    .id(i)
                }
            }
        }
    }

    private func branchCell(_ item: BranchEvolutionItem, node: EvoLineItem) -> some View {
        VStack(spacing: 1) {
            Group {
                if item.isCollected {
                    // Faded when it is a coming evolution (Home); a Pokédex page's family is caught.
                    SpriteView(speciesID: item.speciesID, size: thumb, shiny: drawsShiny(item.speciesID),
                               form: form,
                               sameScale: true, bottomAligned: bottomAligned)
                        .opacity(node.state == .future ? 0.4 : 1)
                        .saturation(node.state == .future ? 0.6 : 1)
                } else {
                    // Silhouette noire (ombre) pour les évolutions non encore obtenues
                    SpriteView(speciesID: item.speciesID, size: thumb, shiny: false, form: form,
                               isSilhouette: true, sameScale: true, bottomAligned: bottomAligned)
                }
            }
            if let names {
                Text(item.isCollected ? PokemonForm.displayName(names[item.speciesID] ?? "…", speciesID: item.speciesID, form: form, label: nil) : "???")
                    .font(.system(size: nameFontSize))
                    .foregroundStyle(item.isCollected ? .secondary : .tertiary)
                    .lineLimit(nameLineLimit)
                    .minimumScaleFactor(nameMinimumScaleFactor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: thumb + Self.nameSlack)
            }
        }
        .frame(width: thumb + (names == nil ? 0 : Self.nameSlack))
        .modifier(dexLinkModifier(forSpeciesID: item.speciesID, isCollected: item.isCollected))
        .hoverTip(item.isCollected ? (names?[item.speciesID] ?? "") : mysteryLabel)
    }
}

/// Lays its content out at the width it needs, but no wider than `maxWidth`, where it wraps. A `.frame(maxWidth:)`
/// takes the whole `maxWidth` in an HStack, even around two sprites, and leaves the rest of it empty.
struct UpToWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let width = min(content.sizeThatFits(.unspecified).width, maxWidth, proposal.width ?? .infinity)
        return CGSize(width: width, height: content.sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// Home's evolution track: the line's stages as stops along a bar. The stretch from the current stage to the next stop
/// fills with the growth; earlier stretches are full. Coming stages show as silhouettes until caught; where the line
/// goes several ways, every way to its end stands at the end of the track behind a bracket; a final stage heads for
/// the graduation cap. Caught species open their Pokédex page.
@MainActor
struct EvolutionTrackView: View {
    let stops: [CompanionStore.EvolutionTrackStop]
    let progress: Double
    /// The rarity's color, like the growth bar it replaces.
    let tint: Color
    var shiny = false
    var form: PokemonForm? = nil
    /// The costume the individual wears once it is a Pikachu.
    var pikachuCostume: PikachuCostume? = nil
    /// What is left, under the track ("95M to Charmeleon · 24%"); `amount` is drawn bold inside it.
    let remaining: String
    let amount: String?
    /// The exact counts on hover ("60M / 187.5M · 32%").
    let detail: String
    let l: L
    var names: [Int: String] = [:]
    var dexLinks: [Int: String] = [:]
    var onOpenDexEntry: ((String) -> Void)? = nil

    static let stopSize: CGFloat = 36
    static let waysPerLine = 8
    /// The bracket and eight 19 pt ways.
    static let branchMaxWidth: CGFloat = 8 + CGFloat(waysPerLine) * 20
    private static let spriteSize: CGFloat = 30

    /// Index of the stage the individual is at; the stretch after it is the one growing.
    private var currentIndex: Int {
        stops.firstIndex { if case .reached(_, true) = $0 { return true } else { return false } } ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                    if index > 0 { stretch(index) }
                    stopView(stop)
                }
            }
            Text(remainingText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private var remainingText: AttributedString {
        var text = AttributedString(remaining)
        if let amount, let range = text.range(of: amount) {
            text[range].font = .system(size: 10, weight: .bold, design: .rounded)
            text[range].foregroundColor = .primary
        }
        return text
    }

    /// The growing stretch tells its exact counts on hover.
    @ViewBuilder
    private func stretch(_ index: Int) -> some View {
        if index == currentIndex + 1 {
            bar(fill: min(1, max(0, progress))).hoverTip(detail)
        } else {
            bar(fill: index <= currentIndex ? 1 : 0)
        }
    }

    private func bar(fill: Double) -> some View {
        Capsule().fill(Color.primary.opacity(0.12))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading,
                                                  endPoint: .trailing))
                        .frame(width: geo.size.width * fill)
                }
            }
            .clipShape(Capsule())
            .frame(minWidth: 10, maxWidth: .infinity)
            .frame(height: 6)
            .padding(.horizontal, 3)
    }

    private func link(_ id: Int, caught: Bool) -> DexEntryLink {
        DexEntryLink(target: caught ? dexLinks[id] : nil, hint: l.dexOpenEntryHint,
                     accessibilityName: names[id], cornerRadius: Self.stopSize / 2, open: onOpenDexEntry)
    }

    private func ring<Content: View>(dashed: Bool, highlight: Color? = nil,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: Self.stopSize, height: Self.stopSize)
            .background(Circle().fill(highlight.map { $0.opacity(0.25) } ?? Color.primary.opacity(dashed ? 0 : 0.08)))
            .overlay(Circle().strokeBorder(highlight ?? Color.primary.opacity(dashed ? 0.28 : 0),
                                           style: StrokeStyle(lineWidth: highlight == nil ? 1 : 1.5,
                                                              dash: dashed ? [3, 2] : [])))
    }

    @ViewBuilder
    private func stopView(_ stop: CompanionStore.EvolutionTrackStop) -> some View {
        switch stop {
        case .reached(let id, let isCurrent):
            ring(dashed: false, highlight: isCurrent ? tint : nil) {
                SpriteView(speciesID: id, size: Self.spriteSize, shiny: shiny,
                           form: id == PikachuCostume.speciesID ? pikachuCostume?.form ?? form : form, sameScale: true)
            }
            .modifier(link(id, caught: true))
        case .coming(let id, let isCaught):
            ring(dashed: true) {
                SpriteView(speciesID: id, size: Self.spriteSize, form: form, isSilhouette: !isCaught, sameScale: true)
                    .opacity(isCaught ? 0.6 : 0.5)
            }
            .modifier(link(id, caught: isCaught))
            .accessibilityLabel(isCaught ? (names[id] ?? "") : l.unknownNextEvolution)
        case .graduation:
            ring(dashed: true) {
                Image(systemName: "graduationcap.fill").font(.system(size: 14)).foregroundStyle(tint)
            }
            .accessibilityHidden(true)
        case .branch(let paths):
            // Eight ways a line at most (Eevee's), so the stretches keep room to show the growth; more scroll. Vivillon's
            // twenty patterns on one line pushed the popover off its edges. Fewer ways take only their own width, so
            // the stretches reach the edge.
            UpToWidth(maxWidth: Self.branchMaxWidth) {
                HStack(spacing: 3) {
                    TrackBracket().stroke(Color.primary.opacity(0.35), lineWidth: 1).frame(width: 5)
                    branchRows(paths)
                }
            }
            .layoutPriority(1)
        }
    }

    /// The ways the line can go: one row when each is a single species (Eevee), else one row per path with arrows.
    @ViewBuilder
    private func branchRows(_ paths: [[BranchEvolutionItem]]) -> some View {
        if paths.allSatisfy({ $0.count == 1 }) {
            // Eevee's eight still fit on one line beside a stop and a stretch; more wrap.
            let size: CGFloat = paths.count > 6 ? 19 : 22
            if paths.count > Self.waysPerLine {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 1) { ForEach(paths.map { $0[0] }) { candidate($0, size: size) } }
                }
            } else {
                WrappingHStack(spacing: 1, lineSpacing: 1) { ForEach(paths.map { $0[0] }) { candidate($0, size: size) } }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(paths.enumerated()), id: \.offset) { _, path in
                    HStack(spacing: 2) {
                        ForEach(Array(path.enumerated()), id: \.offset) { index, item in
                            if index > 0 {
                                Image(systemName: "arrow.right").font(.system(size: 6)).foregroundStyle(.tertiary)
                            }
                            candidate(item, size: 22)
                        }
                    }
                }
            }
        }
    }

    private func candidate(_ item: BranchEvolutionItem, size: CGFloat) -> some View {
        SpriteView(speciesID: item.speciesID, size: size, shiny: item.isCollected && shiny,
                   form: item.form ?? form, isSilhouette: !item.isCollected)
            .opacity(item.isCollected ? 0.8 : 0.55)
            .frame(width: size, height: size)
            .modifier(DexEntryLink(target: item.isCollected ? dexLinks[item.speciesID] : nil, hint: l.dexOpenEntryHint,
                                   accessibilityName: names[item.speciesID], cornerRadius: 5, open: onOpenDexEntry))
            .hoverTip(item.isCollected ? collectedName(item) : l.unknownNextEvolution)
    }

    private func collectedName(_ item: BranchEvolutionItem) -> String {
        guard let name = names[item.speciesID] else { return l.dexOpenEntryHint }
        return item.form.map { PokemonForm.displayName(name, speciesID: item.speciesID, form: $0, language: l.lang) } ?? name
    }
}

/// [ on its side, opening right: groups the ways a line can go at the end of the track.
private struct TrackBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY + 1))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 1))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 1))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 1))
        return p
    }
}

/// Growth bar. Hovering 300 ms grows it with a small spring "plop" and reveals the exact numbers
/// ("X / Y · Z%") inside; leaving shrinks it back. The expanded height is always reserved, so the
/// hover never moves the layout or resizes the popover.
@MainActor
struct LabeledProgressBar: View {
    let value: Double
    let label: String
    var tint: Color = .orange
    @State private var expanded = false
    @State private var hoverTask: Task<Void, Never>?

    private static let collapsedHeight: CGFloat = 8
    private static let expandedHeight: CGFloat = 14

    var body: some View {
        Capsule().fill(Color.secondary.opacity(0.2))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading,
                                                  endPoint: .trailing))
                        .frame(width: geo.size.width * min(1, max(0, value)))
                }
            }
            .overlay {
                Text(label)
                    .font(.system(size: 9, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
                    .opacity(expanded ? 1 : 0)
                    // In after the bar has grown; out at once so it never squeezes into the thin bar.
                    .animation(expanded ? .easeIn(duration: 0.12).delay(0.12) : .easeOut(duration: 0.06),
                               value: expanded)
            }
            .clipShape(Capsule())
            .frame(height: expanded ? Self.expandedHeight : Self.collapsedHeight)
            .frame(height: Self.expandedHeight)
            .contentShape(Rectangle())
            .onHover { hovering in
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { expanded = true }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.18)) { expanded = false }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityValue(label)
    }
}

/// Makes a sprite open its Pokédex detail page. With no target (egg, uncaught species, `?` node)
/// the content is returned untouched — no button, hover highlight or tooltip — so only real links
/// look clickable. The hover highlight is a background, so it never changes the sprite's layout.
@MainActor
struct DexEntryLink: ViewModifier {
    let target: String?
    let hint: String
    let accessibilityName: String?
    let cornerRadius: CGFloat
    let open: ((String) -> Void)?
    @State private var isHovered = false

    func body(content: Content) -> some View {
        if let target, let open {
            Button { open(target) } label: {
                content
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .background {
                        if isHovered {
                            RoundedRectangle(cornerRadius: cornerRadius).fill(Color.primary.opacity(0.1))
                        }
                    }
                    .animation(.easeOut(duration: 0.12), value: isHovered)
            }
            .buttonStyle(.plain)
            .onContinuousHover { phase in
                isHovered = phase != .ended
                Self.cursor(after: phase == .ended ? .ended : .moved, wasHovered: isHovered)?.nsCursor.set()
            }
            // A click navigates the link away while the pointer is still on it; no `.ended` follows,
            // so without this the hand cursor sticks on the next screen.
            .onDisappear { Self.cursor(after: .disappeared, wasHovered: isHovered)?.nsCursor.set() }
            .hoverTip(hint)
            .accessibilityLabel(accessibilityName.map { "\($0), \(hint)" } ?? hint)
        } else {
            content
        }
    }
}

extension DexEntryLink {
    enum HoverEvent { case moved, ended, disappeared }
    enum Cursor {
        case hand, arrow
        var nsCursor: NSCursor { self == .hand ? .pointingHand : .arrow }
    }

    /// The cursor to set after a hover event, or nil to leave it alone. `set()` (not push/pop) so
    /// nothing can stay stacked; disappearing only resets a cursor this link set itself.
    static func cursor(after event: HoverEvent, wasHovered: Bool) -> Cursor? {
        switch event {
        case .moved: .hand
        case .ended: .arrow
        case .disappeared: wasHovered ? .arrow : nil
        }
    }
}

/// 팝오버 상단 — 현재 포켓몬 + 진화 진행 + 부화/진화 연출.
@MainActor
struct CompanionHeader: View {
    let store: CompanionStore
    /// Opens a species' Pokédex detail page (`PopoverNavigation.openDexEntry`). nil = sprites inert.
    var onOpenDexEntry: ((String) -> Void)? = nil
    /// Opens the Bonuses page from the growth badge. nil = the badge only explains itself on hover.
    var onOpenBonuses: (() -> Void)? = nil
    /// Opens an achievement the Pokémon raised counts for. nil = the goals are plain lines.
    var onOpenAchievement: ((ItemKind) -> Void)? = nil
    // 연출 상태 — 부화/진화 순간 흰 플래시 + 스프링 스케일(본가 진화 신 오마주)
    @State private var flashOpacity: Double = 0
    @State private var celebScale: CGFloat = 1
    @State private var shinyBurst = false
    @State private var dittoBurst = false   // 메타몽 리빌 🎭 버스트
    @State private var seenSeq = -1     // 재생 완료한 celebrationSeq (팝오버 재오픈 시 1회 재생 보장)
    @State private var eggWiggle = false
    // 사탕 "+XP" 순간 표시 (진화 없이 부분 진행일 때도 피드백)
    @State private var seenCandySeq = -1
    @State private var candyXPShown = false
    @State private var candyXPAmount = 0     // 표시 순간 캡처(consume 후에도 텍스트 유지)
    @State private var candyRechargedAmount = 0

    /// Hover tooltip for the growth bars: "X / Y · Z%". Used is clamped to total (egg usage can
    /// overshoot while a hatch retry is pending) and the percent floors, so 100% means done.
    nonisolated static func progressDetail(used: Int, total: Int) -> String {
        let used = min(used, total)
        let percent = total > 0 ? used * 100 / total : 0
        return "\(TokenFormatter.compact(used)) / \(TokenFormatter.compact(total)) · \(percent)%"
    }

    /// 부화 임박(90%+) — 알이 흔들리고 문구가 바뀐다.
    private var eggImminent: Bool { store.isEgg && store.eggProgress >= 0.9 }

    /// The current Pokémon's growth multiplier: the repeat boost and every bonus that applies to it, in one badge.
    /// Orange and named for a repeat, blue for bonuses alone. Hover lists them; a click opens the Bonuses page.
    @ViewBuilder
    private var growthBadge: some View {
        let total = store.currentGrowthTotal
        if total > 1.0001 {
            let isRepeat = store.activeIsRepeat
            let label = isRepeat ? store.l.repeatGrowthBoost(total, rank: store.activeCatchRank) : store.l.growthBoost(total)
            let badge = Badge(label,
                              tint: isRepeat ? .orange : .blue, style: .tinted).fixedSize()
            let breakdown = store.currentGrowthFactors.map(store.growthFactorLine).joined(separator: " · ")
            if let onOpenBonuses {
                Button(action: onOpenBonuses) { badge }
                    .buttonStyle(.plain)
                    .hoverTip(breakdown)
                    .accessibilityLabel(label)
                    .accessibilityHint(breakdown)
            } else {
                badge.hoverTip(breakdown)
            }
        }
    }

    /// The badges after the rarity (`ActiveNewsBadges`), shared with the banner the copy button draws.
    private var activeBadges: some View { ActiveNewsBadges(store: store) }

    /// Its own property, out of `body`: the body is long enough for a newer compiler to give up on it.
    @ViewBuilder
    private var copyButton: some View {
        if store.hasActive { CatchCopyButton(store: store).padding(.top, 6).padding(.trailing, 6) }
    }

    var body: some View {
        // Computed once per render and shared by the big sprite and the evolution line.
        let dexLinks = onOpenDexEntry == nil ? [:] : store.dexLinkTargets
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                SpriteView(speciesID: store.currentSpeciesID, size: 80, bob: true, animated: true,
                           shiny: store.currentIsShiny, form: store.currentSpriteForm, egg: store.eggKind)
                    .frame(width: 84, height: 84)
                    // A soft ground shadow under the Pokémon, on the hero card's glow.
                    .background(alignment: .bottom) {
                        Ellipse().fill(Color.black.opacity(0.18)).frame(width: 52, height: 9).blur(radius: 2)
                            .offset(y: -2)
                    }
                    .rotationEffect(.degrees(eggImminent && eggWiggle ? 5 : (eggImminent ? -5 : 0)))
                    .scaleEffect(celebScale)
                    .overlay(RoundedRectangle(cornerRadius: 12).fill(.white).opacity(flashOpacity))
                    .overlay(alignment: .topTrailing) {
                        if shinyBurst {
                            Text("✨").font(.system(size: 22))
                                .transition(.scale.combined(with: .opacity))
                                .offset(x: 6, y: -6)
                        }
                    }
                    .overlay(alignment: .top) {
                        if dittoBurst {
                            Text("🎭").font(.system(size: 26))
                                .transition(.scale.combined(with: .opacity))
                                .offset(y: -12)
                        }
                    }
                    .overlay(alignment: .top) {
                        if candyXPShown {
                            // The Shock Drive's recharged candies, a bolt as on its sprite: no words to translate.
                            (Text("+\(TokenFormatter.compact(candyXPAmount)) XP")
                                + (candyRechargedAmount > 0
                                    ? Text("  ") + Text(Image(systemName: "bolt.fill")) + Text("+\(candyRechargedAmount)")
                                    : Text("")))
                                .font(.caption.weight(.bold)).foregroundStyle(Color.readableOrange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.regularMaterial, in: Capsule())
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .offset(y: -16)
                        }
                    }
                    // Outermost, so the celebration overlays and animations above stay intact.
                    // An egg has no species (nil) and therefore no link.
                    .modifier(DexEntryLink(
                        target: store.currentSpeciesID.flatMap { dexLinks[$0] },
                        hint: store.l.dexOpenEntryHint, accessibilityName: store.displayName,
                        cornerRadius: 12, open: onOpenDexEntry))
                VStack(alignment: .leading, spacing: 4) {
                    // The rarity above the name, so a long name ("Alolan Ninetales") wraps whole instead of being cut
                    // short beside the badge.
                    if let r = store.rarity {
                        // Wraps rather than run off the card in a long language.
                        WrappingHStack(spacing: 4, lineSpacing: 4) {
                            if r == .legendary {
                                LegendaryBadge(text: store.l.rarityLabel(r).uppercased()).lineLimit(1).fixedSize()
                            } else {
                                Badge(store.l.rarityLabel(r).uppercased(), tint: .rarity(r)).lineLimit(1).fixedSize()
                            }
                            activeBadges
                        }
                        // Clear of the copy button in the card's corner.
                        .padding(.trailing, 22)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(store.displayName).font(.system(size: 15, weight: .bold, design: .rounded))
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        if store.currentIsShiny { Text("✨").font(.system(size: 11)) }
                    }
                    if store.hasActive, let id = store.currentSpeciesID {
                        let types = PokemonTypeData.typeNames(speciesID: id, form: store.currentForm,
                                                              fallback: store.pokemonDetails(speciesID: id, form: store.currentForm)?.types)
                        if !types.isEmpty { TypeBadges(types: types, language: store.language) }
                    }
                    if store.hasActive {
                        // The individual's nature and growth; the stage reads off the track below.
                        WrappingHStack(spacing: 5, lineSpacing: 4) {
                            if let nature = store.currentNature { NatureBadge(nature: nature, language: store.language) }
                            growthBadge
                        }
                        if store.evolutionTrack.isEmpty {
                            // The line is still loading: the plain growth bar meanwhile.
                            LabeledProgressBar(value: store.progress,
                                               label: store.hidesGrowthAmounts
                                                   ? "\(Int(store.progress * 100))%"
                                                   : Self.progressDetail(used: store.state.active?.usedAtStage ?? 0,
                                                                         total: store.threshold),
                                               tint: rarityColor(store.rarity))
                        }
                    } else {
                        // 알 인큐베이션 — 부화까지 진행 (임박 시 문구·색 전환)
                        // A badge that does not fit next to the status goes whole to the next line, never squeezed
                        // onto two lines inside its capsule.
                        WrappingHStack(spacing: 6, lineSpacing: 4) {
                            Text(eggImminent ? store.l.eggImminent : store.l.eggIncubating)
                                .font(.caption2)
                                .foregroundStyle(eggImminent ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                                .fixedSize()
                            // 등급 보증 알이면 무엇을 품고 있는지 — 도감 칩과 같은 라벨·색.
                            // 알 스프라이트는 한 장뿐이라 등급 구분은 이 배지가 유일한 신호다.
                            if let guarantee = store.eggGuarantee {
                                Badge(store.l.eggGuaranteeHint(guarantee), tint: .rarity(guarantee))
                                    .lineLimit(1).fixedSize()
                            }
                            if let typeGuarantee = store.eggTypeGuarantee {
                                Badge(store.l.eggTypeGuaranteeHint(typeGuarantee), tint: .type(typeGuarantee))
                                    .lineLimit(1).fixedSize()
                            }
                        }
                        LabeledProgressBar(value: store.eggProgress,
                                           label: Self.progressDetail(used: store.state.eggUsage,
                                                                      total: store.eggHatchThreshold),
                                           tint: store.eggGuarantee.map { rarityColor($0) } ?? Design.eggColor)
                        if store.isEgg, store.isHatchRetryDelayed {
                            Text(store.l.eggHatchDelayed)
                                .font(.caption2)
                                .foregroundStyle(Color.readableOrange)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(store.l.eggToHatch(TokenFormatter.compact(store.eggTokensToHatch)))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        // 첫 실행(적립 0) — 정적 알 앞에서 "고장났나" 오해 방지용 한 줄 안내
                        if !store.eggStarted {
                            Text(store.l.eggFirstRunHint(TokenFormatter.compact(store.eggHatchThreshold)))
                                .font(.caption2).foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(spacing: 4) {
                        if store.hasActive { Image(systemName: statusSymbol).font(.system(size: 9)) }
                        Text(statusLine)
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            let track = store.evolutionTrack
            if store.hasActive, !track.isEmpty {
                evolutionTrack(track, dexLinks: dexLinks)
            }
            ActiveGoalsList(store: store, onOpen: onOpenAchievement)
            if let g = store.justGraduated {
                Text(store.l.graduated(g))
                    .font(.caption2).foregroundStyle(Color.readableOrange)
            }
        }
        .heroCard(colors: store.themeColors, legendary: store.rarity == .legendary)
        // A discreet copy of the Pokémon raised as a banner, to paste in a conversation (the owner's friends,
        // 2026-11-09); none for an egg.
        .overlay(alignment: .topTrailing) { copyButton }
        // The current form's PokéAPI details, cached after the first fetch: they fill the individual's ability and
        // moves. Same ID as the sprite, so a disguised Ditto loads its disguise's.
        .task(id: store.currentSpeciesID.map { PokemonForm.detailsID(speciesID: $0, form: store.currentForm) }) {
            if store.hasActive, let id = store.currentSpeciesID {
                await store.loadPokemonDetails(speciesID: id, form: store.currentForm)
            }
        }
        .onAppear {
            playCelebrationIfNeeded()
            showCandyXPIfNeeded()
            syncEggWiggle()
        }
        .onChange(of: store.celebrationSeq) { playCelebrationIfNeeded() }
        .onChange(of: store.candyFeedbackSeq) { showCandyXPIfNeeded() }
        .onChange(of: eggImminent) { syncEggWiggle() }
        .task(id: store.currentForm) { await store.loadActiveFormNames() }   // The title names the form.
    }

    /// 부화/진화 연출 1회 재생 — 흰 플래시 페이드아웃 + 스프링 팝. shiny 부화는 ✨ 버스트 추가.
    private func playCelebrationIfNeeded() {
        guard let c = store.celebration, store.celebrationSeq != seenSeq else { return }
        seenSeq = store.celebrationSeq
        store.consumeCelebration()
        flashOpacity = 0.85
        celebScale = 0.6
        withAnimation(.easeOut(duration: 0.8)) { flashOpacity = 0 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { celebScale = 1 }
        if case .hatch(shiny: true) = c {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.3)) { shinyBurst = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                withAnimation(.easeOut(duration: 0.5)) { shinyBurst = false }
            }
        }
        // 메타몽 리빌 — 위장체→메타몽 스프라이트 교체를 플래시가 덮고, 🎭 버스트(이로치면 ✨ 동반).
        if case .dittoReveal(let shiny) = c {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.25)) { dittoBurst = true }
            if shiny {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.45)) { shinyBurst = true }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                withAnimation(.easeOut(duration: 0.5)) { dittoBurst = false; shinyBurst = false }
            }
        }
    }

    /// 사탕 사용 "+XP" 1회 표시. store 를 consume 해 1회성 보장 — 다른 탭 갔다 홈 재진입해
    /// CompanionHeader 가 재마운트(@State 초기화)돼도 다시 뜨지 않는다(회귀 수정).
    private func showCandyXPIfNeeded() {
        guard store.candyFeedbackAmount > 0, store.candyFeedbackSeq != seenCandySeq else { return }
        seenCandySeq = store.candyFeedbackSeq
        candyXPAmount = store.candyFeedbackAmount
        candyRechargedAmount = store.candyFeedbackRecharged
        store.consumeCandyFeedback()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { candyXPShown = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            withAnimation(.easeOut(duration: 0.4)) { candyXPShown = false }
        }
    }

    private func syncEggWiggle() {
        if eggImminent {
            withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) { eggWiggle = true }
        } else {
            withAnimation(.default) { eggWiggle = false }
        }
    }

    /// The stages along a bar that fills with the growth; what is left under it, the next stage named.
    private func evolutionTrack(_ track: [CompanionStore.EvolutionTrackStop], dexLinks: [Int: String]) -> some View {
        let l = store.l
        let amount = store.hidesGrowthAmounts ? nil : TokenFormatter.compact(store.tokensToNext)
        let used = store.state.active?.usedAtStage ?? 0
        let percent = store.threshold > 0 ? min(used, store.threshold) * 100 / store.threshold : 0
        let names = store.currentLine.map { line in
            Dictionary(uniqueKeysWithValues: line.names.keys.map { ($0, line.localizedName($0, store.language)) })
        } ?? [:]
        let percentText = (Double(percent) / 100).formatted(.percent.locale(store.language.displayLocale))
        return EvolutionTrackView(stops: track, progress: store.progress, tint: rarityColor(store.rarity),
                                  shiny: store.currentIsShiny, form: store.evolutionTrackForm,
                                  // A Pokémon GO costume is worn at every stage, Pikachu's cap never over it.
                                  pikachuCostume: store.state.active?.costume == nil ? store.state.active?.pikachuCostume : nil,
                                  remaining: Self.trackCaption(track, amount: amount, percent: percentText,
                                                               names: names, l: l,
                                                               eta: store.timeToNext.map { l.etaAbout(l.shortDuration($0)) }),
                                  amount: amount,
                                  detail: amount == nil ? percentText : Self.progressDetail(used: used, total: store.threshold), l: l,
                                  names: names, dexLinks: dexLinks, onOpenDexEntry: onOpenDexEntry)
    }

    /// What is left before the track's next stop: that stage by name once caught, an evolution while it is a silhouette
    /// or when the line goes several ways, or the graduation. "95M to Charmeleon · 24%". No `amount`: the percentage alone.
    /// `eta`: the time it takes at the user's pace ("about 9 h"), last.
    nonisolated static func trackCaption(_ track: [CompanionStore.EvolutionTrackStop], amount: String?, percent: String,
                                         names: [Int: String], l: L, eta: String? = nil) -> String {
        guard let amount else { return percent }
        let current = track.firstIndex { if case .reached(_, true) = $0 { return true } else { return false } } ?? 0
        let toNext: String
        switch current + 1 < track.count ? track[current + 1] : .graduation {
        case .coming(let id, let isCaught): toNext = isCaught ? l.toStage(amount, names[id] ?? "#\(id)") : l.toNextEvolution(amount)
        case .branch: toNext = l.toNextEvolution(amount)
        case .graduation, .reached: toNext = l.toGraduation(amount)
        }
        return "\(toNext) · \(percent)" + (eta.map { " · \($0)" } ?? "")
    }

    /// The mood's symbol, before its line.
    private var statusSymbol: String {
        switch store.displayState {
        case .sleep: return "moon.zzz.fill"
        case .working: return "bolt.fill"
        case .focus: return "flame.fill"
        case .tired: return "battery.25"
        case .levelUp: return "sparkles"
        case .idle, .egg: return "leaf.fill"
        }
    }

    private var statusLine: String {
        let l = store.l
        switch store.displayState {
        case .egg:     return l.statusEgg
        case .idle:    return l.statusIdle
        case .working: return l.statusWorking
        case .focus:   return l.statusFocus
        case .tired:   return l.statusTired
        case .sleep:   return l.statusSleep
        case .levelUp: return store.evolvedStatus ?? l.statusGrew
        }
    }
}

/// 희귀도 1종 캡슐 — 색 점 + 라벨 + 개수. 선택 시 원색 링 + 체크마크로 강조.
/// (solid 채움 대신 링+체크 — green/orange 위 흰 텍스트 대비 문제 회피 + 라이트/다크 양쪽 가독.
///  텍스트는 .primary 라 모드 자동 적응, 색 정체성은 점·링·체크로 유지 → 엔트리 배지와 안 어긋남.)
/// 0이면 흐리게(필터 불가).
@MainActor
struct RarityTally: View {
    let label: String
    let count: Int
    /// The rarity's species in all: "120/430". Nil where the count is of individuals, or before the index loads.
    var total: Int? = nil
    let color: Color
    var isSelected: Bool = false      // 이 희귀도로 필터 활성 → 원색 링 + 체크
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            Text(total.map { "\(count)/\($0)" } ?? "\(count)").font(.system(size: 11, weight: .bold)).monospacedDigit()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(isSelected ? 0.22 : 0.12))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(isSelected ? color : color.opacity(0.35),
                                        lineWidth: isSelected ? 1.5 : 0.5))
        .opacity(count == 0 ? 0.4 : 1)
    }
}

/// 포획 로그 요약 헤더 — 총 개체 수 + 희귀도별 개체 수 캡슐.
/// 개수 단위가 개체(store.dexCount)라 종 단위인 도감 헤더와 공유하지 않는다.
@MainActor
struct DexSummaryHeader: View {
    let store: CompanionStore
    let selected: Rarity?                  // nil = 필터 없음(전체)
    let onSelect: (Rarity) -> Void         // 캡슐 탭 → 토글
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(store.l.catchLogTitle).font(.callout.weight(.semibold))
                Text(store.l.dexTotal(store.dexEntries.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
            // Wrapped rather than scrolled sideways: the last ones were cut with nothing to say so (#183).
            WrappingHStack(spacing: 4, lineSpacing: 4) {
                ForEach(rarityDisplayOrder, id: \.self) { r in
                    let count = store.dexCount(r)
                    Button { onSelect(r) } label: {
                        RarityTally(
                            label: store.l.rarityLabel(r), count: count, color: rarityColor(r),
                            isSelected: selected == r)
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0)          // 0마리 희귀도는 필터 불가
                    .hoverTip(store.l.dexFilterHint)
                }
            }
        }
    }
}

/// 컬렉션 탭 — 도감과 포획 로그를 하위 세그먼트로 전환한다.
///
/// 두 화면은 같은 데이터를 다른 축으로 본다:
///  - **도감**: 종 1개 = 1칸. 안농의 28개 글자는 상세 화면에서 모아 본다.
///  - **로그**: 개체 1마리 = 1행. 같은 라인이 여러 행으로 나오는 게 정상 — 성격·획득 시각처럼
///    개체에 딸린 정보는 여기에만 있다.
/// 상위 탭(PopoverTab)은 그대로 4개 — 세그먼트 폭(332/2)이 넉넉해 탭바를 늘릴 필요가 없다.
@MainActor
struct CollectionView: View {
    let store: CompanionStore
    let navigation: PopoverNavigation
    @State private var selectedRarity: Rarity?
    @State private var searchText = ""
    @State private var shinyOnly = false
    @State private var favoritesOnly = false
    @State private var evolutionFamily = false
    @State private var dexSort: CompanionStore.DexSortOption = .numberAsc
    @State private var logSort: CompanionStore.CatchLogSortOption = .recentFirst
    /// The species whose detail page was just closed. The detail page replaces the grid, so Back
    /// rebuilds it; this makes it reopen on that species' page instead of page 1. Used once, and set
    /// only when Back lands on the grid: the grid's appearance is what clears it.
    @State private var dexReturnAnchor: String?
    /// Same for the catch log: the row (`DexEntry.id`) that opened the detail page, scrolled back
    /// into view when Back rebuilds the log. Used once.
    @State private var logReturnAnchor: String?

    /// 도감·로그 공통 높이 — 상점·가방과 같은 520. 세그먼트를 전환할 때도, 탭을 넘나들 때도
    /// 팝오버가 리사이즈되지 않는다.
    private static let contentHeight: CGFloat = 520

    private var visibleEntries: [CatchLogItem] {
        store.catchLogItems(
            query: searchText,
            rarity: selectedRarity,
            shinyOnly: shinyOnly,
            favoritesOnly: favoritesOnly,
            evolutionFamily: evolutionFamily,
            sort: logSort
        )
    }

    private var isCustomSortActive: Bool {
        navigation.showingCollectionLog ? logSort != .recentFirst : dexSort != .numberAsc
    }

    private func resetFilters() {
        searchText = ""
        shinyOnly = false
        favoritesOnly = false
        evolutionFamily = false
        selectedRarity = nil
        dexSort = .numberAsc
        logSort = .recentFirst
    }

    var body: some View {
        @Bindable var nav = navigation
        if store.dexEntries.isEmpty {
            emptyState
        } else if let id = nav.dexDetailCollectionID,
                  let species = store.dexSpecies.first(where: { $0.collectionID == id }) {
            PokemonDetailView(store: store, species: species, onBack: {
                // A page opened from another's evolution family goes back to that one first.
                if nav.returnToPreviousDexPage() { return }
                // Back to the log would leave it for the next switch to the grid.
                if !nav.showingCollectionLog { dexReturnAnchor = id }
                nav.dexDetailCollectionID = nil
            }, initialForm: nav.dexDetailForm, onOpenDexPage: { page, current in nav.openDexPage(page, from: current) },
               onOpenCostumes: { nav.showingCostumes = true })
                .id("\(species.collectionID)-\(nav.dexDetailForm?.rawValue ?? "")")
                .frame(height: Self.contentHeight)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    PillPicker(selection: $nav.showingCollectionLog,
                               options: [(false, store.l.dexTitle), (true, store.l.catchLogTitle)])
                    // What is done and what is left, by generation, type and category (the owner, 2026-11-10).
                    CircleIconButton(systemImage: "square.grid.3x3.fill", help: store.l.dexStatsButtonHint) {
                        nav.showingCollectionStats = true
                    }
                    // The costumed Pokémon, a lot each month (the owner, 2026-11-13).
                    CircleIconButton(systemImage: "theatermasks.fill", help: store.l.costumesButtonHint) {
                        nav.showingCostumes = true
                    }
                }

                filterToolbar

                if nav.showingCollectionLog {
                    catchLog
                } else {
                    // The three scopes in one layout, by region with the same cells (the owner, 2026-11-18).
                    FullDexView(store: store, searchText: searchText, missingOnly: nav.dexScope == .missing,
                                shinyOnly: shinyOnly && nav.dexScope != .missing,
                                favoritesOnly: favoritesOnly && nav.dexScope != .missing, evolutionFamily: evolutionFamily,
                                scope: $nav.dexScope, caughtOnly: nav.dexScope == .caught,
                                rarityFilter: $selectedRarity, sort: nav.dexScope == .caught ? dexSort : .numberAsc,
                                returnAnchor: dexReturnAnchor.flatMap { anchor in
                                    store.dexSpecies.first { $0.collectionID == anchor }?.id
                                },
                                onReturnAnchorUsed: { dexReturnAnchor = nil },
                                onSelectSpecies: { sp in nav.dexDetailCollectionID = sp.collectionID })
                }
            }
            .frame(height: Self.contentHeight)
            // Switching segment drops the open detail page — `PopoverNavigation.showingCollectionLog`.
        }
    }

    /// Every species, the caught ones, or the missing ones.
    private var dexScopePicker: some View {
        @Bindable var nav = navigation
        return PillPicker(selection: $nav.dexScope,
                          options: PopoverNavigation.DexScope.allCases.map { ($0, store.l.dexScope($0)) })
    }

    /// The sort orders individuals and the caught grid; the whole Pokédex keeps its regions' order.
    private var sortsCaught: Bool { navigation.showingCollectionLog || navigation.dexScope == .caught }
    /// Shiny only: individuals, caught species, the whole Pokédex's; the missing species have no shiny.
    private var filtersShiny: Bool { navigation.showingCollectionLog || navigation.dexScope != .missing }
    /// Favorites only: the liked individuals, the species they went through; the missing species have none.
    private var filtersFavorites: Bool { filtersShiny }

    private var filterToolbar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                TextField(store.l.dexSearchPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.l.clearFilters)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
            )

            if filtersShiny {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    shinyOnly.toggle()
                }
            } label: {
                Image(systemName: shinyOnly ? "sparkles" : "sparkle")
                    .font(.system(size: 13, weight: shinyOnly ? .bold : .regular))
                    .foregroundStyle(shinyOnly ? Color.yellow : Color.secondary)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(shinyOnly ? Color.yellow.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(shinyOnly ? Color.yellow.opacity(0.6) : Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .hoverTip(store.l.filterShinyOnly)
            .accessibilityLabel(store.l.filterShinyOnly)
            }

            if filtersFavorites {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    favoritesOnly.toggle()
                }
            } label: {
                // Filled or not says it, not the pink alone.
                Image(systemName: favoritesOnly ? "heart.fill" : "heart")
                    .font(.system(size: 12, weight: favoritesOnly ? .bold : .regular))
                    .foregroundStyle(favoritesOnly ? Color.pink : Color.secondary)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(favoritesOnly ? Color.pink.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(favoritesOnly ? Color.pink.opacity(0.6) : Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .hoverTip(store.l.filterFavoritesOnly)
            .accessibilityLabel(store.l.filterFavoritesOnly)
            .accessibilityAddTraits(favoritesOnly ? .isSelected : [])
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    evolutionFamily.toggle()
                }
            } label: {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 13, weight: evolutionFamily ? .bold : .regular))
                    .foregroundStyle(evolutionFamily ? Color.teal : Color.secondary)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(evolutionFamily ? Color.teal.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(evolutionFamily ? Color.teal.opacity(0.6) : Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .hoverTip(store.l.filterEvolutionFamily)
            .accessibilityLabel(store.l.filterEvolutionFamily)

            if sortsCaught {
            Menu {
                if navigation.showingCollectionLog {
                    ForEach(CompanionStore.CatchLogSortOption.allCases) { option in
                        Button {
                            logSort = option
                        } label: {
                            HStack {
                                Text(store.l.label(for: option))
                                if logSort == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } else {
                    ForEach(CompanionStore.DexSortOption.allCases) { option in
                        Button {
                            dexSort = option
                        } label: {
                            HStack {
                                Text(store.l.label(for: option))
                                if dexSort == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13))
                    .foregroundStyle(isCustomSortActive ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(isCustomSortActive ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isCustomSortActive ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .hoverTip(store.l.sortTitle)
            .accessibilityLabel(store.l.sortTitle)
            }
        }
    }

    /// 포획 로그 — 개체 단위 기록. 필터(요약 헤더)는 고정, 목록만 스크롤한다
    private var catchLog: some View {
        let dexLinks = store.dexLinkTargets   // once for all rows, not per row
        // Once for the list too: each row sorted and walked the whole Pokédex for its own badge (n² to scroll it).
        let duplicates = store.duplicateCatchEntryIDs
        let ranks = store.dexCatchRanks
        // Filtered and sorted once: the empty check and the list each did it.
        let entries = visibleEntries
        return VStack(alignment: .leading, spacing: 6) {
            DexSummaryHeader(store: store, selected: selectedRarity) { r in
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedRarity = (selectedRarity == r) ? nil : r
                }
            }
            if entries.isEmpty {
                emptySearchResults
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            Color.clear.frame(height: 0).id("dexTop")
                            ForEach(entries) { item in
                                switch item {
                                case .entry(let entry):
                                    // Keeps the segment, so Back from the detail page returns to the log.
                                    DexEntryRow(store: store, entry: entry, dexLinks: dexLinks,
                                                isDuplicate: duplicates.contains(entry.id), catchRank: ranks[entry.id]) {
                                        logReturnAnchor = entry.id
                                        navigation.dexDetailCollectionID = $0
                                    }
                                case .battleForm(let won):
                                    BattleFormCatchRow(store: store, won: won, dexLinks: dexLinks) { collectionID, form in
                                        logReturnAnchor = won.id
                                        navigation.dexDetailForm = form
                                        navigation.dexDetailCollectionID = collectionID
                                    }
                                }
                            }
                        }
                        .reservesScrollerLane()
                    }
                    .frame(maxHeight: .infinity)
                    .task {
                        guard let anchor = logReturnAnchor else { return }
                        logReturnAnchor = nil
                        // The first scroll is placed with estimated heights for the lazy rows. The
                        // rows it reveals are measured afterwards and push the target off its spot
                        // (a row short on CI), so scroll again once they have been laid out.
                        proxy.scrollTo(anchor, anchor: .center)
                        try? await Task.sleep(for: .milliseconds(50))
                        proxy.scrollTo(anchor, anchor: .center)
                    }
                    // 필터·검색·정렬 변경 시 새 결과를 처음부터 보여준다.
                    .onChange(of: selectedRarity) {
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("dexTop", anchor: .top) }
                    }
                    .onChange(of: searchText) {
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("dexTop", anchor: .top) }
                    }
                    .onChange(of: shinyOnly) {
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("dexTop", anchor: .top) }
                    }
                    .onChange(of: evolutionFamily) {
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("dexTop", anchor: .top) }
                    }
                    .onChange(of: logSort) {
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("dexTop", anchor: .top) }
                    }
                    .onChange(of: favoritesOnly) { proxy.scrollTo("dexTop", anchor: .top) }
                }
            }
        }
    }

    private var emptySearchResults: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(store.l.noSearchResults)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Button(store.l.clearFilters) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    resetFilters()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 빈 도감 — 안내 마스코트(피카츄, PokéAPI) + 포켓몬을 모으라는 문구.
    private var emptyState: some View {
        VStack(spacing: 10) {
            SpriteView(speciesID: 25, size: 96, animated: true)
            Text(store.l.dexEmptyTitle).font(.callout.weight(.semibold))
            Text(store.l.dexEmptyHint)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// 도감 하단의 대표 설정 액션. 문구는 툴팁·접근성에 유지하되 시각적으로는 아이콘만 써서,
/// 긴 en/es 문구가 선택한 종의 이름·희귀도를 밀어내지 않게 한다.
@MainActor
struct RepresentativeFooterButton: View {
    let localization: L
    let isRepresentative: Bool
    let action: () -> Void

    private var title: String {
        isRepresentative ? localization.representativeFollowCurrent : localization.representativeSet
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isRepresentative ? "arrow.triangle.2.circlepath" : "star")
        }
        .labelStyle(.iconOnly)
        .hoverTip(title)
        .accessibilityLabel(title)
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .fixedSize()
    }
}

/// 도감 페이지 셰브론. `.plain` 버튼은 라벨 프레임만 클릭되는데 13pt 셰브론은 약 7×12pt 라
/// 클릭이 자주 빗나갔다(#379). 글리프는 그대로 두고 히트 영역만 `hitSize` 정사각형으로 넓힌다.
/// 푸터는 18pt 높이로 고정돼 있어 넘치는 부분은 레이아웃을 밀지 않고 위아래로 겹친다.
@MainActor
struct DexPageButton: View {
    static let hitSize: CGFloat = 28
    /// 13pt 셰브론 글리프(약 7pt 폭) 양옆에 생기는 히트 영역 여백.
    static let edgeInset: CGFloat = 10

    let forward: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .frame(width: Self.hitSize, height: Self.hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Turns scroll-wheel / trackpad events into single page steps for the Dex grid.
/// `scrollingDeltaY` already reflects the natural-scrolling setting, so a negative delta always
/// means "move the content up" (reveal what comes next), exactly like a list would.
/// What the Pokédex grid's still prefetch depends on: the page shown and the cells the filters keep.
private struct StillPrefetchKey: Equatable {
    let page: Int
    let ids: [String]
}

struct DexScrollPager {
    /// Accumulated trackpad distance (pt) before a gesture flips the page.
    static let preciseThreshold: CGFloat = 24

    private var accumulated: CGFloat = 0
    private var firedThisGesture = false

    /// +1 = next page, -1 = previous page, 0 = no change.
    mutating func step(deltaY: CGFloat, precise: Bool,
                       phase: NSEvent.Phase, momentumPhase: NSEvent.Phase) -> Int {
        // Wheel notch: one event per notch, one page per notch.
        guard precise else { return Self.direction(deltaY) }
        // The momentum tail belongs to a gesture that has already paged.
        guard momentumPhase.isEmpty else { return 0 }
        if phase.contains(.began) || phase.contains(.mayBegin) {
            accumulated = 0
            firedThisGesture = false
        }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            accumulated = 0
            firedThisGesture = false
            return 0
        }
        guard !firedThisGesture else { return 0 }
        accumulated += deltaY
        guard abs(accumulated) >= Self.preciseThreshold else { return 0 }
        let result = Self.direction(accumulated)
        accumulated = 0
        // Phase-less precise devices have no gesture boundary, so only latch real gestures.
        firedThisGesture = !phase.isEmpty
        return result
    }

    /// Cell indices in the order their stills are made ahead: the next page, then the previous one. The current page
    /// loads its own cells, and turning a page prefetches the new one's neighbors. Every page ahead, on an empty cache,
    /// downloaded a GIF for each species of the Pokédex at its first opening.
    static func prefetchOrder(count: Int, current: Int, pageSize: Int) -> [Int] {
        let pageCount = max(1, (count + pageSize - 1) / pageSize)
        return [current + 1, current - 1]
            .filter { $0 != current && (0..<pageCount).contains($0) }
            .flatMap { page in (page * pageSize)..<min(count, (page + 1) * pageSize) }
    }

    static func pageAfterScroll(current: Int, pageCount: Int, step: Int) -> Int {
        min(max(0, current + step), max(0, pageCount - 1))
    }

    /// The page that shows `id` — where Back from a detail page lands. 0 when `id` is nil or
    /// filtered out, the same page a fresh grid opens on.
    static func page(containing id: String?, in ids: [String], pageSize: Int) -> Int {
        guard let id, let index = ids.firstIndex(of: id) else { return 0 }
        return index / pageSize
    }

    private static func direction(_ deltaY: CGFloat) -> Int {
        deltaY < 0 ? 1 : (deltaY > 0 ? -1 : 0)
    }
}

/// Background view that feeds scroll events over its bounds to `onStep`. A local monitor (not a
/// `scrollWheel(with:)` override) keeps clicks and hover on the cells above it untouched.
struct ScrollWheelPager: NSViewRepresentable {
    let onStep: (Int) -> Void

    func makeNSView(context: Context) -> PagerView { PagerView() }
    func updateNSView(_ view: PagerView, context: Context) { view.onStep = onStep }

    final class PagerView: NSView {
        var onStep: ((Int) -> Void)?
        private var pager = DexScrollPager()
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                else { return event }
                let step = self.pager.step(deltaY: event.scrollingDeltaY,
                                           precise: event.hasPreciseScrollingDeltas,
                                           phase: event.phase, momentumPhase: event.momentumPhase)
                if step != 0 { self.onStep?(step) }
                return nil
            }
        }
    }
}

/// The whole Pokédex region by region, as TokenDex shows it: the completion and the shinies, then each region with
/// its progress and rarities and every one of its species, caught (its sprite, in its rarity's color), only seen
/// (faded) or missing (its number alone, no sprite to download). A region folds on its header.
@MainActor
struct FullDexView: View {
    let store: CompanionStore
    let searchText: String
    let missingOnly: Bool
    /// Only the species caught shiny.
    var shinyOnly = false
    /// Only the species a liked Pokémon went through.
    var favoritesOnly = false
    /// The search finds whole evolution families, their missing members included.
    var evolutionFamily = false
    @Binding var scope: PopoverNavigation.DexScope
    /// Only the species in the Pokédex: "Obtenus", laid out as "Tous" and "Manquants" are (the owner, 2026-11-18).
    var caughtOnly = false
    /// The rarity filter, on the three scopes alike.
    var rarityFilter: Binding<Rarity?> = .constant(nil)
    private var selectedRarity: Rarity? {
        get { rarityFilter.wrappedValue }
        nonmutating set { rarityFilter.wrappedValue = newValue }
    }
    /// The caught species' order: by number they stand in their regions, any other order in one grid.
    var sort: CompanionStore.DexSortOption = .numberAsc
    /// The species whose page was just closed: the list comes back to it, then `onReturnAnchorUsed` clears it.
    var returnAnchor: Int? = nil
    var onReturnAnchorUsed: () -> Void = {}
    let onSelectSpecies: (CompanionStore.DexSpecies) -> Void
    @State private var folded: Set<Int> = []

    /// Five to a row, so a sprite stays big enough to tell apart.
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 5)

    /// A species' rarity: its line's, as the totals count it, else its Pokédex record's before the index loads.
    private func rarity(_ id: Int, _ species: [Int: CompanionStore.DexSpecies], _ lines: [Int: Rarity]?) -> Rarity? {
        lines?[id] ?? species[id]?.rarity
    }

    var body: some View {
        let species = Dictionary(store.dexSpecies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let graduated = store.graduatedSpeciesIDs
        let names = species.mapValues(\.name)
        var kept: Set<Int>? = shinyOnly ? Set(store.dexSpecies.filter(\.isShiny).map(\.id)) : nil
        if favoritesOnly {
            let liked = store.favoriteSpeciesIDs
            kept = kept.map { $0.intersection(liked) } ?? liked
        }
        let lines = store.speciesRarities
        // The scope and the other filters first: the rarity chips count what they would show.
        let inScope = Self.visibleIDs(names: names, missingOnly: missingOnly, query: searchText, shinies: kept,
                                      family: evolutionFamily)
            .filter { !caughtOnly || names[$0] != nil }
        let visible = selectedRarity.map { wanted in inScope.filter { rarity($0, species, lines) == wanted } } ?? inScope
        func shows(_ id: Int) -> Bool { visible.contains(id) }
        return VStack(alignment: .leading, spacing: 6) {
            PillPicker(selection: $scope, options: PopoverNavigation.DexScope.allCases.map { ($0, store.l.dexScope($0)) })
            summary(registered: species.count, graduated: graduated)
            // Out of each rarity's total: those caught ("Tous", "Obtenus"), or those missing ("Manquants").
            rarityChips(missingOnly ? inScope : inScope.filter { names[$0] != nil }, species: species, lines: lines)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if caughtOnly, sort != .numberAsc {
                            // Another order than the number: one grid in that order, no regions to cut it.
                            let ordered = store.sortDexSpecies(visible.compactMap { species[$0] }, by: sort)
                            LazyVGrid(columns: Self.columns, spacing: 4) {
                                ForEach(ordered, id: \.id) { sp in
                                    cell(sp.id, species: sp, isGraduated: graduated.contains(sp.id)).id(sp.id)
                                }
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        } else {
                            ForEach(Array(PokemonTypeData.generations.enumerated()), id: \.offset) { index, range in
                                let ids = range.filter(shows)
                                if !ids.isEmpty {
                                    region(index + 1, range: range, ids: ids, species: species, graduated: graduated)
                                }
                            }
                        }
                    }
                    .reservesScrollerLane()
                }
                .frame(maxHeight: .infinity)
                .task(id: returnAnchor) {
                    guard let returnAnchor else { return }
                    // Cleared only once scrolled to: cleared on appear, the wait was cancelled and the scroll ran
                    // before the grid had its layout, landing mid-page (the owner, 2026-11-18, back from Charizard).
                    // The lazy cells measured after the first scroll move it, so it scrolls again.
                    do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
                    proxy.scrollTo(returnAnchor, anchor: .center)
                    do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
                    proxy.scrollTo(returnAnchor, anchor: .center)
                    onReturnAnchorUsed()
                }
            }
        }
        .task { await store.backfillMissingDexNames() }
        // The rarities' totals ("120/430") and the missing species' rarity read the hatch index.
        .task { await store.loadHatchIndex() }
    }

    /// The rarity filter, as "Obtenus" had it, now on the three scopes: each rarity's species in this scope, out of
    /// all of that rarity; a click keeps that rarity only, a second one lifts it.
    private func rarityChips(_ ids: Set<Int>, species: [Int: CompanionStore.DexSpecies], lines: [Int: Rarity]?) -> some View {
        let totals = store.speciesTotalsByRarity
        return WrappingHStack(spacing: 4, lineSpacing: 4) {
            ForEach(rarityDisplayOrder, id: \.self) { r in
                let count = ids.filter { rarity($0, species, lines) == r }.count
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedRarity = selectedRarity == r ? nil : r }
                } label: {
                    RarityTally(label: store.l.rarityLabel(r), count: count, total: totals?[r],
                                color: rarityColor(r), isSelected: selectedRarity == r)
                }
                .buttonStyle(.plain)
                .disabled(count == 0 && selectedRarity != r)
                .hoverTip(store.l.dexFilterHint)
            }
        }
    }

    /// Whether a species shows: the missing ones only when asked, and those the search finds, by number (with or
    /// without "#" and leading zeros) or by the name of a species in the Pokédex.
    static func shows(_ id: Int, names: [Int: String], missingOnly: Bool, query: String) -> Bool {
        if missingOnly, names[id] != nil { return false }
        return found(id, names: names, query: query)
    }

    /// The species shown: those `shows` keeps, with the whole family of each one the search finds when `family` is
    /// on (missing members too: a search for a caught Charmander brings Charizard still missing), and only the
    /// `shinies` when given.
    static func visibleIDs(names: [Int: String], missingOnly: Bool, query: String, shinies: Set<Int>? = nil,
                           family: Bool = false) -> Set<Int> {
        let every = PokemonTypeData.generations.flatMap { Array($0) }
        var ids = Set(every.filter { found($0, names: names, query: query) })
        if family, !normalized(query).isEmpty { ids = Set(ids.flatMap(Self.family)) }
        return ids.filter { id in
            (!missingOnly || names[id] == nil) && (shinies.map { $0.contains(id) } ?? true)
        }
    }

    /// Every species of the line `id` is in, from its first one down every branch.
    static func family(of id: Int) -> [Int] {
        var line: [Int] = []
        var queue = [PokemonEvolutionData.root(of: id)]
        while let next = queue.popLast() {
            line.append(next)
            queue += PokemonEvolutionData.children[next] ?? []
        }
        return line
    }

    private static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespaces).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }

    private static func found(_ id: Int, names: [Int: String], query: String) -> Bool {
        let query = normalized(query)
        guard !query.isEmpty else { return true }
        if let number = Int(query) { return id == number || String(id).hasPrefix(String(number)) }
        return names[id]?.lowercased().contains(query) == true
    }

    /// The whole Pokédex: species graduated, their share, the ones only seen, the forms and the shinies.
    private func summary(registered: Int, graduated: Set<Int>) -> some View {
        let owned = store.graduatedCollectionProgress
        let total = max(1, owned.speciesTotal)
        let shinies = Set(store.dexSpecies.filter(\.isShiny).map(\.id)).count
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(store.l.dexSpeciesProgress(owned.species, of: owned.speciesTotal)).font(.callout.weight(.semibold))
                Text(store.l.dexPercent(owned.species * 100 / total)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if registered > owned.species {
                    Label(store.l.dexSeenOnly(registered - owned.species), systemImage: "eye").labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary).hoverTip(store.l.dexSeenNotGraduated)
                }
            }
            HStack(spacing: 8) {
                Text(store.l.dexLinesProgress(owned.lines, of: owned.linesTotal)).hoverTip(store.l.dexLinesHint)
                Text(store.l.formsCollected(owned.forms, of: owned.formsTotal))
                Text("✨ \(store.l.dexShinySpecies(shinies))")
            }
            .foregroundStyle(.secondary)
            ProgressView(value: Double(owned.species), total: Double(total)).controlSize(.small)
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1).minimumScaleFactor(0.8)
    }

    private func region(_ generation: Int, range: ClosedRange<Int>, ids: [Int],
                        species: [Int: CompanionStore.DexSpecies], graduated: Set<Int>) -> some View {
        let caught = range.filter { graduated.contains($0) }.count
        let isFolded = folded.contains(generation)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isFolded { folded.remove(generation) } else { folded.insert(generation) }
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: isFolded ? "chevron.right" : "chevron.down")
                            .font(.caption2.weight(.bold)).foregroundStyle(.secondary).frame(width: 10)
                        Text(store.l.regionName(generation: generation)).font(.callout.weight(.semibold))
                        Spacer(minLength: 4)
                        Text("\(caught) / \(range.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text("\(caught * 100 / range.count) %").font(.caption.monospacedDigit().weight(.semibold))
                    }
                    ProgressView(value: Double(caught), total: Double(range.count)).controlSize(.mini)
                    HStack(spacing: 8) {
                        ForEach(rarityDisplayOrder, id: \.self) { rarity in
                            let count = range.filter { species[$0]?.rarity == rarity }.count
                            if count > 0 {
                                HStack(spacing: 3) {
                                    Circle().fill(rarityColor(rarity)).frame(width: 8, height: 8)
                                    Text("\(count)").font(.caption2.monospacedDigit())
                                }
                                .hoverTip(store.l.rarityLabel(rarity))
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isFolded ? [] : .isSelected)
            if !isFolded {
                LazyVGrid(columns: Self.columns, spacing: 4) {
                    ForEach(ids, id: \.self) { id in
                        cell(id, species: species[id], isGraduated: graduated.contains(id)).id(id)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func cell(_ id: Int, species: CompanionStore.DexSpecies?, isGraduated: Bool) -> some View {
        let number = String(format: "%03d", id)
        if let species {
            // The Pokémon its page opens on: shiny in the form caught shiny, as the caught grid drew it.
            let cover = store.dexCover(for: species)
            Button { onSelectSpecies(species) } label: {
                VStack(spacing: 2) {
                    // One scale for the whole grid, as on the caught grid: a Charmander smaller than a Charizard.
                    SpriteView(speciesID: id, size: 42, shiny: cover.isShiny, form: cover.form, sameScale: true)
                        .frame(width: 44, height: 44)
                        // A shiny one says so, as on the caught grid.
                        .overlay(alignment: .topTrailing) {
                            if species.isShiny { Text("✨").font(.system(size: 10)).accessibilityLabel(store.l.dexShinyLabel) }
                        }
                    // Its rarity in a dot before its number.
                    HStack(spacing: 3) {
                        Circle().fill(rarityColor(species.rarity)).frame(width: 8, height: 8)
                        Text(number).font(.system(size: 10, weight: .semibold).monospacedDigit())
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 4)
                .background(rarityColor(species.rarity).opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                .opacity(isGraduated ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .hoverTip("#\(id) \(species.name) · \(store.l.rarityLabel(species.rarity))"
                  + (isGraduated ? "" : " · \(store.l.dexSeenNotGraduated)"))
            .accessibilityLabel("#\(id) \(species.name)")
        } else {
            VStack(spacing: 2) {
                // Who's that Pokémon: its shape in black, at the grid's one scale, its name still hidden.
                SpriteView(speciesID: id, size: 42, isSilhouette: true, sameScale: true)
                    .frame(width: 44, height: 44)
                Text(number).font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            // How to get it, rather than only that it is missing.
            .hoverTip(howToGet(id))
            .accessibilityLabel(store.l.dexMissingHint(id))
        }
    }

    /// The tip of a species not caught (`L.dexHowToGet`): a species owned is named, one not caught keeps its number.
    private func howToGet(_ id: Int) -> String {
        let source = CompanionStore.source(of: id)
        let nextDig = source == .fossil ? store.excavationProgress.towardNext.map { ($0, FossilDig.rockPerDig) } : nil
        return store.l.dexHowToGet(id, source: source, name: { other in
            store.dexSpecies.first { $0.id == other }.map { "\($0.name) (#\(other))" } ?? "#\(other)"
        }, goals: store.goals(counting: id), nextDig: nextDig)
    }
}

/// 도감 — 보유 종만 도감 번호순으로, 한 페이지 16칸(4열×4행) 고정 격자.
@MainActor
private struct DexGridView: View {
    let store: CompanionStore
    let searchText: String
    let shinyOnly: Bool
    let favoritesOnly: Bool
    let evolutionFamily: Bool
    let sortOption: CompanionStore.DexSortOption
    @Binding var selectedRarity: Rarity?
    let onSelectSpecies: (CompanionStore.DexSpecies) -> Void
    let onResetFilters: () -> Void

    /// nil = the page that shows `returnAnchor` (Back from a detail page). Paging or filtering sets it.
    @State private var page: Int?
    /// The species whose detail page was just closed. Only picks the page; nothing is selected.
    /// State, not a `let`: the parent clears its copy once the grid appears, which must not move the page.
    @State private var returnAnchor: String?
    /// 선택한 칸 — 하단 줄에 희귀도를 띄우고, 이로치를 잡은 종이면 스프라이트를 그 색으로 바꾼다.
    @State private var selectedID: String?

    private static let columns = 4
    private static let rows = 4
    private static let pageSize = columns * rows      // 16
    private static let spacing: CGFloat = 4

    /// `returnAnchor` = the species whose detail page was just closed. The grid opens on its page,
    /// set here rather than in `onAppear`, which would flash page 1 for a frame first.
    init(store: CompanionStore, searchText: String, shinyOnly: Bool, favoritesOnly: Bool = false, evolutionFamily: Bool,
         sortOption: CompanionStore.DexSortOption, selectedRarity: Binding<Rarity?>,
         returnAnchor: String?,
         onSelectSpecies: @escaping (CompanionStore.DexSpecies) -> Void,
         onResetFilters: @escaping () -> Void) {
        self.store = store
        self.searchText = searchText
        self.shinyOnly = shinyOnly
        self.favoritesOnly = favoritesOnly
        self.evolutionFamily = evolutionFamily
        self.sortOption = sortOption
        _selectedRarity = selectedRarity
        self.onSelectSpecies = onSelectSpecies
        self.onResetFilters = onResetFilters
        _returnAnchor = State(initialValue: returnAnchor)
    }

    var body: some View {
        let all = store.dexSpecies
        let visible = store.filteredDexSpecies(
            query: searchText,
            rarity: selectedRarity,
            shinyOnly: shinyOnly,
            favoritesOnly: favoritesOnly,
            evolutionFamily: evolutionFamily,
            sort: sortOption
        )
        let pageCount = max(1, (visible.count + Self.pageSize - 1) / Self.pageSize)
        let current = min(page ?? DexScrollPager.page(containing: returnAnchor, in: visible.map(\.collectionID),
                                                      pageSize: Self.pageSize),
                          pageCount - 1)
        let slice = Array(visible.dropFirst(current * Self.pageSize).prefix(Self.pageSize))

        VStack(alignment: .leading, spacing: 6) {
            header(all)
            if visible.isEmpty {
                emptySearchResults
            } else {
                grid(slice)
                    .background(ScrollWheelPager { step in
                        let next = DexScrollPager.pageAfterScroll(current: current, pageCount: pageCount, step: step)
                        if next != current { page = next; selectedID = nil }
                    })
                footer(slice, current: current, pageCount: pageCount)
            }
        }
        .onChange(of: searchText) { page = 0; selectedID = nil }
        .onChange(of: shinyOnly) { page = 0; selectedID = nil }
        .onChange(of: favoritesOnly) { page = 0; selectedID = nil }
        .onChange(of: evolutionFamily) { page = 0; selectedID = nil }
        .onChange(of: sortOption) { page = 0; selectedID = nil }
        .onChange(of: selectedRarity) { page = 0; selectedID = nil }
        .task { await store.backfillMissingDexNames() }
        // The rarities' totals ("120/430") read the hatch index, cached once loaded.
        .task { await store.loadHatchIndex() }
        // The other pages' stills, made in the background so turning a page shows its Pokémon at once (each
        // still comes from a GIF download the first time). Restarts when the page or the filters change.
        .task(id: StillPrefetchKey(page: current, ids: visible.map(\.collectionID)), priority: .utility) {
            let order = DexScrollPager.prefetchOrder(count: visible.count, current: current, pageSize: Self.pageSize)
            await SpriteStore.shared.warmStills(order.map { index in
                let species = visible[index]
                // As `DexSpeciesCell` draws it: shiny only for a species with a single appearance.
                return SpriteStore.StillRequest(speciesID: species.id,
                                                shiny: species.isShiny && !PokemonForm.hasForms(speciesID: species.id))
            })
        }
    }

    private var emptySearchResults: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(store.l.noSearchResults)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Button(store.l.clearFilters) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    onResetFilters()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(_ all: [CompanionStore.DexSpecies]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // What is collected and what is left: species, then every form of every species. Graduated ones, as the
            // games' Owned, and how many more were only seen (raised, or released), as their Seen.
            let owned = store.graduatedCollectionProgress
            let seen = store.collectionProgress.species - owned.species
            let totals = store.speciesTotalsByRarity
            HStack(spacing: 6) {
                Text(store.l.dexTitle).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                Spacer(minLength: 4)
                Text(store.l.dexSpeciesProgress(owned.species, of: owned.speciesTotal))
                if seen > 0 {
                    Text("·").foregroundStyle(.tertiary)
                    Label(store.l.dexSeenOnly(seen), systemImage: "eye").labelStyle(.titleAndIcon)
                        .hoverTip(store.l.dexSeenNotGraduated)
                }
                Text("·").foregroundStyle(.tertiary)
                Text(store.l.formsCollected(owned.forms, of: owned.formsTotal))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(0.8)
            WrappingHStack(spacing: 4, lineSpacing: 4) {
                ForEach(rarityDisplayOrder, id: \.self) { r in
                    let count = all.lazy.filter { $0.rarity == r }.count
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedRarity = (selectedRarity == r) ? nil : r
                            page = 0
                            selectedID = nil
                        }
                    } label: {
                        RarityTally(label: store.l.rarityLabel(r), count: count, total: totals?[r],
                                    color: rarityColor(r), isSelected: selectedRarity == r)
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0)
                    .hoverTip(store.l.dexFilterHint)
                }
            }
        }
    }

    private func grid(_ slice: [CompanionStore.DexSpecies]) -> some View {
        let formCounts = Dictionary(uniqueKeysWithValues: slice.lazy
            .filter { PokemonForm.hasForms(speciesID: $0.id) }
            .map { ($0.id, store.state.collectedForms(speciesID: $0.id).count) })
        let graduated = store.graduatedSpeciesIDs
        let catchCounts = store.dexCatchCounts
        return VStack(spacing: Self.spacing) {
            ForEach(0..<Self.rows, id: \.self) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(0..<Self.columns, id: \.self) { col in
                        let i = row * Self.columns + col
                        if i < slice.count {
                            let sp = slice[i]
                            DexSpeciesCell(store: store, species: sp,
                                           isSelected: selectedID == sp.collectionID,
                                           isRepresentative: store.isRepresentative(sp),
                                           formCount: formCounts[sp.id],
                                           isSeenOnly: !graduated.contains(sp.id),
                                           catchCount: catchCounts[sp.id] ?? 0) {
                                selectedID = sp.collectionID
                                onSelectSpecies(sp)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func footer(_ slice: [CompanionStore.DexSpecies],
                        current: Int, pageCount: Int) -> some View {
        HStack(spacing: 8) {
            if let sel = slice.first(where: { $0.collectionID == selectedID }) {
                // 칸은 번호·스프라이트·이름만 보여주므로 희귀도가 선택으로 얻는 정보다.
                Text("#\(sel.id) \(sel.name) · \(store.l.rarityLabel(sel.rarity))")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                if !PokemonForm.hasForms(speciesID: sel.id) {
                    let isRepresentative = store.isRepresentative(sel)
                    RepresentativeFooterButton(localization: store.l,
                                               isRepresentative: isRepresentative) {
                        _ = store.setRepresentativeSpeciesID(isRepresentative ? nil : sel.id)
                    }
                }
            }
            Spacer(minLength: 4)
            if pageCount > 1 {
                // 넓힌 히트 영역의 여백이 곧 셰브론↔숫자 간격이다. 바깥 음수 패딩으로 글리프를
                // 원래 자리(우측 끝)에 두고, 넘친 히트 영역은 팝오버 여백 쪽으로 뻗게 한다.
                HStack(spacing: 0) {
                    DexPageButton(forward: false, label: store.l.dexPagePrev) {
                        page = max(0, current - 1); selectedID = nil
                    }
                    .disabled(current == 0)
                    Text("\(current + 1) / \(pageCount)")
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(store.l.dexPageLabel(current + 1, pageCount))
                    DexPageButton(forward: true, label: store.l.dexPageNext) {
                        page = min(pageCount - 1, current + 1); selectedID = nil
                    }
                    .disabled(current == pageCount - 1)
                }
                .padding(.horizontal, -DexPageButton.edgeInset)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .frame(height: 18)
    }
}

/// Scrollable species + individual page. A Pokédex species may aggregate several catches, so the
/// picker selects the exact persisted profile while the immutable PokéAPI section stays shared.
@MainActor
struct PokemonDetailView: View {
    let store: CompanionStore
    let species: CompanionStore.DexSpecies
    let onBack: () -> Void
    private let spriteStore: SpriteStore
    @State private var selectedInstanceID = ""
    @State private var selectedForm: PokemonForm?
    /// The slot of the dungeon loop being changed (`LoopEditor`).
    @State private var editingLoopSlot: Int?
    @State private var selectedShiny: Bool?
    /// The look the header shows, picked among the costumes (`CostumeEntry.key`, `plainLook` for none); nil shows the
    /// individual's own.
    @State private var shownCostume: String?
    @State private var tab: DetailTab
    private static let plainLook = ""

    /// Opens another page of the family (the target, then this page as it is shown, for Back).
    private let onOpenDexPage: ((PopoverNavigation.DexPage, PopoverNavigation.DexPage) -> Void)?
    /// Opens the costumed collection.
    private let onOpenCostumes: (() -> Void)?

    init(store: CompanionStore, species: CompanionStore.DexSpecies,
         onBack: @escaping () -> Void, selectedShiny: Bool? = nil,
         spriteStore: SpriteStore = .shared, initialForm: PokemonForm? = nil,
         onOpenDexPage: ((PopoverNavigation.DexPage, PopoverNavigation.DexPage) -> Void)? = nil,
         onOpenCostumes: (() -> Void)? = nil, initialTab: DetailTab = .individual) {
        self.store = store
        self.species = species
        self.onBack = onBack
        self.spriteStore = spriteStore
        self.onOpenDexPage = onOpenDexPage
        self.onOpenCostumes = onOpenCostumes
        _tab = State(initialValue: initialTab)
        _selectedShiny = State(initialValue: selectedShiny)
        // A family page opens in the form it was seen in, when this species was caught in it (`displayedSpecies`).
        _selectedForm = State(initialValue: initialForm.flatMap { PokemonForm.resolved(speciesID: species.id, form: $0) })
    }

    private var formSpecies: [CompanionStore.DexSpecies] {
        store.formSpecies(speciesID: species.id)
    }

    private var displayedSpecies: CompanionStore.DexSpecies {
        // A battle form won is shown as the species' cover in that form: no individual ever graduated in it.
        if let selectedForm, BattleForms.form(speciesID: species.id, form: selectedForm) != nil {
            var cover = store.dexCover(for: species)
            cover.form = selectedForm
            return cover
        }
        return formSpecies.first { $0.form == selectedForm } ?? store.dexCover(for: species)
    }

    private var allIndividuals: [DexEntry] {
        store.pokemonIndividuals(speciesID: species.id, form: displayedSpecies.form)
    }
    /// Shiny unless Normal is picked: a species caught shiny opens shiny, even when its latest catch is normal. Normal
    /// can always be looked at, as a preview when none was caught in this form; shiny only once caught shiny.
    private var displayedShiny: Bool {
        if let selectedShiny, !selectedShiny || displayedSpecies.isShiny { return selectedShiny }
        return displayedSpecies.isShiny
    }
    private var individuals: [DexEntry] {
        allIndividuals.filter { $0.isShiny == displayedShiny }
    }
    private var individual: DexEntry? {
        individuals.first { $0.id == selectedInstanceID } ?? individuals.first
    }

    /// The page's tabs, under the identity and the evolution line.
    enum DetailTab: Hashable, CaseIterable { case individual, battle, species, moves, costumes }

    /// The individual whose dungeon moves the Battle tab edits: one graduated as this species, able to join a team.
    private var loopIndividual: DexEntry? {
        guard let individual, individual.finalID == species.id,
              store.dungeonCandidates.contains(where: { $0.id == individual.id }) else { return nil }
        return individual
    }

    /// Only the tabs with something to show: no Battle tab without a team member, no Costumes tab without costumes.
    private var shownTabs: [DetailTab] {
        DetailTab.allCases.filter { tab in
            switch tab {
            case .battle: loopIndividual != nil
            case .costumes: !speciesCostumes.isEmpty
            default: true
            }
        }
    }

    private func tabTitle(_ tab: DetailTab) -> String {
        switch tab {
        case .individual: store.l.dexTabIndividual
        case .battle: store.l.dexTabBattle
        case .species: store.l.dexTabSpecies
        case .moves: store.l.dexTabMoves
        case .costumes: store.l.dexTabCostumes
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onBack) {
                    Label(store.l.back, systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("#\(species.id)").font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if PokemonForm.hasForms(speciesID: species.id) { formPicker }
                    if !store.shownBattleForms(speciesID: species.id).isEmpty { battleFormPicker }
                    if species.id == PikachuCostume.speciesID { costumePicker }
                    // A form caught shiny only still shows its normal look: one of Vivillon's patterns caught shiny
                    // had no way back to its usual colors.
                    if displayedSpecies.isShiny { appearancePicker }
                    identityHeader
                    // The rest in tabs under the identity: the page ran over six screens (#183).
                    let tabs = shownTabs
                    if tabs.count > 1 {
                        PillPicker(selection: Binding(get: { tabs.contains(tab) ? tab : tabs[0] }, set: { tab = $0 }),
                                   options: tabs.map { ($0, tabTitle($0)) })
                    }
                    let current = tabs.contains(tab) ? tab : tabs[0]
                    if current == .individual {
                        if individuals.count > 1 { individualPicker }
                        if individuals.isEmpty {
                            Text(store.l.dexAppearancePreview).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if current == .costumes { costumeSection }
                    // The displayed form's own stats, size, abilities and moves (an Alolan Vulpix's, not a Kanto one's).
                    if current == .costumes {
                        EmptyView()
                    } else if let details = store.pokemonDetails(speciesID: species.id, form: displayedSpecies.form) {
                        switch current {
                        case .individual:
                            if let individual, let profile = individual.profile {
                                individualSection(entry: individual, profile: profile, details: details)
                            } else {
                                baseStatsSection(details)
                            }
                            if let individual, let record = individual.raising {
                                RaisingRecordCard(record: record, entry: individual, store: store)
                            }
                        case .battle:
                            // R4: the moves it fights with in the dungeons, as on the team screen.
                            if let individual = loopIndividual {
                                LoopEditor(store: store, entry: individual, dungeon: nil, editingSlot: $editingLoopSlot,
                                           asCard: true)
                                    .onChange(of: individual.id) { _, _ in editingLoopSlot = nil }
                            }
                        case .species:
                            speciesSection(details)
                            baseStatsSection(details)
                        case .moves:
                            movesSection(details)
                        case .costumes:
                            EmptyView()
                        }
                    } else if store.failedToLoadPokemonDetails(speciesID: species.id, form: displayedSpecies.form) {
                        VStack(spacing: 8) {
                            Text(store.l.pokemonDetailsUnavailable).foregroundStyle(.secondary)
                            Button(store.l.retry) {
                                Task { await store.loadPokemonDetails(speciesID: species.id, form: displayedSpecies.form) }
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else {
                        HStack { Spacer(); ProgressView(); Text(store.l.loadingPokemonDetails); Spacer() }
                            .foregroundStyle(.secondary).padding(.vertical, 30)
                    }
                }
                .padding(.bottom, 8)
                .reservesScrollerLane()
            }
        }
        .task {
            if selectedForm == nil { selectedForm = displayedSpecies.form }
            if selectedInstanceID.isEmpty { selectedInstanceID = individuals.first?.id ?? "" }
        }
        // Again whenever the form picker shows a form with data of its own.
        .task(id: PokemonForm.detailsID(speciesID: species.id, form: displayedSpecies.form)) {
            await store.loadPokemonDetails(speciesID: species.id, form: displayedSpecies.form)
        }
    }

    /// The species' battle forms (2026-11-02): won ones open their stats, missing ones fade and say which dungeon gives
    /// them. The usual form comes first for a species with no other form to go back to.
    private var battleFormPicker: some View {
        let l = store.l
        let forms = store.shownBattleForms(speciesID: species.id)
        let won = Set(store.wonBattleForms(speciesID: species.id).map(\.key))
        let battleSelected = BattleForms.form(speciesID: species.id, form: selectedForm)
        return VStack(alignment: .leading, spacing: 6) {
            Text(l.battleFormsWon(won.count, of: forms.count)).font(.callout.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 4), spacing: 4) {
                if !PokemonForm.hasForms(speciesID: species.id) {
                    battleCell(label: l.battleFormUsual, form: nil, owned: true, selected: battleSelected == nil, hint: nil)
                }
                ForEach(forms, id: \.key) { form in
                    // Its own form named when the species has several: Tatsugiri's three Megas.
                    battleCell(label: PokemonForm.label(speciesID: species.id, form: form.form, language: store.language)
                                   ?? l.battleFormLabel(form), form: form.form, owned: won.contains(form.key),
                               selected: battleSelected == form, hint: won.contains(form.key) ? nil : l.battleFormSource(form))
                }
            }
        }
    }

    private func battleCell(label: String, form: PokemonForm?, owned: Bool, selected: Bool, hint: String?) -> some View {
        Button {
            selectedForm = form ?? PokemonForm.forms(speciesID: species.id).first
            selectedInstanceID = ""
            selectedShiny = nil
        } label: {
            VStack(spacing: 1) {
                SpriteView(speciesID: species.id, size: 36, form: form).frame(width: 36, height: 36)
                Text(label).font(.system(size: 11, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                if let hint {
                    Text(hint).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
                }
            }
            .opacity(owned ? 1 : 0.4)
            .frame(maxWidth: .infinity).padding(.vertical, 3)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .overlay { if selected { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 1.5) } }
        }
        .buttonStyle(.plain)
        .disabled(!owned)
        .accessibilityLabel(label)
    }

    /// Unown's 28 letters fill seven columns and short labels six (Arceus's types), one line each. Longer names
    /// ("Motif Continental", Alcremie's sweets) take four columns and two lines: in six, they were cut short.
    static func formPickerColumns(formCount: Int, longestLabel: Int) -> Int {
        guard formCount > 8, longestLabel <= 8 else { return min(formCount, 4) }
        return longestLabel <= 2 ? 7 : 6
    }

    private var formPicker: some View {
        let forms = formSpecies
        let allForms = PokemonForm.forms(speciesID: species.id)
        let selected = displayedSpecies.form
        let labels = allForms.map { PokemonForm.label(speciesID: species.id, form: $0, language: store.language) ?? "" }
        let columns = Self.formPickerColumns(formCount: allForms.count, longestLabel: labels.map(\.count).max() ?? 0)
        let source = PokemonForm.unlockSource(speciesID: species.id)
        let unlockedTypes = source == .legendaryType ? store.state.silvallyMemoryTypes : store.state.plateTypes
        return VStack(alignment: .leading, spacing: 6) {
            Text(store.l.formsCollected(forms.count, of: allForms.count)).font(.callout.weight(.semibold))
            switch source {
            case .gymBadge?: Text(store.l.plateFormsHint).font(.caption).foregroundStyle(.secondary)
            case .legendaryType?: Text(store.l.memoryFormsHint).font(.caption).foregroundStyle(.secondary)
            case nil: EmptyView()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: columns), spacing: 4) {
                ForEach(allForms, id: \.self) { form in
                    let owned = forms.first { $0.form == form }
                    let label = PokemonForm.label(speciesID: species.id, form: form, language: store.language) ?? ""
                    let plate = PokemonForm.unlockType(speciesID: species.id, form: form)
                    Button {
                        selectedForm = form
                        selectedInstanceID = ""
                        selectedShiny = nil
                    } label: {
                        VStack(spacing: 0) {
                            VStack(spacing: 0) {
                                SpriteView(speciesID: species.id, size: 36,
                                           shiny: owned?.isShiny == true, form: form)
                                    .frame(width: 36, height: 36)
                                    .overlay(alignment: .topTrailing) {
                                        if owned?.isShiny == true { Text("✨").font(.system(size: 11)) }
                                    }
                                // Wide grids hold short labels (letters, types); longer names wrap on two lines,
                                // three for Alcremie's longest sweets.
                                Text(label).font(.system(size: 11, weight: .semibold))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(columns > 4 ? 1...1 : 2...3)
                                    .minimumScaleFactor(columns > 4 ? 0.6 : 0.8)
                                    .padding(.horizontal, 2)
                            }
                            // Faded until caught, the name still readable on a light card.
                            .opacity(owned == nil ? 0.4 : 1)
                            // What unlocks the form, faded until won: the badge that gives Arceus's Plate (one region
                            // claimed), or the type of the legendary that gives Silvally's Memory.
                            if let plate {
                                Group {
                                    if source == .gymBadge {
                                        ItemIconView(kind: plate.badgeItem, size: 14)
                                    } else {
                                        Circle().fill(plate.color).frame(width: 9, height: 9).padding(2.5)
                                    }
                                }
                                .opacity(unlockedTypes.contains(plate) ? 1 : 0.35)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                        .background(owned.map { store.isRepresentative($0) } == true
                                    ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            if selected == form {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(owned == nil)
                    .accessibilityLabel("\(species.name) [\(label)]")
                    .accessibilityValue(owned == nil
                                        ? [store.l.formNotCollected,
                                           plate.map { source == .gymBadge ? store.l.itemName($0.badgeItem) : store.l.typeName($0) }]
                                            .compactMap { $0 }.joined(separator: ", ")
                                        : (owned?.isShiny == true ? store.l.dexShinyLabel : ""))
                    .accessibilityAddTraits(selected == form ? .isSelected : [])
                }
            }
        }
        .task(id: species.id) { await store.loadFormNames(PokemonForm.nameResources(speciesID: species.id)) }
    }

    /// Pikachu's costumes: the ones won in color, the others faded; tapping one makes Pikachu wear it everywhere.
    private var costumePicker: some View {
        let l = store.l
        let owned = store.state.pikachuCostumes
        let equipped = store.state.equippedPikachuCostume
        let choices: [PikachuCostume?] = [nil] + PikachuCostume.allCases.map { $0 }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(l.pikachuCostumesTitle).font(.callout.weight(.semibold))
                Spacer()
                Text(l.pikachuCostumesProgress(owned.count, of: PikachuCostume.allCases.count))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(l.pikachuCostumesHint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 6), spacing: 4) {
                ForEach(choices, id: \.self) { costume in
                    let isOwned = costume.map(owned.contains) ?? true
                    let name = costume.map(l.pikachuCostumeName) ?? l.pikachuNoCostume
                    Button {
                        store.equipPikachuCostume(costume)
                    } label: {
                        VStack(spacing: 0) {
                            SpriteView(speciesID: PikachuCostume.speciesID, size: 36,
                                       form: costume?.form ?? PikachuCostume.plain)
                                .frame(width: 36, height: 36)
                            Text(name).font(.system(size: 10, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 2)
                        }
                        .opacity(isOwned ? 1 : 0.25)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                        .overlay {
                            if costume == equipped {
                                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 1.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isOwned)
                    .hoverTip(name)
                    .accessibilityLabel(name)
                    .accessibilityAddTraits(costume == equipped ? .isSelected : [])
                }
            }
        }
    }

    /// The species in its type color, as Home's hero card (a legendary gets the whole event).
    private var identityHeader: some View {
        let species = displayedSpecies
        let typeColors = PokemonTypeData.types(forSpeciesID: species.id, form: species.form).prefix(2).map(\.color)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                SpriteView(speciesID: species.id, size: 96, animated: true,
                           shiny: headerLook.shiny, spriteStore: spriteStore, form: headerLook.form, bottomAligned: true)
                    .frame(width: 100, height: 100)
                    .background(alignment: .bottom) {
                        Ellipse().fill(Color.black.opacity(0.18)).frame(width: 60, height: 10).blur(radius: 2)
                    }
                VStack(alignment: .leading, spacing: 5) {
                    // The rarity above the name, as on Home: a long form name ("Vivillon [Continental Pattern]")
                    // wraps whole instead of being cut beside the badge.
                    if species.rarity == .legendary {
                        LegendaryBadge(text: store.l.rarityLabel(species.rarity).uppercased()).fixedSize()
                    } else {
                        Badge(store.l.rarityLabel(species.rarity).uppercased(), tint: .rarity(species.rarity))
                            .lineLimit(1).fixedSize()
                    }
                    Text(species.name).font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                    let types = PokemonTypeData.typeNames(speciesID: species.id, form: species.form,
                                                          fallback: store.pokemonDetails(speciesID: species.id, form: species.form)?.types)
                    if !types.isEmpty {
                        TypeBadges(types: types, language: store.language, size: 11,
                                   horizontalPadding: 7, verticalPadding: 2)
                    }
                    if displayedShiny { Text("✨ \(store.l.dexShinyLabel)").font(.callout) }
                    if let individual, store.isActiveDexEntry(individual) { Text(store.l.dexRaising).font(.callout).foregroundStyle(Color.accentColor) }
                    let isRepresentative = store.isRepresentative(species)
                    HStack(spacing: 6) {
                        RepresentativeFooterButton(localization: store.l,
                                                   isRepresentative: isRepresentative) {
                            _ = store.setRepresentativeSpeciesID(isRepresentative ? nil : species.id,
                                                                 form: species.form)
                        }
                        if store.canFavorite(speciesID: species.id) || store.isFavorite(speciesID: species.id) {
                            favoriteButton
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            familyLine(species)
        }
        .heroCard(colors: typeColors.isEmpty ? [.gray] : Array(typeColors), legendary: species.rarity == .legendary)
    }

    // MARK: Costumes (the owner, 2026-11-16: "sur la fiche d'un pokémon tous ses costumes")

    /// The costumes of Pokémon GO this species wears in the form shown (`CostumeCatalog`), in the catalog's order.
    private var speciesCostumes: [CostumeEntry] {
        let form = displayedSpecies.form
        return CostumeCatalog.entries.filter {
            $0.speciesID == species.id && CostumeCatalog.entry(code: $0.code, speciesID: species.id, form: form) == $0
        }
    }

    /// The header's look: a costume picked below, else the individual's costume at this species, else the form.
    private var headerLook: (form: PokemonForm?, shiny: Bool) {
        let form = displayedSpecies.form
        switch shownCostume {
        case Self.plainLook?: return (form, displayedShiny)
        case let key?:
            // A costume of another form picked before the form changed: the individual's look.
            guard let entry = CostumeCatalog.byKey[key], speciesCostumes.contains(entry) else { return (form, displayedShiny) }
            return (entry.displayForm, displayedShiny && store.ownedCostumeKeys().shiny.contains(key))
        case nil:
            guard let individual, individual.costume != nil else { return (form, displayedShiny) }
            return (individual.spriteForm(at: species.id), displayedShiny)
        }
    }

    /// Every costume of the species, those collected in color and the others as silhouettes; one collected shows in the
    /// header, on the individual wearing it when there is one.
    private var costumeSection: some View {
        let l = store.l
        let owned = store.ownedCostumeKeys()
        let costumes = speciesCostumes
        let have = costumes.filter { owned.all.contains($0.key) }.count
        let worn = individual.flatMap { $0.costume == nil ? nil : CostumeCatalog.entry(code: $0.costume!, speciesID: species.id, form: $0.form)?.key }
        let current = shownCostume ?? worn ?? Self.plainLook
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label(l.costumesTitle.uppercased(), systemImage: "theatermasks.fill")
                    .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.6).foregroundStyle(.secondary)
                Text(l.costumesOfSpecies(have, of: costumes.count)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let onOpenCostumes {
                    Button(l.costumesSeeAll, action: onOpenCostumes)
                        .buttonStyle(.borderless).controlSize(.small).font(.caption.weight(.semibold))
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 54, maximum: 64), spacing: 4)], alignment: .leading, spacing: 4) {
                costumeCell(key: Self.plainLook, form: displayedSpecies.form, label: l.costumePlainLook,
                            owned: true, shiny: false, selected: current == Self.plainLook, hint: l.costumePlainLook)
                ForEach(costumes, id: \.key) { entry in
                    let isOwned = owned.all.contains(entry.key)
                    costumeCell(key: entry.key, form: entry.displayForm, label: l.monthName(entry.month), owned: isOwned,
                                shiny: displayedShiny && owned.shiny.contains(entry.key), selected: current == entry.key,
                                hint: l.costumeCellHint(month: entry.month, owned: isOwned))
                }
            }
            if have == 0 {
                Text(l.costumesSpeciesHint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .detailCard()
    }

    private func costumeCell(key: String, form: PokemonForm?, label: String, owned: Bool, shiny: Bool, selected: Bool,
                             hint: String) -> some View {
        Button {
            shownCostume = key
            // The individual wearing it, when one was caught in it.
            if let entry = CostumeCatalog.byKey[key], let wearer = individuals.first(where: { $0.costume == entry.code }) {
                selectedInstanceID = wearer.id
            }
        } label: {
            VStack(spacing: 1) {
                // One species: each costume fills its cell, an Eevee as big as a Snorlax.
                SpriteView(speciesID: species.id, size: 40, shiny: shiny, spriteStore: spriteStore, form: form,
                           isSilhouette: !owned)
                    .frame(width: 42, height: 42)
                Text(label).font(.system(size: 9, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 2)
            }
            .opacity(owned ? 1 : 0.45)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 1.5) }
            }
        }
        .buttonStyle(.plain)
        .disabled(!owned)
        .hoverTip(hint)
        .accessibilityLabel(hint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// What the species evolves from and into, under its identity like the line on Home's card. A caught one opens
    /// its page in the same form, and Back comes back here; one not caught is a silhouette.
    @ViewBuilder
    private func familyLine(_ shown: CompanionStore.DexSpecies) -> some View {
        let family = store.dexFamily(speciesID: shown.id, form: shown.form)
        let line = Self.lineWithoutPage(family.nodes)
        if !line.isEmpty {
            let dex = store.dexSpecies
            // The species itself is the page already open.
            let links = Dictionary(dex.filter { $0.id != shown.id }.map { ($0.id, $0.collectionID) },
                                   uniquingKeysWith: { first, _ in first })
            let names = Dictionary(dex.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            EvoLineView(nodes: line, mysteryLabel: store.l.unknownNextEvolution, language: store.language,
                        thumb: 34, shiny: displayedShiny,
                        shinyStages: store.dexFamilyShinies(family), wrapsBranches: true, names: names,
                        maxWidth: PopoverMetrics.scrollContentWidth - Design.cardPadding * 2, form: family.form,
                        nameFontSize: 10, dexLinks: links,
                        onOpenDexEntry: { target in
                            onOpenDexPage?(.init(collectionID: target, form: family.form),
                                           .init(collectionID: species.collectionID, form: shown.form))
                        })
        }
    }

    /// The page's family without the page's own species: the header shows it already (the owner, 2026-11-17).
    nonisolated static func lineWithoutPage(_ nodes: [EvoLineItem]) -> [EvoLineItem] {
        nodes.filter { $0.state != .current }
    }

    private var appearancePicker: some View {
        PillPicker(selection: Binding(get: { displayedShiny }, set: { selectedShiny = $0; selectedInstanceID = "" }),
                   options: [(false, store.l.dexNormalLabel), (true, "✨ \(store.l.dexShinyLabel)")])
            .accessibilityLabel(store.l.dexAppearance)
    }

    private var individualPicker: some View {
        Picker(store.l.pokemonIndividual, selection: Binding(
            get: { individual?.id ?? "" }, set: { selectedInstanceID = $0; shownCostume = nil })) {
            ForEach(Array(individuals.enumerated()), id: \.element.id) { index, entry in
                Text(individualLabel(entry, index: index)).tag(entry.id)
            }
        }
        .pickerStyle(.menu)
    }

    private func individualLabel(_ entry: DexEntry, index: Int) -> String {
        let appearance = entry.isShiny ? "✨ \(store.l.dexShinyLabel)" : store.l.dexNormalLabel
        let date = entry.caughtAt.map {
            $0.formatted(Date.FormatStyle(date: .numeric, time: .omitted)
                .locale(Locale(identifier: store.language.rawValue)))
        } ?? (store.isActiveDexEntry(entry) ? store.l.dexRaising : "-")
        let costume = entry.costume.flatMap { CostumeCatalog.entry(code: $0, speciesID: species.id, form: entry.form) }
            .map { " · 🎭 \(store.l.monthName($0.month))" } ?? ""
        return "#\(index + 1) · \(appearance)\(costume) · Lv. \(entry.profile?.level ?? 5) · \(date)"
    }

    /// Likes this species, or unlikes it: the ♥ filter of the Pokédex, the catch log, the teams and the Capsules.
    private var favoriteButton: some View {
        let liked = store.isFavorite(speciesID: species.id)
        let label = liked ? store.l.favoriteRemove : store.l.favoriteAdd
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { store.toggleFavorite(speciesID: species.id) }
        } label: {
            // Filled or not says it, not the pink alone.
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(liked ? Color.pink : Color.secondary)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverTip(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(liked ? .isSelected : [])
    }

    private func individualSection(entry: DexEntry, profile: PokemonProfile,
                                   details: PokemonDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                detailTitle(store.l.pokemonIndividual)
                Spacer()
            }
            HStack(spacing: 12) {
                valuePair(store.l.level, "\(profile.level)")
                valuePair(store.l.gender, store.l.genderLabel(profile.gender))
                valuePair(store.l.nature, entry.nature?.name(store.language) ?? "-")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(store.l.ability).font(.system(size: 11)).foregroundStyle(.secondary)
                if let name = profile.abilityName {
                    PokemonNameLabel(.ability, name, language: store.language,
                                     suffix: profile.abilityIsHidden ? " · " + store.l.hiddenAbility : "")
                        .font(.callout.weight(.semibold))
                } else {
                    Text("-").font(.callout.weight(.semibold))
                }
            }
            statsSection(PokemonStatCalculator.stats(details: details, profile: profile, nature: entry.nature))
            detailTitle(store.l.activeMoves)
            if profile.moves.isEmpty {
                Text(store.l.noLevelMoves).font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(profile.moves) { move in
                    HStack {
                        PokemonNameLabel(.move, move.name, language: store.language)
                        Spacer()
                        Text("Lv. \(move.learnedAtLevel)").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
        .detailCard()
    }

    private func baseStatsSection(_ details: PokemonDetails) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            detailTitle(store.l.baseStats)
            ForEach(PokemonStatCalculator.order, id: \.self) { stat in
                if let value = details.baseStats[stat] {
                    statRow(name: stat, value: value, iv: nil, scaleMaximum: 300)
                }
            }
        }
        .detailCard()
    }

    private func statsSection(_ stats: [PokemonComputedStat]) -> some View {
        let scaleMaximum = PokemonStatCalculator.displayScaleMaximum(for: stats.map(\.value))
        return VStack(alignment: .leading, spacing: 5) {
            detailTitle(store.l.actualStats)
            ForEach(stats) { stat in
                statRow(name: stat.name, value: stat.value, iv: stat.iv, scaleMaximum: scaleMaximum)
            }
        }
    }

    private func statRow(name: String, value: Int, iv: Int?, scaleMaximum: Int) -> some View {
        let color = Self.statColor(name)
        return HStack(spacing: 6) {
            Text(store.l.statLabel(name)).frame(width: 74, alignment: .leading)
            Capsule().fill(Color.primary.opacity(0.08))
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule().fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading,
                                                      endPoint: .trailing))
                            .frame(width: geo.size.width * min(1, Double(value) / Double(max(1, scaleMaximum))))
                    }
                }
                .frame(height: 7)
            Text("\(value)").font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                .frame(width: 30, alignment: .trailing)
            if let iv { Text("IV \(iv)").foregroundStyle(.secondary).frame(width: 38, alignment: .trailing) }
        }
        .font(.system(size: 12))
    }

    /// Each stat in its color from the games' summary screens.
    static func statColor(_ name: String) -> Color {
        let hex: UInt32
        switch name {
        case "hp": hex = 0xFF5959
        case "attack": hex = 0xF5AC78
        case "defense": hex = 0xFAE078
        case "special-attack": hex = 0x9DB7F5
        case "special-defense": hex = 0xA7DB8D
        case "speed": hex = 0xFA92B2
        default: hex = 0xAAAAAA
        }
        return Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                     blue: Double(hex & 0xFF) / 255)
    }

    private func speciesSection(_ details: PokemonDetails) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            detailTitle(store.l.speciesData)
            HStack(spacing: 14) {
                valuePair(store.l.height, String(format: "%.1f m", Double(details.height) / 10))
                valuePair(store.l.weight, String(format: "%.1f kg", Double(details.weight) / 10))
                valuePair(store.l.baseStatTotal, "\(details.baseStatTotal)")
            }
            detailTitle(store.l.possibleAbilities)
            PokemonNameLabel(items: details.abilities.map { option in
                PokemonNameItem(resource: .init(kind: .ability, name: option.name),
                                suffix: option.isHidden ? " (\(store.l.hidden))" : "")
            }, language: store.language)
            .font(.callout).foregroundStyle(.secondary)
        }
        .detailCard()
    }

    private func movesSection(_ details: PokemonDetails) -> some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            detailTitle(store.l.completeMoveList(details.moves.count))
            ForEach(details.moves) { move in
                HStack(alignment: .firstTextBaseline) {
                    PokemonNameLabel(.move, move.name, language: store.language)
                    Spacer()
                    Text(move.learnMethods.map(store.l.moveMethod).uniqued().joined(separator: " · "))
                        .foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
                .font(.callout)
                Divider()
            }
        }
        .detailCard()
    }

    private func detailTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.6)
            .foregroundStyle(.secondary)
    }

    private func valuePair(_ label: String, _ value: String, suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value + (suffix.map { " · \($0)" } ?? "")).font(.callout.weight(.semibold))
        }
    }

}

private extension View {
    func detailCard() -> some View {
        designCard()
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        reduce(into: []) { result, value in if !result.contains(value) { result.append(value) } }
    }
}

/// 도감 한 칸 — 도감 번호 + 스프라이트 + 종 이름. 종 정보만 담는다(성격·획득 횟수는 로그의 몫).
/// 정적 스프라이트만 쓴다(animated 생략) — 한 페이지 16칸을 GIF 로 동시 재생하면 CPU 가 안 된다.
@MainActor
private struct DexSpeciesCell: View {
    let store: CompanionStore
    let species: CompanionStore.DexSpecies
    let isSelected: Bool
    let isRepresentative: Bool
    /// Collected forms, nil for species with a single appearance.
    let formCount: Int?
    /// Seen (raised, or released) but never graduated: it counts for no achievement yet.
    var isSeenOnly = false
    /// How many records reached this species (`CompanionStore.dexCatchCounts`): "×N" from two.
    var catchCount = 0
    let onTap: () -> Void
    @State private var isHovered = false

    private var formTotal: Int { PokemonForm.forms(speciesID: species.id).count }

    /// The Pokémon the cell shows, the one its page opens on: shiny in the form caught shiny.
    private var cover: CompanionStore.DexSpecies { store.dexCover(for: species) }

    /// The cell's tint: the species' first type in the form the cell shows.
    private var typeColor: Color {
        PokemonTypeData.types(forSpeciesID: species.id, form: cover.form).first?.color ?? .gray
    }

    /// Larger thumbnails remain static so a full page does not animate concurrently.
    private static let thumb: CGFloat = 56

    var body: some View {
        Button(action: onTap) { cell }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .hoverTip(tooltip)
        .accessibilityLabel(tooltip)
        .contextMenu {
            if formCount != nil {
                Button(store.l.chooseForm, action: onTap)
            } else {
                Button {
                    _ = store.setRepresentativeSpeciesID(isRepresentative ? nil : species.id)
                } label: {
                    Label(isRepresentative ? store.l.representativeFollowCurrent
                                           : store.l.representativeSet,
                          systemImage: isRepresentative ? "arrow.triangle.2.circlepath" : "star")
                }
            }
        }
    }

    private var types: [PokemonType] { PokemonTypeData.types(forSpeciesID: species.id, form: cover.form) }
    private var displayName: String { formCount.map { "\(species.name) \($0)/\(formTotal)" } ?? species.name }

    private func sprite(_ size: CGFloat) -> some View {
        let cover = cover
        return SpriteView(speciesID: species.id, size: size, shiny: cover.isShiny, form: cover.form, sameScale: true)
            .frame(width: size, height: size)
    }

    /// A neutral card, a hairline in the type color when selected; hover lifts it a little.
    private func neutralCard<Content: View>(radius: CGFloat = 11, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.primary.opacity(isHovered ? 0.08 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(isSelected ? typeColor : Color.primary.opacity(0.07), lineWidth: isSelected ? 1.5 : 1))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(isRepresentative ? Color.accentColor.opacity(0.12) : .clear).allowsHitTesting(false))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .scaleEffect(isHovered ? 1.03 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    /// 번호 색 = 희귀도 — "전체" 보기에서도 칸마다 희귀도가 보인다. The star marks the representative.
    private var plainNumber: some View {
        HStack(spacing: 2) {
            Text("#\(species.id)")
            if isRepresentative { Image(systemName: "star.fill").font(.system(size: 7, weight: .bold)) }
        }
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .foregroundStyle(rarityColor(species.rarity))
        .padding(.horizontal, 4).padding(.vertical, 1)
        .background(Capsule().fill(rarityColor(species.rarity).opacity(0.16)))
    }

    private var typeDots: some View {
        HStack(spacing: 3) {
            ForEach(types.prefix(2), id: \.self) { type in Circle().fill(type.color).frame(width: 9, height: 9) }
        }
    }

    private var seenMark: some View {
        Group {
            if isSeenOnly && !species.isRaising {
                Image(systemName: "eye").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
    }

    private var shinyMark: some View {
        Group { if species.isShiny { Text("✨").font(.system(size: 9)) } }
    }

    /// A neutral card: the number in its rarity's color, the types as one or two dots, the sprite, the name.
    private var cell: some View {
        neutralCard {
            VStack(spacing: 2) {
                HStack { plainNumber; Spacer(minLength: 0); seenMark; shinyMark; typeDots }
                // Seen only: faded, but the one being raised keeps its badge instead.
                sprite(50).opacity(isSeenOnly && !species.isRaising ? 0.45 : 1)
                    .overlay(alignment: .bottom) { if species.isRaising { raisingBadge.fixedSize() } }
                    .overlay(alignment: .topTrailing) { if catchCount > 1 { countBadge.fixedSize() } }
                Text(displayName).font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(5)
        }
    }

    /// "×8": the duplicates show at a glance, on every page of the grid.
    private var countBadge: some View {
        Text(store.l.catchCount(catchCount))
            .font(.system(size: 9, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(.regularMaterial, in: Capsule())
    }

    /// "키우는 중"은 현재 개체의 현재 형태 한 칸에만 표시한다. accent 틴트는 반투명이라
    /// 스프라이트가 비치므로 material 을 한 겹 깔아 대비를 확보한다(로그는 카드 배경 위라 불필요).
    private var raisingBadge: some View {
        Badge(store.l.dexRaising.uppercased(), tint: .accent, style: .tinted, size: 10)
            .background(.regularMaterial, in: Capsule())
    }

    /// 툴팁과 접근성 라벨이 같은 문장을 쓴다 — 칸이 글자로 못 보여주는 희귀도를 담는다.
    /// ✨ 는 이모지라 스크린리더가 일관되게 읽지 못하므로 명사로 함께 넣는다.
    private var tooltip: String {
        var parts = ["#\(species.id) \(species.name)", store.l.rarityLabel(species.rarity)]
        if let formCount { parts.append(store.l.formsCollected(formCount, of: formTotal)) }
        if species.isShiny { parts.append(store.l.dexShinyLabel) }
        if species.isRaising { parts.append(store.l.dexRaising) }
        if catchCount > 1 { parts.append(store.l.dexCaughtTimes(catchCount)) }
        if isSeenOnly { parts.append(store.l.dexSeenNotGraduated) }
        if isRepresentative { parts.append(store.l.representativeBadge) }
        return parts.joined(separator: " · ")
    }
}

/// 포획 로그 한 항목 — 희귀도·성격 헤더 + 진화 체인 스프라이트(각 밑에 종 이름) + 잡은 시각.
/// 체인 각 종의 이름은 저장분이 있으면 body 에서 즉시(플래시 없음), 없으면(구버전) .task 로 조회 후 백필.
@MainActor
private struct DexEntryRow: View {
    let store: CompanionStore
    let entry: DexEntry
    let dexLinks: [Int: String]
    /// `CompanionStore.duplicateCatchEntryIDs`, read once by the list.
    let isDuplicate: Bool
    /// Which one of its species this record is (`CompanionStore.dexCatchRanks`): a duplicate's "×N".
    var catchRank: Int? = nil
    let onOpenDexEntry: (String) -> Void
    @State private var resolved: [Int: String] = [:]

    /// "DUPLICATE ×8" from the second of its species.
    private var duplicateLabel: String {
        let word = store.l.dexDuplicate.uppercased()
        guard let catchRank, catchRank > 1 else { return word }
        return "\(word) \(store.l.catchCount(catchRank))"
    }

    /// 카드 안쪽 여백. 진화 라인이 쓸 수 있는 폭 계산과 단일 소스를 공유한다.
    private static let cardPadding: CGFloat = 8

    /// When it graduated, was sent off, or hatched for the one being raised, then how long ago (#183).
    private var whenLine: String? {
        let l = store.l
        let locale = store.language.displayLocale
        func stamp(_ date: Date) -> String {
            date.formatted(.dateTime.day().month().hour().minute().locale(locale)) + " · "
                + date.formatted(.relative(presentation: .named).locale(locale))
        }
        if store.isActiveDexEntry(entry) { return entry.raising.map { l.logHatchedOn(stamp($0.hatchedAt)) } }
        guard let caughtAt = entry.caughtAt else { return nil }
        return entry.isReleased ? l.logReleasedOn(stamp(caughtAt)) : l.logGraduatedOn(stamp(caughtAt))
    }

    var body: some View {
        // 저장분 우선(즉시·언어대응), 없으면 async 로 채운 resolved 사용.
        let names = store.dexStoredChainNames(entry) ?? (resolved.isEmpty ? nil : resolved)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 6) {
                // The badges go to a second line rather than squeeze one: in one row, French broke "NOUVELLE FORME"
                // inside its capsule.
                WrappingHStack(spacing: 6, lineSpacing: 4) {
                    Badge(store.l.rarityLabel(entry.rarity).uppercased(), tint: .rarity(entry.rarity), size: 10)
                    if store.isActiveDexEntry(entry) {
                        Badge(store.l.dexRaising.uppercased(), tint: .accent, style: .tinted, size: 10)
                    } else if entry.isReleased {
                        // 놓아준 개체 — 종은 도감에 남지만 이 개체는 끝까지 키우지 않았다.
                        // 중립색(secondary)으로 둔다: 실패가 아니라 다른 종류의 기록이라 경고색은 과하다.
                        Badge(store.l.dexReleased.uppercased(), tint: .secondary, style: .tinted, size: 10)
                    }
                    if entry.hasNewForm, !store.hidesFormNews(entry) {
                        Badge(store.l.newFormBadge.uppercased(), tint: .blue, style: .tinted, size: 10)
                    }
                    if isDuplicate {
                        Text(duplicateLabel)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.14))
                            .foregroundStyle(Color.secondary)
                            .clipShape(Capsule())
                    }
                    if entry.isShiny {
                        // 이모지는 스크린리더가 일관되게 읽지 못해 명사 라벨을 붙인다(도감 칸과 동일 규칙).
                        Text("✨").font(.system(size: 10))
                            .accessibilityLabel(store.l.dexShinyLabel)
                    }
                    if store.isFavorite(entry) {
                        Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(Color.pink)
                            .accessibilityLabel(store.l.favoriteLabel)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let nature = entry.nature {
                    Text(nature.name(store.language))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            EvoLineView(nodes: entry.chainOrder.map { EvoLineItem(.species($0), .done) },
                        mysteryLabel: store.l.unknownNextEvolution, language: store.language, thumb: 68,
                        shiny: entry.isShiny, names: names,
                        maxWidth: PopoverMetrics.scrollContentWidth - Self.cardPadding * 2, form: entry.spriteForm(),
                        nameFontSize: 11, nameLineLimit: 2, nameMinimumScaleFactor: 1,
                        dexLinks: dexLinks, onOpenDexEntry: onOpenDexEntry, bottomAligned: true)
            if let when = whenLine {
                Text(when).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            if let record = entry.raising, let summary = RaisingRecordCard.summary(record, entry: entry, store: store) {
                Text(summary).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(Self.cardPadding)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: "\(entry.id)-\(store.language.rawValue)") {
            // Stored names need no lookup: the row draws them already, and an unchanged write would draw it again.
            guard entry.needsNamesRefresh || store.dexStoredChainNames(entry) == nil else { return }
            let names = await store.dexResolveChainNames(entry)
            if names != resolved { resolved = names }
        }
    }
}

/// The short message of forms just unlocked (Arceus's Plates): their sprites, gone after a few seconds or a
/// click. Several claims at once ("Claim all") share one message.
@MainActor
struct FormUnlockToast: View {
    let store: CompanionStore

    var body: some View {
        let news = store.formUnlockNews
        let count = news.reduce(0) { $0 + $1.forms.count }
        VStack(alignment: .leading, spacing: 6) {
            Text(store.l.formUnlockTitle(count: count)).font(.callout.weight(.semibold))
            ForEach(news, id: \.speciesID) { item in
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 4), count: min(max(item.forms.count, 1), 7)),
                          alignment: .leading, spacing: 4) {
                    ForEach(item.forms, id: \.self) { form in
                        SpriteView(speciesID: item.speciesID, size: 40, form: form)
                            .frame(width: 40, height: 40)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { store.dismissFormUnlockNews() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .task(id: news) {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { store.dismissFormUnlockNews() }
        }
    }
}

/// What graduating the Pokémon raised would advance (`CompanionStore.activeGoals`), under its track: every goal on
/// its own row, however long the list. Nothing when it brings nothing.
@MainActor
struct ActiveGoalsList: View {
    let store: CompanionStore
    /// Opens the goal's achievement; nil, the lines are not links.
    var onOpen: ((ItemKind) -> Void)? = nil
    /// The goals the send-off confirmation's sentence names before "…".
    static let inSentence = 3

    var body: some View {
        let goals = store.activeGoals
        if !goals.isEmpty {
            let l = store.l
            VStack(alignment: .leading, spacing: 4) {
                Text(l.countsFor).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(goals.enumerated()), id: \.offset) { _, goal in
                    let row = HStack(spacing: 6) {
                        ItemIconView(kind: goal.item, size: 16)
                        Text(l.activeGoalName(goal)).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text("+\(goal.gain)").fontWeight(.bold)
                        Text("\(goal.count)/\(goal.needed)").foregroundStyle(.secondary)
                        if onOpen != nil {
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption).monospacedDigit()
                    if let onOpen {
                        Button { onOpen(goal.item) } label: { row.contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .hoverTip(HoverTip(id: "goal:\(goal.item.rawValue)", title: l.openAchievementHint))
                    } else {
                        row
                    }
                }
            }
            .accessibilityElement(children: onOpen == nil ? .combine : .contain)
        }
    }

    /// The confirmation's sentence: the goals, each with what it adds.
    static func sentence(_ store: CompanionStore) -> String? {
        let goals = store.activeGoals
        guard !goals.isEmpty else { return nil }
        let l = store.l
        let list = goals.prefix(inSentence).map { "\(l.activeGoalName($0)) (+\($0.gain))" }.joined(separator: ", ")
            + (goals.count > inSentence ? ", …" : "")
        return l.stillCountsFor(store.displayName, list)
    }
}

/// The badges after the rarity: a form its line never had, fixed at hatch and kept through evolution, then whether
/// sending it off loses anything (`CompanionStore.activeNews`): nothing new through its whole line, or new. On the card
/// and on the banner its copy button draws.
@MainActor
struct ActiveNewsBadges: View {
    let store: CompanionStore

    var body: some View {
        let l = store.l
        let isMystery = store.activeNews?.mystery != nil
        let isNewForm = store.state.active?.hasNewForm == true
        if isMystery {
            Badge(l.formMysteryBadge.uppercased(), tint: .blue, style: .tinted)
                .lineLimit(1).fixedSize()
                .hoverTip(store.activeNewsHint)
        } else if isNewForm {
            Badge(l.newFormBadge.uppercased(), tint: .blue, style: .tinted)
                .lineLimit(1).fixedSize()
                .hoverTip(store.activeNewsHint)
        }
        if let news = store.activeNews, !isMystery {
            if news.isDuplicate {
                Badge(l.activeDuplicateBadge.uppercased(), tint: .secondary, style: .tinted)
                    .lineLimit(1).fixedSize()
                    .hoverTip(l.activeDuplicateHint)
            } else if !isNewForm {
                // A costume new to the collection on species all held: "New costume", else "New" (the owner, 2026-11-13).
                let onlyCostume = news.newCostume && news.newSpecies.isEmpty && !news.firstShiny && !news.costume
                Badge((onlyCostume ? l.activeNewCostumeBadge : l.activeNewBadge).uppercased(), tint: .green, style: .tinted)
                    .lineLimit(1).fixedSize()
                    .hoverTip(store.activeNewsHint)
            }
        }
    }
}
