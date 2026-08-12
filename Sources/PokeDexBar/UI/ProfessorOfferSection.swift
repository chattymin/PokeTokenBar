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
    /// 카드를 열었을 때 연출을 띄워 달라고 상점에 알린다 — 오버레이는 상점이 소유한다
    /// (알 뽑기 결과가 쓰는 그 자리이고, 섹션 안에 덮으면 카드 세 장 위에만 깔린다).
    var onReveal: (Grade, Bool) -> Void = { _, _ in }

    /// 받아 온 후보. 네트워크로 오므로 처음엔 비어 있고, 그동안은 준비 중이라고 적는다.
    @State private var index: [BaseSpecies] = []

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

    @ViewBuilder
    private func card(_ offer: ProfessorOffer) -> some View {
        let individual = offer.individual
        if !offer.opened {
            // 박사가 아직 들고 있다 — 얼굴을 흐리게 깔아 "누가 쥐고 있는지"만 말하고
            // 무엇인지는 아무것도 안 말한다.
            Button {
                if let taken = store.openProfessorOffer(offerID: offer.id) {
                    onReveal(taken.grade, taken.showsShiny)
                }
            } label: {
                VStack(spacing: 3) {
                    ProfessorIcon(size: 30).opacity(0.35)
                    Text(Self.closedCardText(l: l))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        } else {
            let price = ProfessorBalance.price(grade: individual.grade)
            let affordable = store.state.researchPoints >= price
            VStack(spacing: 3) {
                SpriteView(speciesID: individual.displaySpeciesID, form: individual.spriteForm,
                           size: 40, shiny: individual.showsShiny)
                    .frame(width: 40, height: 40)
                Text(name(individual))
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(individual.grade.label(store.language))
                    .font(.system(size: 8)).foregroundStyle(.secondary)
                if offer.claimed {
                    Text(l.offerTaken).font(.system(size: 9)).foregroundStyle(.tertiary)
                } else {
                    ProfessorOfferButton(title: l.offerPrice(price), affordable: affordable) {
                        store.acceptProfessorOffer(offerID: offer.id)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .opacity(offer.claimed ? 0.5 : 1)
            .padding(6)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                // 이로치 표시 — 칸 테두리를 금테로. 박스 칸(`BoxCell`)과 같은 처리를 그대로 쓴다
                // (새 표현을 발명하지 않는다 — 카드마다 이로치가 다른 뜻이 되면 안 된다).
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(individual.showsShiny ? Color.yellow.opacity(0.85) : .clear, lineWidth: 1.2)
            }
            .task(id: individual.displayLineID) {
                // 이름은 네트워크로 온다 — 없으면 요청해 두고, 오는 대로 카드가 채워진다.
                if lines[individual.displayLineID] == nil { onNeedLine(individual.displayLineID) }
            }
        }
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
