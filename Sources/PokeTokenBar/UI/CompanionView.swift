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
        // 캐시에 있으면 즉시(동기) 표시 — 재렌더 플래시 방지.
        _img = State(initialValue: kind.spriteName.flatMap { SpriteLoader.cachedItemImage(name: $0) })
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
/// SwiftUI `.task` 는 호스트 없이 돌릴 수 없어 규칙만 순수 값 전이로 빼 둔다(`frameDelay` 와 같은 방식).
/// 여기 담긴 규칙은 둘 다 "화면에 남은 픽셀이 지금 주체의 것인가"를 지킨다.
struct SpriteSubject: Equatable {
    var image: NSImage?
    /// image 가 어느 speciesID 것인지. nil = 알(또는 로드된 개체 없음).
    var loadedID: Int?

    /// 주체가 알로 바뀌었다(졸업·새 알). 이전 **개체**의 이미지는 다른 주체의 픽셀이라 버린다.
    /// 이미 알이던 경우(loadedID == nil)엔 손대지 않는다 — 시드된 알 이미지를 지워 🥚 글리프로 깜빡이게 하지 않기 위해.
    func becomingEgg(cachedEgg: NSImage?) -> SpriteSubject {
        guard loadedID != nil else { return self }
        return SpriteSubject(image: cachedEgg, loadedID: nil)
    }

    /// 로드된 정적 스프라이트를 반영한 결과. **취소된 로드는 nil — 상태를 아예 건드리지 않는다.**
    /// 취소는 곧 주체가 바뀌었다는 뜻이고, 협조적 취소라 continuation 은 그대로 실행되므로 후속 `.task`
    /// 가 이미 새 주체로 잡아 둔 상태를 뒤늦게 덮어쓸 수 있다. 그러면 알 위에 옛 개체가 되살아나고
    /// (#135 와 같은 증상), 실패한 로드가 `loadedID` 만 남기면 다음에 그 종이 다시 활성일 때
    /// "이미 로드됨"으로 판단해 🥚 글리프가 고정된다.
    /// (nil 로 돌려주는 이유: 같은 값을 되쓰면 @State 무효화가 한 번 더 돌아 항상 떠 있는 펫에 불필요한 재렌더가 생긴다.)
    func applyingLoad(_ image: NSImage?, for id: Int, cancelled: Bool) -> SpriteSubject? {
        cancelled ? nil : SpriteSubject(image: image, loadedID: id)
    }

