import SwiftUI

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
struct SpriteView: View {
    let speciesID: Int?
    /// 메가·거다이맥스 폼의 Showdown 슬러그. nil 이면 보통 모습.
    var form: String?
    var size: CGFloat = 84
    var bob: Bool = false
    var animated: Bool = false
    var shiny: Bool = false
    /// GIF 프레임 지속의 하한(초). 0=원본 delay 그대로. >0 이면 fps 상한 + wakeup 코얼레싱을 적용해
    /// idle 배터리를 통제한다 — 항상 떠 있는 플로팅 펫(0.4s≈2.5fps)이 메뉴바 GIF 규율과 동치가 되게.
    /// 팝오버 등 일시적 표시는 0(기본)으로 두어 네이티브 fps 유지.
    var minFrameDelay: TimeInterval = 0
    /// 켜면 표시 크기에 맞춰 EPX 로 확대한 뒤 그린다. 기본은 끔 — 도감 썸네일처럼 작은 표시는
    /// 원본 픽셀이 더 또렷하다.
    var antialias: Bool = false
    @State private var img: NSImage?
    @State private var up = false
    @State private var loadedID: Int?   // img 가 어느 speciesID 것인지(id 변경 시 갱신 판단)
    /// img 가 어느 폼의 것인지. 폼이 바뀌어도 speciesID 는 그대로라(메가진화는 같은 종),
    /// loadedID 만 보면 "이미 로드됨"으로 판단해 보통 모습이 그대로 남는다.
    @State private var loadedForm: String?
    @State private var frames: [(image: NSImage, delay: TimeInterval)] = []
    @State private var frameIndex = 0

    #if DEBUG
    /// 테스트 전용 생성 카운터 — 지연 로드(LazyVGrid 등)가 실제로 화면 밖 칸을 안 만드는지 재는 계측.
    /// `@MainActor` 뷰라 실제로는 메인 스레드에서만 증가하므로 락 없는 평범한 static Int 로 충분하다.
    /// DEBUG 빌드에만 존재 — 릴리스 바이너리는 이 카운터를 전혀 담지 않는다.
    @MainActor static var constructionCount = 0
    @MainActor static func resetConstructionCount() { constructionCount = 0 }
    #endif

    init(speciesID: Int?, form: String? = nil, size: CGFloat = 84, bob: Bool = false,
         animated: Bool = false, shiny: Bool = false, minFrameDelay: TimeInterval = 0,
         antialias: Bool = false) {
        self.speciesID = speciesID
        self.form = form
        self.size = size
        self.bob = bob
        self.animated = animated
        self.shiny = shiny
        self.minFrameDelay = minFrameDelay
        self.antialias = antialias
        #if DEBUG
        Self.constructionCount += 1
        #endif
        // 캐시에 있으면 즉시(동기) 표시 — 재렌더 플래시 방지 + 정적 스냅샷에서도 보임.
        // speciesID==nil(알 상태)이면 알 스프라이트를 시드(없으면 body 가 🥚 폴백).
        let cached = speciesID.map { SpriteLoader.cachedImage(speciesID: $0, form: form, shiny: shiny) }
            ?? SpriteLoader.cachedEggImage()
        _img = State(initialValue: cached)
        let seeded = speciesID != nil && cached != nil
        _loadedID = State(initialValue: seeded ? speciesID : nil)
        _loadedForm = State(initialValue: seeded ? form : nil)
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

    /// 표시 크기에 맞는 EPX 패스 수만큼 확대한 이미지. 토글이 꺼져 있으면 원본 그대로.
    private func upscaled(_ image: NSImage) -> NSImage {
        guard antialias else { return image }
        let passes = PixelScale.epxPasses(source: image.size,
                                          in: CGSize(width: size, height: size),
                                          displayScale: NSScreen.main?.backingScaleFactor ?? 2)
        return passes > 0 ? PixelUpscaler.epx(image, passes: passes) : image
    }

    /// 전이 결과를 @State 로 되돌린다(State 세터는 nonmutating). 값이 그대로면 쓰지 않는다 —
    /// @State 는 같은 값을 써도 무효화가 돌아, 항상 떠 있는 펫에 불필요한 재렌더가 생긴다.
    private func apply(_ next: SpriteSubject) {
        guard next != subject else { return }
        img = next.image
        loadedID = next.loadedID
    }

    var body: some View {
        Group {
            if !frames.isEmpty {
                // GIF 애니메이션 경로 — 현재 프레임만 렌더
                Image(nsImage: upscaled(frames[frameIndex % frames.count].image))
                    .resizable().interpolation(.none)
                    .scaledToFit()   // 스프라이트마다 원본 비율이 달라 — 정사각형에 늘리면 찌부된다
                    .frame(width: size, height: size)
            } else if let img {
                Image(nsImage: upscaled(img)).resizable().interpolation(.none)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Text("🥚").font(.system(size: size * 0.62)).frame(width: size, height: size)
            }
        }
        // 세이브를 손으로 고친 흔적 — 모든 스프라이트가 위아래로 뒤집힌 채로 남는다.
        // 게임 진행을 막지는 않는다. 막는 게 아니라 보이게 하는 것이 이 장치의 목적이다.
        // 좌우가 아니라 상하인 이유: 스프라이트는 원래 바라보는 방향이 제각각이라 좌우 반전은
        // 눈에 잘 안 띈다. 상하는 한눈에 이상하다.
        .scaleEffect(x: 1, y: GameIntegrity.isTampered ? -1 : 1)
        // GIF 재생 중엔 bob 정지(프레임 자체가 움직임) — 폴백/정적일 때만 상하 움직임
        .offset(y: bob && frames.isEmpty && up ? -3 : 0)
        .task(id: "\(speciesID.map(String.init) ?? "nil")-\(form ?? "")-\(shiny)") {
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
            // 정적 스프라이트 먼저(즉시 표시 + 폴백 보장). 캐시 시드로 이미 같은 id 면 재요청 생략(플래시 방지)
            if loadedID != id || loadedForm != form {
                let loaded = await SpriteLoader.image(speciesID: id, form: form,
                                                      animated: false, shiny: shiny)
                if let next = subject.applyingLoad(loaded, for: id, cancelled: Task.isCancelled) {
                    apply(next)
                    loadedForm = form
                }
            }
            guard animated else { return }
            // animated GIF 시도(shiny 미제공 종은 일반 GIF 폴백) → 프레임 2개 이상이면 순환 루프
            var gifData = await SpriteStore.shared.data(speciesID: id, form: form,
                                                       animated: true, shiny: shiny)
            if gifData == nil, shiny {
                gifData = await SpriteStore.shared.data(speciesID: id, form: form,
                                                        animated: true, shiny: false)
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
