import SwiftUI

func rarityColor(_ r: Rarity?) -> Color {
    switch r {
    case .uncommon: return .green
    case .rare: return .blue
    case .legendary: return .orange
    default: return .gray
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
    @State private var img: NSImage?
    @State private var up = false
    @State private var loadedID: Int?   // img 가 어느 speciesID 것인지(id 변경 시 갱신 판단)
    @State private var frames: [(image: NSImage, delay: TimeInterval)] = []
    @State private var frameIndex = 0

    init(speciesID: Int?, size: CGFloat = 84, bob: Bool = false, animated: Bool = false, shiny: Bool = false) {
        self.speciesID = speciesID
        self.size = size
        self.bob = bob
        self.animated = animated
        self.shiny = shiny
        // 캐시에 있으면 즉시(동기) 표시 — 재렌더 플래시 방지 + 정적 스냅샷에서도 보임
        let cached = speciesID.flatMap { SpriteLoader.cachedImage(speciesID: $0, shiny: shiny) }
        _img = State(initialValue: cached)
        _loadedID = State(initialValue: cached != nil ? speciesID : nil)
    }

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
            guard let id = speciesID else { img = nil; loadedID = nil; return }
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
                let delay = frames[frameIndex % frames.count].delay
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
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
struct EvoLineView: View {
    let nodes: [(id: Int, kind: String)]
    var thumb: CGFloat = 40
    var shiny: Bool = false     // 개체가 shiny 면 라인 전체를 shiny 스프라이트로
    var names: [Int: String]? = nil   // 제공되면 각 스프라이트 밑에 작은 이름 라벨(도감 단계별 이름)
    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { i, node in
                if i > 0 {
                    Image(systemName: "arrow.right").font(.system(size: thumb * 0.2))
                        .foregroundStyle(.tertiary).padding(.top, thumb * 0.4)   // 스프라이트 세로 중앙에 정렬
                }
                VStack(spacing: 1) {
                    SpriteView(speciesID: node.id, size: thumb, shiny: shiny)
                        .opacity(node.kind == "future" ? 0.32 : 1)
                        .saturation(node.kind == "future" ? 0.4 : 1)
                        .overlay(alignment: .bottom) {
                            if node.kind == "cur" {
                                Circle().fill(Color.accentColor).frame(width: 4, height: 4).offset(y: 2)
                            }
                        }
                    if let names {
                        Text(names[node.id] ?? "…")
                            .font(.system(size: 8)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: thumb + 6)
                    }
                }
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
    @State private var seenSeq = -1     // 재생 완료한 celebrationSeq (팝오버 재오픈 시 1회 재생 보장)
    @State private var eggWiggle = false
    // 사탕 "+XP" 순간 표시 (진화 없이 부분 진행일 때도 피드백)
    @State private var seenCandySeq = -1
    @State private var candyXPShown = false
    @State private var candyXPAmount = 0     // 표시 순간 캡처(consume 후에도 텍스트 유지)

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
                        if candyXPShown {
                            Text("+\(TokenFormatter.compact(candyXPAmount)) XP")
                                .font(.caption.weight(.bold)).foregroundStyle(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.regularMaterial, in: Capsule())
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .offset(y: -16)
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
                EvoLineView(nodes: store.lineNodes, shiny: store.currentIsShiny)
            }
            if let g = store.justGraduated {
                Text(store.l.graduated(g))
                    .font(.caption2).foregroundStyle(.orange)
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

/// 도감 — 잡은 라인(초기→최종 전부) 목록.
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
            // 고정 높이 — maxHeight 는 팝오버 재오픈 시 ScrollView fitting size 가 작게 잡혀
            // 크기가 줄어드는 문제가 있어 height 로 고정한다.
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    DexSummaryHeader(store: store, selected: selectedRarity) { r in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedRarity = (selectedRarity == r) ? nil : r
                        }
                    }
                    ForEach(visibleEntries) { entry in
                        DexEntryRow(store: store, entry: entry)
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
                if entry.isShiny { Text("✨").font(.system(size: 10)) }
                Spacer()
                let nature = entry.nature.map { "\($0.name(store.language)) · " } ?? ""
                Text(nature + store.l.formsComplete(entry.chainOrder.count))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            EvoLineView(nodes: entry.chainOrder.map { ($0, "done") }, thumb: 56,
                        shiny: entry.isShiny, names: names)
            if let caughtAt = entry.caughtAt {
                Text(caughtAt, style: .relative).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: "\(entry.id)-\(store.language.rawValue)") {
            if store.dexStoredChainNames(entry) == nil {   // 저장분 없으면(구버전) 조회
                resolved = await store.dexResolveChainNames(entry)
            }
        }
    }
}