    /// 로드된 알 스프라이트를 반영한 결과(같은 이유로 취소면 nil). 알은 종이 없으므로 loadedID 는 그대로.
    func applyingEgg(_ image: NSImage?, cancelled: Bool) -> SpriteSubject? {
        cancelled ? nil : SpriteSubject(image: image, loadedID: loadedID)
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
    /// idle 배터리를 통제한다 — 항상 떠 있는 플로팅 펫(0.4s≈2.5fps)이 메뉴바 GIF 규율과 동치가 되게.
    /// 팝오버 등 일시적 표시는 0(기본)으로 두어 네이티브 fps 유지.
    var minFrameDelay: TimeInterval = 0
    @State private var img: NSImage?
    @State private var up = false
    @State private var loadedID: Int?   // img 가 어느 speciesID 것인지(id 변경 시 갱신 판단)
    /// img 가 이로치 스프라이트인지 — 재로드 판정의 두 번째 축(근거는 needsReload).
    @State private var loadedShiny = false
    @State private var frames: [(image: NSImage, delay: TimeInterval)] = []
    @State private var frameIndex = 0

    init(speciesID: Int?, size: CGFloat = 84, bob: Bool = false, animated: Bool = false,
         shiny: Bool = false, minFrameDelay: TimeInterval = 0) {
        self.speciesID = speciesID
        self.size = size
        self.bob = bob
        self.animated = animated
        self.shiny = shiny
        self.minFrameDelay = minFrameDelay
        // 캐시에 있으면 즉시(동기) 표시 — 재렌더 플래시 방지 + 정적 스냅샷에서도 보임.
        // speciesID==nil(알 상태)이면 알 스프라이트를 시드(없으면 body 가 🥚 폴백).
        let cached = speciesID.map { SpriteLoader.cachedImage(speciesID: $0, shiny: shiny) } ?? SpriteLoader.cachedEggImage()
        _img = State(initialValue: cached)
        _loadedID = State(initialValue: (speciesID != nil && cached != nil) ? speciesID : nil)
        _loadedShiny = State(initialValue: shiny)
    }

    /// 프레임 지속(초) = max(원본 delay, 하한). 순수·테스트용 — fps 상한 회귀 가드.
    static func frameDelay(base: TimeInterval, floor: TimeInterval) -> TimeInterval { max(base, floor) }

    /// 디코드된 GIF 프레임 중 실제로 재생할 것 — 취소됐거나 2프레임 미만이면 빈 배열(정적 폴백).
    /// 취소 검사가 여기 있는 이유: `frames` 는 body 에서 `img` 보다 먼저 그려지므로, 취소된 로드가
    /// 뒤늦게 대입되면 새 주체(알) 위에 옛 개체의 GIF 가 정지 상태로 올라온다.
    static func framesToApply(_ decoded: [(image: NSImage, delay: TimeInterval)],
                              cancelled: Bool) -> [(image: NSImage, delay: TimeInterval)] {
        (cancelled || decoded.count < 2) ? [] : decoded
    }

    /// 현재 그리는 주체(순수 전이 입력).
    private var subject: SpriteSubject { SpriteSubject(image: img, loadedID: loadedID) }

    /// 전이 결과를 @State 로 되돌린다(State 세터는 nonmutating). 값이 그대로면 쓰지 않는다 —
    /// @State 는 같은 값을 써도 무효화가 돌아, 항상 떠 있는 펫에 불필요한 재렌더가 생긴다.
    private func apply(_ next: SpriteSubject) {
        guard next != subject else { return }
        img = next.image
        loadedID = next.loadedID
    }
    /// 정적 스프라이트를 다시 불러야 하는가 — 종이 바뀌었거나 **이로치 여부가 뒤집혔을 때**.
    /// 순수·테스트용(frameDelay 와 같은 이유). 종만 비교하던 과거 판정은 도감의 이로치 토글에서
    /// .task 가 다시 돌아도 "이미 그 종을 로드했다"로 판정해 색이 안 바뀌는 회귀를 낳았다.
    static func needsReload(loadedID: Int?, loadedShiny: Bool, id: Int, shiny: Bool) -> Bool {
        loadedID != id || loadedShiny != shiny
    }

    /// size×size 슬롯 안에서 이 이미지가 실제로 차지할 크기 — 원본 비율 유지(SpriteFit).
    /// 순수·테스트용. `.resizable()` 은 프레임을 그대로 채우므로(늘어남) 프레임을 미리 재서 넘긴다.
    /// 정사각 원본(정적 96×96·아이템 30×30)은 size×size 그대로라 기존 레이아웃과 동일하다.
    static func imageSize(for image: NSImage, box: CGFloat) -> CGSize {
        SpriteFit.size(for: image.size, box: box)
    }

    /// 비율 유지로 잰 이미지 프레임 + 바깥 size×size 슬롯. 바깥 슬롯을 유지하는 이유: 진화 라인·도감
    /// 그리드의 폭 계산(EvoLineView.rowWidth 등)이 칸을 정사각으로 전제한다 — 안쪽만 줄여야 안 흔들린다.
    @ViewBuilder
    private func fitted(_ image: NSImage) -> some View {
        let fit = Self.imageSize(for: image, box: size)
        Image(nsImage: image).resizable().interpolation(.none)
            .frame(width: fit.width, height: fit.height)
            .frame(width: size, height: size)
    }

    var body: some View {
        Group {
            if !frames.isEmpty {
                // GIF 애니메이션 경로 — 현재 프레임만 렌더. Gen-V GIF 캔버스는 종마다 비정사각이라
                // (잭키 36×66) 정사각으로 늘리면 뚱뚱해진다 → fitted 로 비율 유지.
                fitted(frames[frameIndex % frames.count].image)
            } else if let img {
                fitted(img)
            } else {
                Text("🥚").font(.system(size: size * 0.62)).frame(width: size, height: size)
            }
        }
        // GIF 재생 중엔 bob 정지(프레임 자체가 움직임) — 폴백/정적일 때만 상하 움직임
        .offset(y: bob && frames.isEmpty && up ? -3 : 0)
        .task(id: "\(speciesID.map(String.init) ?? "nil")-\(shiny)") {
            // animated 프레임은 id/shiny 변경 시 항상 초기화(이전 개체 프레임 잔상 방지)
            frames = []
            frameIndex = 0
            guard let id = speciesID else {
                // 알 상태 — 정적 알 스프라이트 로드(애니메이션 알은 없음). 실패/오프라인이면 body 가 🥚 폴백.
                // 종 → 알(졸업·새 알)이면 이전 개체 이미지를 버려야 한다 — img 는 뷰 identity 가 살아있는 동안
                // 유지되고 플로팅 펫 패널은 졸업 때 재생성되지 않아, 안 버리면 옛 포켓몬이 계속 떠 있다.
                apply(subject.becomingEgg(cachedEgg: SpriteLoader.cachedEggImage()))
                if img == nil {
                    let egg = await SpriteLoader.eggImage()
                    if let next = subject.applyingEgg(egg, cancelled: Task.isCancelled) { apply(next) }
                }
                return
            }
            // 정적 스프라이트 먼저(즉시 표시 + 폴백 보장).
            // 캐시 시드로 이미 같은 종·같은 이로치 여부면 재요청 생략(플래시 방지)
            if Self.needsReload(loadedID: loadedID, loadedShiny: loadedShiny, id: id, shiny: shiny) {
                let loaded = await SpriteLoader.image(speciesID: id, animated: false, shiny: shiny)
                // 취소된 로드는 반영하지 않는다(#138). 이로치 축은 **반영될 때만** 기록해
                // subject(종)와 loadedShiny 가 어긋나 다음 판정이 틀어지는 것을 막는다.
                if let next = subject.applyingLoad(loaded, for: id, cancelled: Task.isCancelled) {
                    apply(next)
                    loadedShiny = shiny
                }
            }
            guard animated else { return }
            // animated GIF 시도(shiny 미제공 종은 일반 GIF 폴백) → 프레임 2개 이상이면 순환 루프
            var gifData = await SpriteStore.shared.data(speciesID: id, animated: true, shiny: shiny)
            if gifData == nil, shiny {
                gifData = await SpriteStore.shared.data(speciesID: id, animated: true, shiny: false)
            }
            guard let data = gifData else { return }
            // 단일 프레임/디코드 실패 → 정적 폴백. 취소됐으면 아예 반영하지 않는다(빈 배열이라 아래서 종료).
            let ready = Self.framesToApply(GIFDecoder.frames(from: data), cancelled: Task.isCancelled)
            guard !ready.isEmpty else { return }
            frames = ready
            // delay 기반 프레임 advance. .task 취소 시(speciesID 변경/뷰 소멸) 루프 종료 — 누수 없음
            while !Task.isCancelled {
                let delay = Self.frameDelay(base: frames[frameIndex % frames.count].delay, floor: minFrameDelay)
                // minFrameDelay>0(플로팅 펫): fps 상한 + tolerance 로 wakeup 코얼레싱 — 메뉴바
                // max(0.4,delay)+timer.tolerance 규율과 동치(항상 뜬 표면의 idle 배터리 통제). 0 이면 네이티브.
                try? await Task.sleep(for: .seconds(delay),
                                      tolerance: minFrameDelay > 0 ? .seconds(delay * 0.5) : .zero)
                if Task.isCancelled { break }
                frameIndex = (frameIndex + 1) % frames.count
            }
        }
        .onAppear {
            guard bob else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { up = true }
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
    var thumb: CGFloat = 40
    var shiny: Bool = false     // 개체가 shiny 면 라인 전체를 shiny 스프라이트로
    var names: [Int: String]? = nil   // 제공되면 각 스프라이트 밑에 작은 이름 라벨(도감 단계별 이름)
    /// 한 줄이 쓸 수 있는 가로 폭. 기본 .infinity = 제한 없음(스크롤 없이 나열).
    var maxWidth: CGFloat = .infinity

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

    var body: some View {
        if Self.needsScroll(count: nodes.count, thumb: thumb,
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

    private var row: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { i, node in
                if i > 0 {
                    Image(systemName: "arrow.right").font(.system(size: thumb * 0.2))
                        .foregroundStyle(.tertiary)
                        .frame(width: thumb * Self.arrowRatio)
                        .padding(.top, thumb * 0.4)   // 스프라이트 세로 중앙에 정렬
                }
                VStack(spacing: 1) {
                    Group {
                        switch node.content {
                        case .species(let id):
                            SpriteView(speciesID: id, size: thumb, shiny: shiny)
                        case .mystery:
                            Text("?")
                                .font(.system(size: thumb * 0.55, weight: .bold, design: .rounded))
                                .frame(width: thumb, height: thumb)
                                .accessibilityLabel(Text(mysteryLabel))
                        }
                    }
                        .opacity(node.state == .future ? 0.32 : 1)
                        .saturation(node.state == .future ? 0.4 : 1)
                        .overlay(alignment: .bottom) {
                            if node.state == .current {
                                Circle().fill(Color.accentColor).frame(width: 4, height: 4).offset(y: 2)
                            }
                        }
                    if let names, case .species(let id) = node.content {
                        Text(names[id] ?? "…")
                            .font(.system(size: 8)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: thumb + Self.nameSlack)
                    }
                }
                .frame(width: thumb + (names == nil ? 0 : Self.nameSlack))
                .id(i)   // 셰브론 페이징(ScrollViewProxy.scrollTo) 대상
            }
        }
    }
}

/// 팝오버 상단 — 현재 포켓몬 + 진화 진행 + 부화/진화 연출.
@MainActor
struct CompanionHeader: View {
    let store: CompanionStore
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
    // 민트 사용 시 "반짝" 스파클 (성격 변경 피드백 — 텍스트 없이 짧은 이펙트)
    @State private var seenMintSeq = -1
    @State private var mintSparkle = false

    /// 부화 임박(90%+) — 알이 흔들리고 문구가 바뀐다.
    private var eggImminent: Bool { store.isEgg && store.eggProgress >= 0.9 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                SpriteView(speciesID: store.currentSpeciesID, size: 76, bob: true, animated: true,
                           shiny: store.currentIsShiny)
                    .frame(width: 76, height: 76)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                            Text("+\(TokenFormatter.compact(candyXPAmount)) XP")
                                .font(.caption.weight(.bold)).foregroundStyle(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.regularMaterial, in: Capsule())
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .offset(y: -16)
                        }
                    }
                    .overlay {
                        if mintSparkle {
                            ZStack {
                                Text("✨").font(.system(size: 22)).offset(x: -11, y: -9)
                                Text("✨").font(.system(size: 15)).offset(x: 13, y: 5)
                                Text("✨").font(.system(size: 12)).offset(x: 1, y: 13)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(store.displayName).font(.callout.weight(.semibold))
                        if store.currentIsShiny { Text("✨").font(.system(size: 11)) }
                        if let r = store.rarity {
                            Text(store.l.rarityLabel(r).uppercased()).font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(rarityColor(r)).foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    if store.hasActive {
                        // 단계 + 성격(부화 시 확정된 개체 아이덴티티)
                        let nature = store.currentNature.map { " · \($0.name(store.language))" } ?? ""
                        Text(store.stageText + nature).font(.caption2).foregroundStyle(.secondary)
                        ProgressView(value: store.progress).controlSize(.small).tint(.orange)
                        if store.tokensToNext > 0 {
                            let amount = TokenFormatter.compact(store.tokensToNext)
                            Text(store.isFinalStage ? store.l.toGraduation(amount) : store.l.toNextEvolution(amount))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    } else {
                        // 알 인큐베이션 — 부화까지 진행 (임박 시 문구·색 전환)
                        HStack(spacing: 6) {
                            Text(eggImminent ? store.l.eggImminent : store.l.eggIncubating)
                                .font(.caption2)
                                .foregroundStyle(eggImminent ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                            // 등급 보증 알이면 무엇을 품고 있는지 — 도감 칩과 같은 라벨·색.
                            // 알 스프라이트는 한 장뿐이라 등급 구분은 이 배지가 유일한 신호다.
                            if let guarantee = store.eggGuarantee {
                                Text(store.l.eggGuaranteeHint(guarantee)).font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(rarityColor(guarantee)).foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        ProgressView(value: store.eggProgress).controlSize(.small).tint(.orange)
                        Text(store.l.eggToHatch(TokenFormatter.compact(store.eggTokensToHatch)))
                            .font(.caption2).foregroundStyle(.tertiary)
                        // 첫 실행(적립 0) — 정적 알 앞에서 "고장났나" 오해 방지용 한 줄 안내
                        if !store.eggStarted {
                            Text(store.l.eggFirstRunHint)
                                .font(.caption2).foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(statusLine).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if store.hasActive, !store.lineNodes.isEmpty {
                // 폭을 안 주면 분기 라인(이브이)이 넘쳐 팝오버 콘텐츠 전체가 좌우로 잘린다.
                EvoLineView(nodes: store.lineNodes, mysteryLabel: store.l.unknownNextEvolution, shiny: store.currentIsShiny,
                            maxWidth: PopoverMetrics.contentWidth)
            }
            if let g = store.justGraduated {
                Text(store.l.graduated(g))
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
        .onAppear {
            playCelebrationIfNeeded()
            showCandyXPIfNeeded()
            showMintIfNeeded()
            syncEggWiggle()
        }
        .onChange(of: store.celebrationSeq) { playCelebrationIfNeeded() }
        .onChange(of: store.candyFeedbackSeq) { showCandyXPIfNeeded() }
        .onChange(of: store.mintFeedbackSeq) { showMintIfNeeded() }
        .onChange(of: eggImminent) { syncEggWiggle() }
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
        store.consumeCandyFeedback()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { candyXPShown = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            withAnimation(.easeOut(duration: 0.4)) { candyXPShown = false }
        }
    }

    /// 민트 사용 "반짝" 스파클 1회 재생 — 사탕과 동일 1회성 계약(consume 로 재마운트 재생 방지). 텍스트 없음.
    private func showMintIfNeeded() {
        guard store.mintFeedbackNature != nil, store.mintFeedbackSeq != seenMintSeq else { return }
        seenMintSeq = store.mintFeedbackSeq
        store.consumeMintFeedback()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { mintSparkle = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeOut(duration: 0.4)) { mintSparkle = false }
        }
    }

    private func syncEggWiggle() {
        if eggImminent {
            withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) { eggWiggle = true }
        } else {
            withAnimation(.default) { eggWiggle = false }
        }
    }

    private var statusLine: String { store.statusText }
}

/// 희귀도 1종 캡슐 — 색 점 + 라벨 + 개수. 선택 시 원색 링 + 체크마크로 강조.
/// (solid 채움 대신 링+체크 — green/orange 위 흰 텍스트 대비 문제 회피 + 라이트/다크 양쪽 가독.
///  텍스트는 .primary 라 모드 자동 적응, 색 정체성은 점·링·체크로 유지 → 엔트리 배지와 안 어긋남.)
/// 0이면 흐리게(필터 불가).
@MainActor
struct RarityTally: View {
    let label: String
    let count: Int
    let color: Color
    var isSelected: Bool = false      // 이 희귀도로 필터 활성 → 원색 링 + 체크
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9, weight: isSelected ? .semibold : .medium))
            Text("\(count)").font(.system(size: 9, weight: .bold))
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold)).foregroundStyle(color)
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
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(rarityDisplayOrder, id: \.self) { r in
                    let count = store.dexCount(r)
                    Button { onSelect(r) } label: {
                        RarityTally(
                            label: store.l.rarityLabel(r), count: count, color: rarityColor(r),
                            isSelected: selected == r)
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0)          // 0마리 희귀도는 필터 불가
                    .help(store.l.dexFilterHint)
                }
            }
        }
    }
}

/// 컬렉션 탭 — 도감과 포획 로그를 하위 세그먼트로 전환한다.
///
/// 두 화면은 같은 데이터를 다른 축으로 본다:
///  - **도감**: 종 1개 = 1칸. 같은 라인을 여러 번 키워도 한 칸으로 접힌다(종 정보만).
///  - **로그**: 개체 1마리 = 1행. 같은 라인이 여러 행으로 나오는 게 정상 — 성격·획득 시각처럼
///    개체에 딸린 정보는 여기에만 있다.
/// 상위 탭(PopoverTab)은 그대로 4개 — 세그먼트 폭(332/2)이 넉넉해 탭바를 늘릴 필요가 없다.
@MainActor
struct CollectionView: View {
    let store: CompanionStore
    let navigation: PopoverNavigation
    /// 로그 전용 희귀도 필터. 도감은 개수 단위가 종이라 자기 필터를 따로 갖는다(DexGridView).
    @State private var selectedRarity: Rarity?

    /// 도감·로그 공통 높이 — 상점·가방과 같은 520. 세그먼트를 전환할 때도, 탭을 넘나들 때도
    /// 팝오버가 리사이즈되지 않는다.
    ///
    /// 예산: 520 − 세그먼트 24 − 헤더 39 − 하단 줄 18 − 간격 24 = 격자 415. 6행 spacing 4 면
    /// 행이 65.8 이고, 칸 여백 6 과 이름 12 를 빼면 스프라이트에 47.8 이 남는다(현재 44).
    private static let contentHeight: CGFloat = 520

    /// 선택된 희귀도만 노출(없으면 전체). 상단 캡슐 토글로 설정.
    private var visibleEntries: [DexEntry] {
        guard let r = selectedRarity else { return store.dexEntriesSorted }
        return store.dexEntriesSorted.filter { $0.rarity == r }
    }

    var body: some View {
        @Bindable var nav = navigation
        if store.dexEntries.isEmpty {
            emptyState   // 둘 다 비어 있으니 세그먼트를 그리지 않는다
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $nav.showingCollectionLog) {
                    Text(store.l.dexTitle).tag(false)
                    Text(store.l.catchLogTitle).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if nav.showingCollectionLog { catchLog } else { DexGridView(store: store) }
            }
            .frame(height: Self.contentHeight)
        }
    }

    /// 포획 로그 — 개체 단위 기록. 필터(요약 헤더)는 고정, 목록만 스크롤한다
    /// (아래로 내리는 중에도 희귀도 필터를 토글할 수 있다).
    private var catchLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            DexSummaryHeader(store: store, selected: selectedRarity) { r in
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedRarity = (selectedRarity == r) ? nil : r
                }
            }
            // maxHeight 는 팝오버 재오픈 시 ScrollView fitting size 가 작게 잡혀 크기가 줄어드는
            // 문제가 있어, 바깥 VStack 을 height 로 고정해 스크롤 영역이 나머지를 채우게 한다.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Color.clear.frame(height: 0).id("dexTop")   // 스크롤 최상단 앵커
                        ForEach(visibleEntries) { entry in
                            DexEntryRow(store: store, entry: entry)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                // 필터 토글 시 목록 최상단으로 — 이전 스크롤 위치가 새 필터 결과 밖이어도 처음부터 보이게.
                .onChange(of: selectedRarity) {
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("dexTop", anchor: .top) }
                }
            }
        }
    }

    /// 빈 도감 — 안내 마스코트(피카츄, PokéAPI) + 포켓몬을 모으라는 문구.
    private var emptyState: some View {
        VStack(spacing: 10) {
            SpriteView(speciesID: 25, size: 96, animated: true)   // 피카츄(움직임)
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
        .help(title)
        .accessibilityLabel(title)
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .fixedSize()
    }
}

