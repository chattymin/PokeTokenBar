import SwiftUI

/// 상점 맨 위 "박사의 제안" — 오늘의 3마리와 포인트 잔액.
///
/// 새 탭을 만들지 않는다. 값을 치르고 무언가를 얻는 자리는 이미 상점이고, 포인트 잔액도
/// 지갑 옆에 있어야 두 재화가 서로 다른 것이라는 게 한눈에 보인다.
struct ProfessorOfferSection: View {
    let store: PlayerStore
    /// 베이스 종 인덱스를 받아 올 곳. 상점이 뽑기에 쓰는 것과 같은 프로바이더다.
    let provider: any PokeProviding
    /// 종 번호 → 진화 라인. 카드에 이름을 보여주려면 필요하다(박스·부화 슬롯과 같은 이유 —
    /// 스프라이트만으로는 지역 폼·태생폼처럼 미묘한 리컬러를 구분할 수 없다). 아직 없으면
    /// `onNeedLine` 으로 요청하고 번호로 떨어진다(`Individual.displayName` 의 fallback).
    var lines: [Int: EvoLine] = [:]
    var onNeedLine: (Int) -> Void = { _ in }

    /// 받아 온 후보. 네트워크로 오므로 처음엔 비어 있고, 그동안은 준비 중이라고 적는다.
    @State private var index: [BaseSpecies] = []
    /// 방금 연 카드 — 그 칸 안에서만 고리가 퍼진다.
    ///
    /// **연출은 카드 안에서 끝난다.** 처음엔 알 뽑기의 전면 오버레이(`EggRevealView`)를 그대로
    /// 불렀는데, 그건 화면을 덮고 등급을 선언하는 자리라 "세 칸을 하나씩 뒤집어 본다"는 이 기능의
    /// 리듬을 끊는다. 뒤집는 재미는 카드가 그 자리에 있으면서 바뀌는 데 있다.
    @State private var revealing: UUID?

