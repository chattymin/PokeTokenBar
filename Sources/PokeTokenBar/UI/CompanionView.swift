import SwiftUI

func rarityColor(_ r: Rarity?) -> Color {
    switch r {
    case .uncommon: return .green
    case .rare: return .blue
    case .legendary: return .orange
    default: return .gray
    }
}

/// 아이템 아이콘 — 실제 스프라이트(런타임 로드+캐시) 우선, 로딩 전/미제공/실패 시 이모지 폴백.
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
                Image(nsImage: img).resizable().interpolation(.none)
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

/// 스프라이트 1개(런타임 로드 + 캐시). 없으면 알 글리프. bob 으로 가벼운 상하 움직임.
/// animated=true 면 Gen-V GIF 프레임을 순환(미지원/오프라인이면 정적+bob 으로 폴백).
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
    }

    /// 프레임 지속(초) = max(원본 delay, 하한). 순수·테스트용 — fps 상한 회귀 가드.
    static func frameDelay(base: TimeInterval, floor: TimeInterval) -> TimeInterval { max(base, floor) }

    var body: some View {
        Group {
            if !frames.isEmpty {
                // GIF 애니메이션 경로 — 현재 프레임만 렌더
                Image(nsImage: frames[frameIndex % frames.count].image)
                    .resizable().interpolation(.none)
                    .frame(width: size, height: size)
            } else if let img {
                Image(nsImage: img).resizable().interpolation(.none)
                    .frame(width: size, height: size)
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
                if img == nil { img = await SpriteLoader.eggImage() }
                loadedID = nil
                return
            }
            // 정적 스프라이트 먼저(즉시 표시 + 폴백 보장). 캐시 시드로 이미 같은 id 면 재요청 생략(플래시 방지)
            if loadedID != id {
                img = await SpriteLoader.image(speciesID: id, animated: false, shiny: shiny)
                loadedID = id
            }
            guard animated else { return }
            // animated GIF 시도(shiny 미제공 종은 일반 GIF 폴백) → 프레임 2개 이상이면 순환 루프
            var gifData = await SpriteStore.shared.data(speciesID: id, animated: true, shiny: shiny)
            if gifData == nil, shiny {
                gifData = await SpriteStore.shared.data(speciesID: id, animated: true, shiny: false)
            }
            guard let data = gifData else { return }
            let raw = GIFDecoder.frames(from: data)
            guard raw.count > 1 else { return }   // 단일 프레임/디코드 실패 → 정적 폴백
            frames = raw
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
    let language: AppLanguage
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
                                .accessibilityLabel(Text(L(language).unknownNextEvolution))
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
                .id(i)   // 셰브론 페이징(ScrollViewProxy.scrollTo) 대상
            }
        }
    }
}

/// 팝오버 상단 — 현재 포켓몬 + 진화 진행 + 부화/진화 연출.
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
                        Text(eggImminent ? store.l.eggImminent : store.l.eggIncubating)
                            .font(.caption2)
                            .foregroundStyle(eggImminent ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
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
                EvoLineView(nodes: store.lineNodes, language: store.language, shiny: store.currentIsShiny,
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

    private var statusLine: String {
        let l = store.l
        switch store.displayState {
        case .egg:     return l.statusEgg
        case .idle:    return l.statusIdle
        case .working: return l.statusWorking
        case .focus:   return l.statusFocus
        case .tired:   return l.statusTired
        case .sleep:   return l.statusSleep
        case .levelUp: return store.justEvolvedTo.map { l.statusEvolved($0) } ?? l.statusGrew
        }
    }
}

/// 희귀도 1종 캡슐 — 색 점 + 라벨 + 개수. 선택 시 원색 링 + 체크마크로 강조.
/// (solid 채움 대신 링+체크 — green/orange 위 흰 텍스트 대비 문제 회피 + 라이트/다크 양쪽 가독.
///  텍스트는 .primary 라 모드 자동 적응, 색 정체성은 점·링·체크로 유지 → 엔트리 배지와 안 어긋남.)
/// 0이면 흐리게(필터 불가).
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

/// 도감 요약 헤더 — 총 개수 + 희귀도별 개수 캡슐.
struct DexSummaryHeader: View {
    let store: CompanionStore
    let selected: Rarity?                  // nil = 필터 없음(전체)
    let onSelect: (Rarity) -> Void         // 캡슐 탭 → 토글
    private let order: [Rarity] = [.legendary, .rare, .uncommon, .common]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(store.l.dexTitle).font(.callout.weight(.semibold))
                Text(store.l.dexTotal(store.dexEntries.count))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(order, id: \.self) { r in
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

/// 도감 — 현재 키우는 포켓몬과 졸업해 영구 보존된 라인 목록.
struct CollectionView: View {
    let store: CompanionStore
    @State private var selectedRarity: Rarity?

    /// 선택된 희귀도만 노출(없으면 전체). 상단 캡슐 토글로 설정.
    private var visibleEntries: [DexEntry] {
        guard let r = selectedRarity else { return store.dexEntriesSorted }
        return store.dexEntriesSorted.filter { $0.rarity == r }
    }

    var body: some View {
        if store.dexEntries.isEmpty {
            emptyState
        } else {
            // 필터(요약 헤더)는 고정, 포켓몬 목록만 스크롤 — 아래로 내리는 중에도 희귀도 필터를 토글할 수 있다.
            VStack(alignment: .leading, spacing: 8) {
                DexSummaryHeader(store: store, selected: selectedRarity) { r in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedRarity = (selectedRarity == r) ? nil : r
                    }
                }
                // 고정 높이 — maxHeight 는 팝오버 재오픈 시 ScrollView fitting size 가 작게 잡혀
                // 크기가 줄어드는 문제가 있어, 바깥 VStack 을 height 로 고정해 스크롤 영역이 나머지를 채우게 한다.
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
            .frame(height: 520)
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

/// 도감 한 항목 — 희귀도·성격 헤더 + 진화 체인 스프라이트(각 밑에 종 이름) + 잡은 시각.
/// 체인 각 종의 이름은 저장분이 있으면 body 에서 즉시(플래시 없음), 없으면(구버전) .task 로 조회 후 백필.
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
                if entry.isShiny { Text("✨").font(.system(size: 10)) }
                Spacer()
                if let nature = entry.nature {
                    Text(nature.name(store.language))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            EvoLineView(nodes: entry.chainOrder.map { EvoLineItem(.species($0), .done) },
                        language: store.language, thumb: 56,
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