/// 도감 — 보유 종만 도감 번호순으로, 한 페이지 24칸(4열×6행) 고정 격자.
///
/// 페이지식이라 ScrollView 를 쓰지 않는다 — 팝오버 재오픈 시 fitting size 가 줄어드는 기존 결함을
/// 우회(고정 높이 + maxHeight)가 아니라 회피로 피한다. 페이지 크기가 고정이라 모든 칸이 항상
/// 렌더되므로 지연 격자(LazyVGrid)도 필요 없다 — 평범한 VStack/HStack 으로 동기 렌더한다.
/// 미보유 종은 아예 그리지 않는다(물음표·실루엣 칸 없음).
@MainActor
private struct DexGridView: View {
    let store: CompanionStore
    @State private var selectedRarity: Rarity?
    @State private var page = 0

    /// 선택한 칸 — 하단 줄에 희귀도를 띄우고, 이로치를 잡은 종이면 스프라이트를 그 색으로 바꾼다.
    @State private var selectedID: Int?

    private static let columns = 4
    private static let rows = 6
    private static let pageSize = columns * rows      // 24
    private static let spacing: CGFloat = 4

    var body: some View {
        // 종별 집계는 한 번만 훑고 하위로 넘긴다 — 칸마다 재집계하면 도감이 O(칸×도감) 이 된다.
        let all = store.dexSpecies
        let visible = selectedRarity.map { r in all.filter { $0.rarity == r } } ?? all
        let pageCount = max(1, (visible.count + Self.pageSize - 1) / Self.pageSize)
        let current = min(page, pageCount - 1)   // 보유 종이 줄어든 경우(필터 등) 범위 방어
        let slice = Array(visible.dropFirst(current * Self.pageSize).prefix(Self.pageSize))
        VStack(alignment: .leading, spacing: 8) {
            header(all)
            grid(slice)
            footer(slice, current: current, pageCount: pageCount)
        }
        // 이름이 저장돼 있지 않은 구버전 졸업분을 채운다 — 격자는 저장분만 읽으므로 이게 없으면
        // 칸이 `#41` 로 남는다. 저장된 항목은 조회하지 않으므로 채워진 뒤로는 아무 일도 하지 않는다.
        .task { await store.backfillMissingDexNames() }
    }