    /// 열린 카드와 닫힌 카드의 **속 높이**. 둘이 다르면 한 칸을 열 때마다 줄 전체가 들썩인다.
    /// 열린 쪽 내용(스프라이트 40 + 이름·등급 각 10 + 버튼 19 + 간격 3×3)이 이 값을 정한다.
    private static let cardBodyHeight: CGFloat = 88

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // 얼굴이 제목 왼쪽에 온다 — 이 자리가 상점의 다른 진열대가 아니라 **누군가와
                // 거래하는 자리**라는 걸 글자보다 먼저 말한다.
                ProfessorIcon()
                Text(l.professorOffersTitle)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(l.researchPoints(store.state.researchPoints))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if store.state.professorOffers.isEmpty {
                Text(l.professorOffersEmpty)
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            } else {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(store.state.professorOffers) { offer in
                        card(offer)
                    }
                }
            }
        }
        .task {
            // 인덱스는 네트워크로 온다. 늦게 착지해도 안전하다 — `refreshProfessorOffers` 가
            // `professorOfferDate != lastDate` 를 스스로 확인하므로, 이미 준비됐으면 아무것도
            // 안 하고 아직이면 그때 준비한다. 여러 번 불려도 같은 3마리다(`ProfessorRoll`).
            guard index.isEmpty else { return }
            guard let fetched = try? await provider.baseSpeciesIndex(), !fetched.isEmpty else { return }
            guard !Task.isCancelled else { return }   // 팝오버가 닫혔으면 착지하지 않는다
            index = fetched
            store.refreshProfessorOffers(index: fetched)
        }
    }

    /// 닫힌 카드에 적히는 문자열 전부. **순수 함수로 뽑아 두는 이유는 새는지 검사하기 위해서다** —
    /// 종·등급·가격이 한 글자도 안 들어가야 하고, 그건 눈이 아니라 테스트가 봐야 한다.
    nonisolated static func closedCardText(l: L) -> String { l.offerOpen }

    /// 종 번호 → 현지화 이름. 라인이 아직 없으면 요청해 두고 번호로 떨어진다 — 정체를 감추면
    /// (`PlayerStore+Professor.swift` 의 위장 금지 결정과 같은 이유로) 안 된다.
    private func name(_ individual: Individual) -> String {
        let species = PopoverView.speciesName(individual.displaySpeciesID, in: lines, store.language)
            ?? "#\(individual.displaySpeciesID)"
        return individual.displayName(speciesName: species, store.language)
    }

    /// 카드 한 장. **껍데기(높이·여백·배경)는 여기서 한 번만 씌운다** — 열림/닫힘 가지가 각자
    /// 씌우면 둘이 어긋나고, 한 칸 열 때마다 줄 전체가 들썩인다.
    @ViewBuilder
    private func card(_ offer: ProfessorOffer) -> some View {
        Group {
            if !offer.opened { closedBody(offer) } else { openBody(offer) }
        }
        .frame(maxWidth: .infinity, minHeight: Self.cardBodyHeight)
        .padding(6)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            // 이로치 표시 — 칸 테두리를 금테로. 박스 칸(`BoxCell`)과 같은 처리를 그대로 쓴다.
            // **열린 카드에만** 붙는다 — 닫힌 카드에 금테가 뜨면 그게 곧 이로치 힌트다.
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(offer.opened && offer.individual.showsShiny
                              ? Color.yellow.opacity(0.85) : .clear, lineWidth: 1.2)
        }
    }

    /// 아직 안 연 카드. **무엇인지 한 글자도 안 말한다** — 세 칸이 전부 같은 모양이다.
    @ViewBuilder
    private func closedBody(_ offer: ProfessorOffer) -> some View {
        ProfessorClosedOfferButton(offerID: offer.id, text: Self.closedCardText(l: l)) {
            // 상태가 바뀌면서 카드가 통째로 갈리므로, 그 전환에 애니메이션을 건다 —
            // 아래 `openBody` 의 `.transition` 이 이 애니메이션을 타고 스프라이트를 튀어나오게 한다.
            withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                _ = store.openProfessorOffer(offerID: offer.id)
                revealing = offer.id
            }
        }
    }

    @ViewBuilder
    private func openBody(_ offer: ProfessorOffer) -> some View {
        let individual = offer.individual
        let price = ProfessorBalance.price(grade: individual.grade)
        VStack(spacing: 3) {
            SpriteView(speciesID: individual.displaySpeciesID, form: individual.spriteForm,
                       size: 40, shiny: individual.showsShiny)
                .frame(width: 40, height: 40)
                .overlay {
                    if revealing == offer.id {
                        OfferRevealBurst(grade: individual.grade) { revealing = nil }
                    }
                }
            Text(name(individual))
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(individual.grade.label(store.language))
                .font(.system(size: 8)).foregroundStyle(.secondary)
            if offer.claimed {
                Text(l.offerTaken).font(.system(size: 9)).foregroundStyle(.tertiary)
            } else {
                ProfessorOfferButton(title: l.offerPrice(price),
                                     affordable: store.state.researchPoints >= price) {
                    store.acceptProfessorOffer(offerID: offer.id)
                }
            }
        }
        .opacity(offer.claimed ? 0.5 : 1)
        // 열리는 순간 톡 튀어나온다. 나갈 때는 안 쓰이지만(닫히는 일이 없다) 대칭으로 둔다.
        .transition(.scale(scale: 0.55).combined(with: .opacity))
        .task(id: individual.displayLineID) {
            // 이름은 네트워크로 온다 — 없으면 요청해 두고, 오는 대로 카드가 채워진다.
            if lines[individual.displayLineID] == nil { onNeedLine(individual.displayLineID) }
        }
    }
}

/// 카드 안에서 한 번 퍼지는 고리. **등급이 높을수록 고리가 늘고 색이 진해진다** —
/// 알 부화 연출이 쓰는 것과 같은 색 사다리(`EggReveal.stages`)를 그대로 쓰되, 전면 오버레이가
/// 아니라 그 카드 40pt 안에서 끝난다.
///
/// 알 뽑기의 `EggRevealView` 를 안 쓰는 이유: 그건 화면을 덮고 "무엇이 나왔다"를 선언하는
/// 자리다. 여기는 세 칸을 하나씩 뒤집어 보는 리듬이라, 덮어 버리면 그 리듬이 끊긴다.
struct OfferRevealBurst: View {
    let grade: Grade
    let onDone: () -> Void

    @State private var spread: Double = 0

