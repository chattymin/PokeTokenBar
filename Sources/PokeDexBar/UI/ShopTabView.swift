import SwiftUI

/// 상점 — 알 뽑기, 슬롯 확장, 아이템. 확률은 그대로 적어 둔다.
struct ShopTabView: View {
    let store: PlayerStore
    let provider: any PokeProviding

    @State private var drawing = false
    @State private var lastError: String?
    /// 뽑기 작업을 뷰 생애에 묶는다 — 안 그러면 팝오버가 닫혔다 다시 열려 새 뷰가 생겨도
    /// 이전 네트워크 조회가 백그라운드에서 계속 돌아 뒤늦게 착지할 수 있다(스타터 픽커와 동일 문제).
    @State private var drawTask: Task<Void, Never>?
    /// 방금 뽑은 결과 — 연출 중에만 non-nil. 알은 이미 슬롯에 들어갔고 이 화면은 그 사실을
    /// 알려주기만 한다(연출을 건너뛰거나 팝오버를 닫아도 잃는 것이 없다).
    @State private var reveal: (grade: Grade, shiny: Bool)?

    private var l: L { store.l }

    /// 뽑기 확률 표기. 밸런스 표에서 만들어 문구와 수치가 어긋나지 않게 한다.
    /// 언어는 필수 인자다(`AppLanguage` 의 "미정" 관례는 `.systemDefault` — `.ko` 를 기본값으로
    /// 두면 이 파일만 다른 컨벤션을 갖게 된다). 화면에서는 스토어 언어를 그대로 넘긴다.
    nonisolated static func oddsText(_ lang: AppLanguage) -> String {
        EggBalance.odds
            .map { "\($0.grade.label(lang)) \(Int($0.probability * 100))%" }
            .joined(separator: " · ")
    }

    /// 뽑기 착지 — 알을 슬롯에 넣고, 못 넣었으면 보여줄 문구를 돌려준다(nil = 성공).
    /// `startEgg` 은 착지 시점에 `canDraw` 가 아니면 nil 을 돌려준다: 후보를 기다리는 동안에도
    /// 슬롯·아이템 버튼은 살아 있어 지갑이 뽑기 값 아래로 내려갈 수 있다. 그 nil 을 버리면
    /// 사용자는 눌렀는데 재화도 안 줄고 알도 안 생기는 침묵을 본다.
    /// 뷰 밖에서 잠글 수 있게 착지 지점만 떼어 둔다(`draw()` 는 네트워크 await 라 통째로는 못 잡는다).
    static func landDraw(_ store: PlayerStore, grade: Grade, speciesID: Int, shiny: Bool) -> String? {
        store.startEgg(grade: grade, speciesID: speciesID, shiny: shiny) == nil
            ? store.l.shopDrawUnavailable : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                walletRow
                drawSection
                slotSection
                categorySection(.candy)
                categorySection(.form)
                categorySection(.charm)
            }
            .padding(.vertical, 2)
        }
        .frame(height: 320)
        // 연출은 상점 위에만 덮인다 — 팝오버 전체를 가리면 탭 전환이 막힌다.
        .overlay {
            if let reveal {
                EggRevealView(grade: reveal.grade, shiny: reveal.shiny, l: l,
                              language: store.language) { self.reveal = nil }
            }
        }
        .onDisappear {
            // 팝오버가 닫혀 뷰가 사라지면 진행 중인 뽑기 조회도 함께 끊는다 — 살려두면
            // 다음에 연 새 뷰의 뽑기와 경합해 조용히 지는 쪽이 생긴다.
            drawTask?.cancel()
        }
    }

    private var walletRow: some View {
        HStack {
            Text(l.shopWallet).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Text(TokenFormatter.compact(store.state.wallet))
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
        }
    }

    private var drawSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(l.shopEggDraw).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(TokenFormatter.compact(EggBalance.drawPrice))
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(Self.oddsText(store.language)).font(.system(size: 9)).foregroundStyle(.tertiary)
            Text(l.shopFreeSlots(store.freeSlots, store.state.slots))
                .font(.system(size: 9)).foregroundStyle(.tertiary)
            if let lastError {
                Text(lastError).font(.system(size: 9)).foregroundStyle(.orange)
            }
            Button(drawing ? l.shopDrawing : l.shopDrawButton) { draw() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!store.canDraw || drawing)
        }
    }

    private var slotSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l.shopSlotSection).font(.system(size: 12, weight: .semibold))
            if let price = store.nextSlotPrice {
                HStack {
                    Text(l.shopSlotUpgrade(store.state.slots, store.state.slots + 1))
                        .font(.system(size: 10))
                    Spacer()
                    Button(TokenFormatter.compact(price)) { _ = store.buySlot() }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(store.state.wallet < price)
                }
            } else {
                Text(l.shopSlotsMaxed)
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    /// 한 분류의 품목들. 목록은 `ShopItem.category` 가 정한다 — 뷰가 품목 이름을 나열하면
    /// 새 품목이 조용히 안 팔리는 일이 생긴다.
    private func categorySection(_ category: ShopCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.title(store.language)).font(.system(size: 12, weight: .semibold))
            ForEach(ShopItem.allCases.filter { $0.category == category }, id: \.self) { item in
                itemRow(item)
            }
        }
    }

    private func itemRow(_ item: ShopItem) -> some View {
        let owned = item.isCharm ? (store.owns(item) ? 1 : 0) : store.count(of: item)
        let soldOut = item.isCharm && store.owns(item)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(item.label(store.language)).font(.system(size: 11, weight: .medium))
                    if owned > 0 {
                        Text(item.isConsumable ? "×\(owned)" : l.shopItemOwned)
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Text(item.detail(store.language)).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(soldOut ? l.shopItemOwnedButton : TokenFormatter.compact(item.price)) { _ = store.buy(item) }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(soldOut || store.state.wallet < item.price)
        }
    }

    /// 등급·이로치를 굴리고, 그 등급 안에서 베이스 종을 포획률 가중으로 고른다(`EggBalance.pickSpecies`).
    /// 후보는 네트워크(베이스 인덱스)라 여기서 받아 스토어에 넘긴다.
    private func draw() {
        drawing = true
        lastError = nil
        drawTask = Task {
            defer { drawing = false }
            let roll = store.rollGradeAndShiny()
            guard let index = try? await provider.baseSpeciesIndex(), !index.isEmpty else {
                // 그 사이 뷰가 사라져 취소됐으면(팝오버 닫힘 등) 착지하지 않는다.
                guard !Task.isCancelled else { return }
                lastError = l.shopDrawFetchFailed
                return
            }
            // 그 사이 뷰가 사라져 취소됐으면(팝오버 닫힘 등) 착지하지 않는다 — 늦게 도착한
            // 조회가 다음 뽑기와 경합해 조용히 이기는 걸 막는다.
            guard !Task.isCancelled else { return }
            let chosen = EggBalance.pickSpecies(from: index, grade: roll.grade, roll: store.nextRandomUnit())
            lastError = Self.landDraw(store, grade: roll.grade, speciesID: chosen, shiny: roll.shiny)
            // 착지에 실패했으면(슬롯이 찼다 등) 축하할 것이 없다 — 문구만 남긴다.
            if lastError == nil { reveal = (roll.grade, roll.shiny) }
        }
    }
}