    /// 희귀도 필터 — 로그와 같은 RarityTally 를 쓰되 개수는 **종 단위**다.
    /// (DexSummaryHeader 는 개체 수 dexCount 를 내부에서 직접 부르므로 재사용하려면 시그니처를 바꿔
    ///  로그 경로까지 건드려야 한다. 캡슐 4개짜리 헤더라 여기서는 인라인으로 둔다.)
    private func header(_ all: [CompanionStore.DexSpecies]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(store.l.dexTitle).font(.callout.weight(.semibold))
                // 총계는 필터와 무관한 전체 종 수 — 로그 헤더(dexTotal)와 같은 규칙.
                // 필터 중인 희귀도의 개수는 아래 캡슐이 이미 보여준다.
                Text(store.l.dexSpeciesTotal(all.count)).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(rarityDisplayOrder, id: \.self) { r in
                    let count = all.lazy.filter { $0.rarity == r }.count
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedRarity = (selectedRarity == r) ? nil : r
                            page = 0        // 필터가 바뀌면 페이지 범위도 바뀐다 — 항상 첫 페이지부터
                            selectedID = nil // 선택한 칸이 필터 밖으로 나가면 하단 줄이 유령 정보를 남긴다
                        }
                    } label: {
                        RarityTally(label: store.l.rarityLabel(r), count: count,
                                    color: rarityColor(r), isSelected: selectedRarity == r)
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0)          // 0종 희귀도는 필터 불가
                    .help(store.l.dexFilterHint)
                }
            }
        }
    }

    /// 고정 격자 — 남는 칸은 투명(테두리·물음표 없이 정렬만 유지).
    /// 모든 행에 maxHeight 를 걸어 6행이 높이를 균등 분할하게 한다 — 빈 칸의 Color 는 유연 크기라,
    /// 행마다 안 걸면 빈 행이 늘어나 채워진 행을 짓누른다(보유 종이 적을 때 첫 줄이 찌그러짐).
    private func grid(_ slice: [CompanionStore.DexSpecies]) -> some View {
        VStack(spacing: Self.spacing) {
            ForEach(0..<Self.rows, id: \.self) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(0..<Self.columns, id: \.self) { col in
                        let i = row * Self.columns + col
                        if i < slice.count {
                            let sp = slice[i]
                            DexSpeciesCell(store: store, species: sp,
                                           isSelected: selectedID == sp.id,
                                           isRepresentative: store.representativeSpeciesID == sp.id) {
                                selectedID = (selectedID == sp.id) ? nil : sp.id
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

    /// 하단 한 줄 — 왼쪽은 선택한 칸의 희귀도, 오른쪽은 페이저.
    /// 페이저가 1페이지라 안 보일 때도 이 줄을 **항상** 예약한다 — 페이지 수나 선택 여부에 따라
    /// 격자 높이가 흔들리지 않게.
    private func footer(_ slice: [CompanionStore.DexSpecies],
                        current: Int, pageCount: Int) -> some View {
        HStack(spacing: 8) {
            if let sel = slice.first(where: { $0.id == selectedID }) {
                // 칸은 번호·스프라이트·이름만 보여주므로 희귀도가 선택으로 얻는 정보다.
                Text("#\(sel.id) \(sel.name) · \(store.l.rarityLabel(sel.rarity))")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                let isRepresentative = store.representativeSpeciesID == sel.id
                RepresentativeFooterButton(localization: store.l,
                                           isRepresentative: isRepresentative) {
                    _ = store.setRepresentativeSpeciesID(isRepresentative ? nil : sel.id)
                }
            }
            Spacer(minLength: 4)
            if pageCount > 1 {
                Button { page = max(0, current - 1); selectedID = nil } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain).disabled(current == 0)
                .accessibilityLabel(store.l.dexPagePrev)
                Text("\(current + 1) / \(pageCount)")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(store.l.dexPageLabel(current + 1, pageCount))
                Button { page = min(pageCount - 1, current + 1); selectedID = nil } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain).disabled(current == pageCount - 1)
                .accessibilityLabel(store.l.dexPageNext)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .frame(height: 18)
    }
}

/// 도감 한 칸 — 도감 번호 + 스프라이트 + 종 이름. 종 정보만 담는다(성격·획득 횟수는 로그의 몫).
/// 정적 스프라이트만 쓴다(animated 생략) — 한 페이지 24칸을 GIF 로 동시 재생하면 CPU 가 안 된다.
@MainActor
private struct DexSpeciesCell: View {
    let store: CompanionStore
    let species: CompanionStore.DexSpecies
    let isSelected: Bool
    let isRepresentative: Bool
    let onTap: () -> Void

    /// 로그(56)보다 작다 — 24칸 격자에 이름까지 담아야 한다. 원본 96×96 픽셀아트를
    /// interpolation(.none) 으로 축소하므로 이 크기에서도 식별에 문제없다.
    private static let thumb: CGFloat = 44

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 1) {
                // 기본은 일반색. 이로치를 잡은 종은 선택하면 이로치색으로 바뀐다 —
                // 일반·이로치를 둘 다 가진 종도 두 모습을 다 볼 수 있다(본가 HOME 의 이로치 토글과 같은 결).
                SpriteView(speciesID: species.id, size: Self.thumb,
                           shiny: species.isShiny && isSelected)
                    .frame(width: Self.thumb, height: Self.thumb)
                    // 표식은 스프라이트 아래가 아니라 위에 겹친다 — 별도 줄로 빼면 칸 높이가 넘친다.
                    // 이 줄은 번호·이로치와 폭을 다투지 않아 세 언어 모두 8pt 그대로 들어간다
                    // (가장 긴 en "RAISING" 이 캡슐 포함 45pt, 칸 안쪽 폭 74pt).
                    // `fixedSize` 필수 — 오버레이는 붙은 뷰(스프라이트 44)의 폭을 제안받아서, 없으면
                    // 칸이 아니라 스프라이트 폭에 갇혀 "RAISIN/G" 로 줄바꿈된다.
                    .overlay(alignment: .bottom) {
                        if species.isRaising { raisingBadge.fixedSize() }
                    }
                Text(species.name)
                    .font(.system(size: 9))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            // 번호·이로치는 스프라이트(44)가 아니라 **칸 안쪽 폭**(74)에 건다 — 스프라이트에 걸면
            // 가운데 정렬된 44 기준이라 좌우 15 씩 안으로 밀려 번호가 칸 중앙 쪽에 떠 보인다.
            // 칸 기준으로 두면 양 끝으로 붙고, 픽셀아트 몸통과 겹치는 폭도 줄어든다.
            .overlay(alignment: .topLeading) { numberTag }
            .overlay(alignment: .topTrailing) {
                // ✨ = 이 종의 이로치를 잡은 적이 있다는 표식(탭하면 그 색으로 바뀐다).
                if species.isShiny {
                    Text("✨")
                        .font(.system(size: 8))
                        .padding(.horizontal, 2)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityLabel(store.l.dexShinyLabel)
                }
            }
            .padding(3)
            // 대표 = 영속적인 accent 배경, 방금 클릭한 칸 = 기존 accent 테두리.
            // 서로 다른 카드여도 같은 강조 두 개가 선택된 것처럼 보이지 않는다.
            .background(isRepresentative ? Color.accentColor.opacity(0.16)
                                         : Color.secondary.opacity(isSelected ? 0.16 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .contextMenu {
            Button {
                _ = store.setRepresentativeSpeciesID(isRepresentative ? nil : species.id)
            } label: {
                Label(isRepresentative ? store.l.representativeFollowCurrent
                                       : store.l.representativeSet,
                      systemImage: isRepresentative ? "arrow.triangle.2.circlepath" : "star")
            }
        }
    }

    /// material 판 — 어두운 스프라이트 위에서도 읽히게(라이트/다크 자동).
    /// 스프라이트 위 라벨에 이미 쓰는 패턴과 동일.
    private var numberTag: some View {
        HStack(spacing: 2) {
            Text("#\(species.id)")
            // 기존 번호 캡슐에 결합해 이로치(우측 상단)·키우는 중(스프라이트 하단)·이름과
            // 새 자리를 다투지 않는다. 아이콘은 언어에 따라 폭이 달라지지 않고, 의미는 셀의
            // 현지화된 툴팁·접근성 라벨이 보완한다.
            if isRepresentative {
                Image(systemName: "star.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
            .background(.regularMaterial, in: Capsule())
    }

    /// "키우는 중" — 아직 졸업 기록이 없어 사라질 수 있는 칸임을 알린다. 포획 로그의 같은 뱃지와
    /// 글자·색을 맞춰 두 화면이 같은 말을 쓰게 한다. accent 틴트는 반투명이라 스프라이트가 비치므로
    /// material 을 한 겹 깔아 대비를 확보한다(로그는 카드 배경 위라 필요 없었다).
    private var raisingBadge: some View {
        Text(store.l.dexRaising.uppercased())
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .background(.regularMaterial, in: Capsule())
    }

    /// 툴팁과 접근성 라벨이 같은 문장을 쓴다 — 칸이 글자로 못 보여주는 희귀도를 담는다.
    /// ✨ 는 이모지라 스크린리더가 일관되게 읽지 못하므로 명사로 함께 넣는다.
    private var tooltip: String {
        var parts = ["#\(species.id) \(species.name)", store.l.rarityLabel(species.rarity)]
        if species.isShiny { parts.append(store.l.dexShinyLabel) }
        if species.isRaising { parts.append(store.l.dexRaising) }
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
    @State private var resolved: [Int: String] = [:]

    /// 카드 안쪽 여백. 진화 라인이 쓸 수 있는 폭 계산과 단일 소스를 공유한다.
    private static let cardPadding: CGFloat = 8

    var body: some View {
        // 저장분 우선(즉시·언어대응), 없으면 async 로 채운 resolved 사용.
        let names = resolved.isEmpty ? store.dexStoredChainNames(entry) : resolved
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(store.l.rarityLabel(entry.rarity).uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(rarityColor(entry.rarity)).foregroundStyle(.white)
                    .clipShape(Capsule())
                if store.isActiveDexEntry(entry) {
                    Text(store.l.dexRaising.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.14))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
                if entry.isShiny {
                    // 이모지는 스크린리더가 일관되게 읽지 못해 명사 라벨을 붙인다(도감 칸과 동일 규칙).
                    Text("✨").font(.system(size: 10))
                        .accessibilityLabel(store.l.dexShinyLabel)
                }
                Spacer()
                if let nature = entry.nature {
                    Text(nature.name(store.language))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            EvoLineView(nodes: entry.chainOrder.map { EvoLineItem(.species($0), .done) },
                        mysteryLabel: store.l.unknownNextEvolution, thumb: 56,
                        shiny: entry.isShiny, names: names,
                        maxWidth: PopoverMetrics.contentWidth - Self.cardPadding * 2)
            if let caughtAt = entry.caughtAt {
                Text(caughtAt, style: .relative).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(Self.cardPadding)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: "\(entry.id)-\(store.language.rawValue)") {
            if store.dexStoredChainNames(entry) == nil {   // 저장분 없으면(구버전) 조회
                resolved = await store.dexResolveChainNames(entry)
            }
        }
    }
}