    #if DEBUG
    /// 어느 등급으로 연출이 떴는지 기록한다 — `ProfessorClosedOfferButton` 과 같은 이유다.
    /// 화면에는 고리 몇 개가 퍼질 뿐이라 "그 자리 등급으로 떴는가"를 그림에서 읽어 낼 수 없다.
    @MainActor static var constructed: [Grade] = []
    @MainActor static var isRecording = false
    @MainActor static func resetConstructed() {
        isRecording = true
        constructed = []
    }
    #endif

    init(grade: Grade, onDone: @escaping () -> Void) {
        self.grade = grade
        self.onDone = onDone
        #if DEBUG
        if Self.isRecording { Self.constructed.append(grade) }
        #endif
    }

    private var stages: [RevealStage] { EggReveal.stages(for: grade) }
    private var duration: Double { 0.16 + Double(stages.count) * 0.10 }

    var body: some View {
        ZStack {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                Circle()
                    .strokeBorder(stage.color, lineWidth: 1.6)
                    // 뒤쪽 고리일수록 더 멀리 — 등급이 높으면 퍼짐이 겹쳐 두꺼워 보인다.
                    .scaleEffect(0.35 + spread * (1.5 + Double(index) * 0.35))
                    .opacity((1 - spread) * 0.85)
            }
        }
        .allowsHitTesting(false)
        .task {
            withAnimation(.easeOut(duration: duration)) { spread = 1 }
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000)))
            guard !Task.isCancelled else { return }
            onDone()
        }
    }
}

/// 닫힌 카드의 "열어보기" 버튼. 별도 타입으로 뽑은 이유는 `ProfessorOfferButton` 과 같다 —
/// **배선 자체를 테스트로 잠그기 위해서**다. 닫힌 카드는 세 칸이 일부러 전부 같은 문구를 쓰므로
/// (그게 새지 않는다는 증거다) 화면에 뜬 문자열만으로는 "이 버튼이 몇 번째 자리를 여는지"를
/// 구분할 수 없다 — 그래서 recorder 가 `offerID` 를 문구와 별도로 들고 있어서, 특정 자리를
/// 지목해 "그 버튼을 부르면 그 자리만 열리는가"를 검사할 수 있게 한다.
struct ProfessorClosedOfferButton: View {
    let offerID: UUID
    let text: String
    let action: () -> Void

    #if DEBUG
    @MainActor static var constructed: [(offerID: UUID, action: () -> Void)] = []
    @MainActor static var isRecording = false
    @MainActor static func resetConstructed() {
        isRecording = true
        constructed = []
    }
    #endif

    init(offerID: UUID, text: String, action: @escaping () -> Void) {
        self.offerID = offerID
        self.text = text
        self.action = action
        #if DEBUG
        if Self.isRecording { Self.constructed.append((offerID, action)) }
        #endif
    }

    var body: some View {
        // 껍데기(여백·배경·높이)는 카드 쪽에서 한 번만 씌운다 — 여기서 또 씌우면 열린 카드와
        // 크기가 어긋난다. 박사 얼굴은 안 쓴다: 세 칸에 같은 얼굴이 늘어서면 지저분하고,
        // 얼굴은 이미 섹션 제목 옆에 한 번 있다. 여기 필요한 건 "아직 모른다"는 표시뿐이다.
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: "questionmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 40, height: 40)
                Text(text)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 제안 카드의 구매 버튼. 별도 타입으로 뽑은 이유는 **배선 자체를 테스트로 잠그기 위해서**다 —
/// `DetailActionButton`/`CandyButton` 과 같은 패턴. 값(가격·잔액)은 맞는데 화면이 엉뚱한 제안을
/// 사거나 안 그리는 결함은 순수 함수 테스트로는 못 잡는다.
struct ProfessorOfferButton: View {
    let title: String
    let affordable: Bool
    let action: () -> Void

    #if DEBUG
    @MainActor static var constructed: [(title: String, affordable: Bool, action: () -> Void)] = []
    @MainActor static var isRecording = false
    @MainActor static func resetConstructed() {
        isRecording = true
        constructed = []
    }
    #endif

    init(title: String, affordable: Bool, action: @escaping () -> Void) {
        self.title = title
        self.affordable = affordable
        self.action = action
        #if DEBUG
        if Self.isRecording { Self.constructed.append((title, affordable, action)) }
        #endif
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(affordable ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(affordable ? Color.accentColor : Color.secondary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(!affordable)
    }
}
