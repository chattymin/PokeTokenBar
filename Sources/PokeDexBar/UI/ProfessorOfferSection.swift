import SwiftUI

/// 상점 맨 위 "박사의 제안" — 오늘의 3마리와 포인트 잔액.
///
/// 새 탭을 만들지 않는다. 값을 치르고 무언가를 얻는 자리는 이미 상점이고, 포인트 잔액도
/// 지갑 옆에 있어야 두 재화가 서로 다른 것이라는 게 한눈에 보인다.
struct ProfessorOfferSection: View {
    let store: PlayerStore
    /// 베이스 종 인덱스를 받아 올 곳. 상점이 뽑기에 쓰는 것과 같은 프로바이더다.
    let provider: any PokeProviding

    /// 받아 온 후보. 네트워크로 오므로 처음엔 비어 있고, 그동안은 준비 중이라고 적는다.
    @State private var index: [BaseSpecies] = []

    private var l: L { store.l }

    /// 살 수 있나. 순수 함수라 뷰 없이 테스트로 잠근다.
    nonisolated static func canAfford(price: Int, points: Int) -> Bool { points >= price }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(l.professorOffersTitle)
                    .font(.system(size: 11, weight: .semibold))
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

    @ViewBuilder
    private func card(_ offer: ProfessorOffer) -> some View {
        let individual = offer.individual
        let price = ProfessorBalance.price(grade: individual.grade)
        let affordable = Self.canAfford(price: price, points: store.state.researchPoints)
        VStack(spacing: 3) {
            SpriteView(speciesID: individual.displaySpeciesID, form: individual.spriteForm,
                       size: 40, shiny: individual.showsShiny)
                .frame(width: 40, height: 40)
            Text(individual.grade.label(store.language))
                .font(.system(size: 8)).foregroundStyle(.secondary)
            if offer.claimed {
                Text(l.offerTaken).font(.system(size: 9)).foregroundStyle(.tertiary)
            } else {
                Button { store.acceptProfessorOffer(offerID: offer.id) } label: {
                    Text(l.offerPrice(price))
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
        .frame(maxWidth: .infinity)
        .opacity(offer.claimed ? 0.5 : 1)
        .padding(6)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}
