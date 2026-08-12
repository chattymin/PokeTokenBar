import SwiftUI

/// 박스 — 보관함. 도감이 "종을 모았나"라면 여기는 "무엇을 가졌나"다.
/// 본가 PC 처럼 **고정 30칸(6×5) 한 상자**를 페이지로 넘긴다. 가진 만큼만 흐르는 그리드는
/// 목록으로 보이지 보관함으로 안 보인다 — 빈 칸이 보여야 "여기 채워 넣는 곳"이 된다.
/// 칸은 보는 용도만 맡고, 개체를 만지는 일(파트너 지정·사탕·진화)은 전부
/// `IndividualDetailView` 로 넘긴다 — 중복 개체가 흔해서 칸마다 버튼을 늘어놓으면 못 읽는다.
struct BoxTabView: View {
    let store: PlayerStore
    /// 종 번호 → 진화 라인. 없으면 진화 후보를 알 수 없어 진화 버튼 자체를 숨긴다.
    let lines: [Int: EvoLine]
    /// 라인이 없을 때 호출 — 앱이 받아와 `lines` 를 채운다.
    let onNeedLine: (Int) -> Void
    /// 상세를 열어 둔 개체. 팝오버가 소유해 탭을 옮기면 닫힌다.
    @Binding var selection: UUID?
    /// 스프라이트를 칸에 꽉 채울지(설정).
    var fillFrame = true

    private var l: L { store.l }

    /// 경험치 진행도(0…1). 순수 함수라 테스트로 잠근다.
    ///
    /// **무엇을 향한 진행인지는 개체마다 다르다.** 진화할 곳이 남았으면 다음 단계까지고, 더 갈
    /// 곳이 없으면 다음 알까지다. 전에는 늘 진화 임계를 분모로 썼는데, 최종형은 그 값을 이미
    /// 지나 있어 막대가 100%에 붙은 채 아무 뜻도 없었다 — 경험치는 계속 오르는데 바는 안 움직였다.
    ///
    /// 분모는 `IndividualDetailView.expThreshold` 한 곳에서만 정한다. 상세 화면과 홈이 같은
    /// 개체를 다른 퍼센트로 그리면 안 된다.
    ///
    /// - Parameter isFoundEggCandidate: 더 진화할 곳이 없고 위장 중도 아닌가.
    ///   판정에 `EvoLine`(네트워크)이 필요해 호출부가 넘긴다.
    nonisolated static func progress(_ individual: Individual, isFoundEggCandidate: Bool) -> Double {
        let threshold = IndividualDetailView.expThreshold(
            individual: individual, isFoundEggCandidate: isFoundEggCandidate)
        guard threshold > 0 else { return 0 }
        return min(1, max(0, Double(individual.exp) / Double(threshold)))
    }

    /// 이 개체를 골라 담을 수 있나. **판정은 `releaseValue` 하나** — 파트너면 nil 이다.
    /// 화면이 "파트너인가"를 따로 적으면 스토어와 갈린다.
    @MainActor static func isPickable(_ individual: Individual, store: PlayerStore) -> Bool {
        store.releaseValue(individual) != nil
    }

    /// 칸을 눌렀을 때 무슨 일이 일어나나. 선택 모드가 곧 안전장치라 — 모드 밖에서는 상세로 가고,
    /// 안에서는 절대 안 간다. 그 판단을 뷰 본문에 두면 테스트가 못 본다.
    enum CellTap: Equatable { case openDetail, toggle, ignore }

    /// 모드 밖에서는 `isPickable` 을 아예 안 본다 — 파트너도 상세는 지금처럼 열려야 한다.
    /// 선택 모드 안에서만 못 고르는 아이(파트너)를 무시한다.
    nonisolated static func cellTap(selecting: Bool, isPickable: Bool) -> CellTap {
        guard selecting else { return .openDetail }
        return isPickable ? .toggle : .ignore
    }

    /// 고른 아이들을 보내면 받을 포인트 합.
    @MainActor static func pickedTotal(_ individuals: [Individual], store: PlayerStore) -> Int {
        individuals.reduce(0) { $0 + (store.releaseValue($1) ?? 0) }
    }

    /// 확인 바의 보내기 버튼을 눌렀을 때 무슨 일이 일어나나 — 다음 확인 단계로 가는지,
    /// 실제로 보내는지. 이 판단을 뷰 클로저 안의 삼항연산자로만 두면, 게이트를 지우고
    /// 첫 클릭에 바로 보내도(`step` 비교를 안 쓰게 고쳐도) 컴파일은 그대로 되고 아무 테스트도
    /// 안 걸린다 — 실제로 `testTheBoxReachesTheBulkPath` 는 `let steps = …` 바인딩이 있다는
    /// 것만 grep 으로 확인해, `steps` 를 한 번도 안 읽어도 통과했다. 이 함수를 따로 빼서
    /// 직접 테스트한다.
    enum BulkSendPress: Equatable { case advance, send }

    nonisolated static func bulkSendPress(step: Int, steps: Int) -> BulkSendPress {
        step < steps ? .advance : .send
    }

    /// 확인 바에 뜨는 문구 — **첫 확인과 마지막 확인이 달라야** 세 번 연타해도 몇 번째
    /// 클릭인지 알 수 있다(이로치가 섞인 배치가 첫 클릭인지 두 번째 클릭인지 모른 채 보내지는
    /// 것이 이 기능의 유일한 진짜 사고다). 문구 자체는 단일 보내기의 `releaseConfirmText` 를
    /// 그대로 재사용한다 — 여기서 세 번째 문구 규칙을 새로 적으면 두 흐름이 갈린다.
    /// 마릿수를 아는 문구(`bulkConfirm`)는 첫 확인에서만 쓴다 — 마지막 확인은 위험한 이름이
    /// 마릿수를 대신하고, 둘 다 적으면 확인 바가 세 줄이 되어 `selectingHeight` 예산을 넘는다.
    nonisolated static func bulkConfirmText(step: Int, count: Int, l: L) -> String {
        step == 1 ? l.bulkConfirm(count) : IndividualDetailView.releaseConfirmText(step: step, l: l)
    }

    /// 선택 모드 스냅샷 — 모드·담은 것·확인 단계. 모드를 나갈 때와 보낸 뒤에 이 셋을
    /// 어떻게 되돌리는지가 스펙의 안전장치라("모드를 나가면 선택이 비워지고, 보낸 뒤에는
    /// 모드는 남고 선택만 비워진다") 뷰의 `@State` 대입 세 줄로만 적으면 그 규칙 자체를
    /// 테스트로 못 잠근다.
    struct BulkSelection: Equatable {
        var selecting: Bool
        var picked: Set<UUID>
        var bulkStep: Int
    }

    /// 「선택」/「완료」 버튼을 눌렀을 때. 들어갈 때는 그대로 두고, 나갈 때만 비운다 —
    /// 다음에 열었을 때 지난 선택이 남아 있으면 뭘 보내는지 모른 채 누르게 된다.
    nonisolated static func afterToggleMode(_ state: BulkSelection) -> BulkSelection {
        var next = state
        next.selecting.toggle()
        if !next.selecting { next.picked = []; next.bulkStep = 0 }
        return next
    }

    /// 보낸 뒤. **모드에는 머무른다** — 정리는 보통 한 번에 안 끝나고, 보낸 직후가 다음 것을
    /// 고르기 가장 좋은 순간이다. 담은 것과 확인 단계만 비운다.
    nonisolated static func afterSend(_ state: BulkSelection) -> BulkSelection {
        var next = state
        next.picked = []
        next.bulkStep = 0
        return next
    }

    /// 획득 순(오래된 것부터). 본가 PC 처럼 **자리가 고정**돼야 보관함으로 읽힌다 —
    /// 최신순이면 한 마리 얻을 때마다 전부 한 칸씩 밀려 어제 본 자리에 없다.
    private var sorted: [Individual] {
        store.state.box.sorted { $0.obtainedAt < $1.obtainedAt }
    }

    /// 상자 하나에 들어가는 칸 수와 배열 — 본가와 같은 6×5.
    nonisolated static let columnCount = 6
    nonisolated static let rowCount = 5
    nonisolated static let pageSize = columnCount * rowCount

    /// 이 마릿수를 담는 데 필요한 상자 수. 비어 있어도 상자 하나는 있다.
    nonisolated static func pageCount(forBoxCount count: Int) -> Int {
        max(1, Int(ceil(Double(count) / Double(pageSize))))
    }

    /// 페이지가 줄어들 때(진화·정리) 현재 페이지가 범위를 벗어나지 않게 자른다.
    nonisolated static func clampedPage(_ page: Int, pageCount: Int) -> Int {
        min(max(0, page), max(0, pageCount - 1))
    }

    /// 선택된 개체를 **id 로 다시 찾는다** — 진화하면 speciesID 가 바뀌고 정렬 순서도 바뀌므로
    /// 인덱스나 값 복사본을 들고 있으면 상세가 옛 모습에 머문다.
    private var selected: Individual? {
        selection.flatMap { id in store.state.box.first { $0.id == id } }
    }

    private let columns = Array(repeating: GridItem(.fixed(48), spacing: 5),
                                count: BoxTabView.columnCount)
    @State private var page = 0
    /// 선택 모드인가. 모드 밖에서는 칸을 누르면 지금처럼 상세로 간다 —
    /// **되돌릴 수 없는 조작으로 가는 문은 눌러서 연다.**
    @State private var selecting = false
    /// 골라 담은 아이들. 페이지를 넘겨도 유지된다 — 30칸을 넘겨 정리하는 것이 이 기능의 이유다.
    @State private var picked: Set<UUID> = []
    /// 확인이 몇 단계까지 진행됐나. 0 이면 아직 안 눌렀다.
    @State private var bulkStep = 0

    /// 선택 모드가 아닐 때의 탭 높이 — 다른 탭(상점·가방)과 같은 320 을 맞춰 탭을 오갈 때
    /// 팝오버가 안 흔들린다. 예산: 헤더(제목 11pt+칸 사용 8pt ≈ 23) + 그리드와의 간격(6) +
    /// 그리드(5행×50 + 4간격×5 + 안쪽 패딩 12 = 282) = 311 — 320 에 9pt 슬랙.
    /// (`assets/screenshot-box.png`, 720×696@2x 실측: 그리드 밴드가 96→660px = 282pt.)
    private static let baseHeight: CGFloat = 320

    /// 선택 모드일 때의 탭 높이. 이 모드는 `bulkBar` 한 덩이가 그대로 얹히므로 밑에서부터
    /// 예산을 다시 쌓아야 한다 — 320 은 고를 칸 수만 생각한 값이라 확인 문구가 들어갈 자리가
    /// 없다(리뷰 실측: 최악의 경우 320 짜리 프레임에 ~366pt 가 들어가려 해서 확인 줄과
    /// 보내기 버튼이 통째로 밖으로 넘쳤다).
    ///
    /// 예산(위 `baseHeight` 의 311 위에 더한다):
    /// - `bulkBar` 자체(간격 6 + 마릿수·보내기 한 줄 ≈ 19) → 311 + 6 + 19 = 336
    /// - 확인 1단계 문구 한 줄 추가(간격 4 + 9pt 텍스트 ≈ 15) → 336 + 15 = 351
    /// - 위험한 아이 이름 줄까지(2단계에서만, 한 번 더 +15) → 351 + 15 = 366
    ///
    /// 366 에 여유(14)를 더해 380 으로 잡는다 — `baseHeight` 의 슬랙(9)과 비슷한 비율이다.
    private static let selectingHeight: CGFloat = 380

    var body: some View {
        Group {
            if let selected {
                IndividualDetailView(store: store, individual: selected,
                                     line: lines[selected.displayLineID],
                                     onNeedLine: onNeedLine,
                                     onBack: { selection = nil })
            } else {
                grid
            }
        }
        // `selected` 가 있을 때는 늘 `selecting == false` 다(상세는 선택 모드 밖에서만 연다) —
        // 그래도 조건은 `selecting` 하나만 본다. 상세 화면은 그리드와 무관하게 항상 기본
        // 높이여야 하는데, `selected != nil` 을 따로 검사하지 않아도 이 불변식 때문에 맞는다.
        //
        // **`alignment: .top` 이 없으면 안 된다.** 기본값은 가운데 정렬이라, 높이가 320↔380 으로
        // 바뀔 때 남는 공간이 위아래로 갈려 헤더와 그리드가 통째로 ~17pt 내려앉는다 — 선택 모드에
        // 들어갈 때 한 번, 확인 단계가 늘 때마다 또. 넘침을 고치면서 흔들림을 들여온 자리였다.
        // 위로 붙여 두면 늘어난 높이는 전부 아래(=`bulkBar` 가 자라는 쪽)로만 간다.
        .frame(height: selecting ? Self.selectingHeight : Self.baseHeight, alignment: .top)
    }

    private var pageCount: Int { Self.pageCount(forBoxCount: store.state.box.count) }
    private var currentPage: Int { Self.clampedPage(page, pageCount: pageCount) }

    /// 이 상자에 놓인 개체들 — 빈 자리는 nil. 고정 30칸이라 뒤가 비어도 칸은 그린다.
    private var slots: [Individual?] {
        let all = sorted
        let start = currentPage * Self.pageSize
        return (0..<Self.pageSize).map { offset in
            let index = start + offset
            return index < all.count ? all[index] : nil
        }
    }

    private var grid: some View {
        VStack(spacing: 6) {
            boxHeader
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(Array(slots.enumerated()), id: \.offset) { _, individual in
                    if let individual {
                        BoxCell(individual: individual,
                                isPartner: individual.id == store.state.partnerID,
                                ribbon: individual.ribbon(at: store.currentDate()),
                                canEvolve: readyToEvolve(individual),
                                partnerBadge: l.partnerBadge,
                                picked: selecting && picked.contains(individual.id),
                                fillFrame: fillFrame) {
                            switch Self.cellTap(selecting: selecting,
                                                isPickable: Self.isPickable(individual, store: store)) {
                            case .openDetail:
                                selection = individual.id
                            case .toggle:
                                if picked.contains(individual.id) {
                                    picked.remove(individual.id)
                                } else {
                                    picked.insert(individual.id)
                                }
                                bulkStep = 0   // 담은 것이 바뀌면 확인은 처음부터
                            case .ignore:
                                break   // 못 고르는 아이(파트너)를 눌러도 아무 일도 안 일어난다.
                            }
                        }
                        // 진화 가능 표시를 그리려면 라인이 필요하다 — 보이는 칸만 요청한다.
                        .task(id: individual.baseID) {
                            if lines[individual.baseID] == nil { onNeedLine(individual.baseID) }
                        }
                    } else {
                        emptySlot
                    }
                }
            }
            .padding(6)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
            }
            if selecting { bulkBar }
            if store.state.box.isEmpty {
                Text(l.boxEmpty).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    /// 상자 이름과 좌우 이동. 상자가 하나뿐이어도 화살표를 비활성으로 남겨 둔다 —
    /// 사라지면 페이지가 늘었을 때 어디를 눌러야 하는지 새로 배워야 한다.
    ///
    /// 제목은 **HStack 흐름 밖에서 overlay 로** 얹는다. 전에는 가운데 `VStack` 이
    /// `maxWidth: .infinity` 로 화살표·선택 버튼과 남는 공간을 나눠 가졌는데, 그러면
    /// 「선택」↔「완료」처럼 라벨 폭이 크게 바뀔 때마다 나눠 갖는 공간 자체가 바뀌어 제목이
    /// 화살표 사이에서 옆으로 튀었다(영어 Select→Done 폭 차가 특히 크다). overlay 는 헤더
    /// 전체 폭을 기준으로 가운데를 잡으므로 옆 버튼 폭과 무관하게 항상 같은 자리다.
    private var boxHeader: some View {
        HStack(spacing: 8) {
            pageButton(systemName: "chevron.left", enabled: currentPage > 0) {
                page = currentPage - 1
            }
            Spacer(minLength: 0)
            pageButton(systemName: "chevron.right", enabled: currentPage < pageCount - 1) {
                page = currentPage + 1
            }
            Button(selecting ? l.bulkDone : l.bulkSelect) {
                let next = Self.afterToggleMode(.init(selecting: selecting, picked: picked,
                                                       bulkStep: bulkStep))
                selecting = next.selecting; picked = next.picked; bulkStep = next.bulkStep
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.accentColor)
        }
        .overlay {
            VStack(spacing: 0) {
                Text(l.boxTitle(currentPage + 1)).font(.system(size: 11, weight: .semibold))
                Text(l.boxSlotUsage(store.state.box.count, Self.pageSize * pageCount))
                    .font(.system(size: 8)).monospacedDigit().foregroundStyle(.tertiary)
            }
            .allowsHitTesting(false)
        }
    }

    private func pageButton(systemName: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 20, height: 18)
                .background(Color.secondary.opacity(enabled ? 0.18 : 0.06),
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .disabled(!enabled)
    }

    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color.secondary.opacity(0.07))
            .frame(width: 48, height: 50)
    }

    /// 고른 아이들을 한 번에 보내는 바. 단일 보내기와 같은 방식으로 **버튼 자리가 확인으로
    /// 바뀐다** — 이 앱에는 확인 다이얼로그 전례가 없고 팝오버 안에서는 help 툴팁 수정자조차 안 뜬다.
    @ViewBuilder
    private var bulkBar: some View {
        // 확인이 실제로 나가는 값은 `picked`(id 집합)가 아니라 **이 `chosen`** 이어야 한다 —
        // 마릿수·포인트·위험 이름이 전부 이걸로 계산되므로, 보내는 것도 같은 값이어야
        // "확인한 것"과 "보낸 것"이 글자 그대로 같다. 오늘은 갈릴 길이 없어도(파트너는 애초에
        // 못 고르고, 없는 id 는 안 담긴다) 되돌릴 수 없는 동작이라 값 하나를 두 번 계산하지 않는다.
        let chosen = store.state.box.filter { picked.contains($0.id) }
        let steps = BulkRelease.confirmSteps(for: chosen)
        // 위험한 아이들만 이름으로 — 스무 마리를 다 나열하면 아무도 안 읽는다. 표식은
        // `BulkRelease.riskyLabel` 한 곳에서만 정한다(단일 소스) — 이로치·전설을 여기서
        // 또 판정하면 위와 갈릴 수 있다.
        let names = BulkRelease.risky(chosen).map { individual in
            BulkRelease.riskyLabel(individual,
                name: individual.displayName(speciesName: Self.speciesName(individual, in: lines,
                                                                            store.language),
                                             store.language),
                l: l)
        }
        VStack(alignment: .leading, spacing: 4) {
            if bulkStep > 0 {
                Text(Self.bulkConfirmText(step: bulkStep, count: chosen.count, l: l))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                // 위험한 이름은 **마지막 확인에서만** — steps 가 2일 때만 도달하는 화면이라,
                // 이름이 뜨는 것 자체가 "왜 한 번 더 묻는지"의 답이자 두 화면을 실제로 가르는
                // 표식이다(첫 확인과 마지막 확인이 항상 같은 두 줄을 보여 주던 게 원래 문제였다).
                if bulkStep == steps, !names.isEmpty {
                    Text(l.bulkConfirmRisky(names.joined(separator: " · ")))
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.orange)
                }
            }
            HStack(spacing: 6) {
                Text(l.bulkPicked(chosen.count, Self.pickedTotal(chosen, store: store)))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
                Spacer()
                if bulkStep > 0 {
                    Button(l.sendCancel) { bulkStep = 0 }
                        .buttonStyle(.plain).font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Button(l.sendNow) {
                    switch Self.bulkSendPress(step: bulkStep, steps: steps) {
                    case .advance:
                        bulkStep += 1
                    case .send:
                        store.releaseManyToProfessor(individualIDs: chosen.map(\.id))
                        let next = Self.afterSend(.init(selecting: selecting, picked: picked,
                                                        bulkStep: bulkStep))
                        selecting = next.selecting; picked = next.picked; bulkStep = next.bulkStep
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(chosen.isEmpty ? Color.secondary : Color.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(chosen.isEmpty ? Color.secondary.opacity(0.15) : Color.accentColor,
                            in: RoundedRectangle(cornerRadius: 5))
                .disabled(chosen.isEmpty)
            }
        }
        .padding(.horizontal, 4)
    }

    /// 종 이름 — 라인이 아직 없으면 번호로 떨어진다(`Individual.displayName` 이 정한 폴백 형식).
    @MainActor static func speciesName(_ individual: Individual, in lines: [Int: EvoLine],
                                       _ lang: AppLanguage) -> String {
        lines[individual.displayLineID]?.localizedName(individual.displaySpeciesID, lang)
            ?? "#\(individual.displaySpeciesID)"
    }

    private func readyToEvolve(_ individual: Individual) -> Bool {
        guard let line = lines[individual.baseID] else { return false }
        return store.canEvolve(individual) && !store.evolutionChoices(individual, line: line).isEmpty
    }
}

/// 그리드 한 칸. 눌러서 상세로 들어가는 유일한 통로라 별도 타입으로 뽑아 테스트로 잠근다
/// (사탕이 상점에서 팔리는데 쓸 화면이 없던 결함이 "배선을 아무도 안 봤다"에서 나왔다).
struct BoxCell: View {
    let individual: Individual
    let isPartner: Bool
    /// 단 리본 — 칸에서 바로 보여야 "오래 데리고 다닌 아이"가 구분되고, 단계까지 읽힌다.
    let ribbon: Ribbon?
    let canEvolve: Bool
    /// 선택 모드에서 담긴 상태인가. 모드 밖에서는 항상 false 다.
    let picked: Bool
    let fillFrame: Bool
    let partnerBadge: String
    let onTap: () -> Void

    #if DEBUG
    @MainActor static var constructed: [(id: UUID, onTap: () -> Void)] = []
    @MainActor static var isRecording = false
    @MainActor static func resetConstructed() {
        isRecording = true
        constructed = []
    }
    #endif

    init(individual: Individual, isPartner: Bool, ribbon: Ribbon? = nil, canEvolve: Bool,
         partnerBadge: String, picked: Bool = false, fillFrame: Bool = true,
         onTap: @escaping () -> Void) {
        self.individual = individual
        self.isPartner = isPartner
        self.ribbon = ribbon
        self.canEvolve = canEvolve
        self.fillFrame = fillFrame
        self.partnerBadge = partnerBadge
        self.picked = picked
        self.onTap = onTap
        #if DEBUG
        if Self.isRecording { Self.constructed.append((individual.id, onTap)) }
        #endif
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    SpriteView(speciesID: individual.displaySpeciesID, form: individual.spriteForm,
                               size: 36, shiny: individual.showsShiny, fillFrame: fillFrame)
                        .frame(width: 36, height: 36)
                        // 리본은 좌측 상단, 진화 가능은 우측 상단 — 양쪽 귀퉁이로 갈라 둬야
                        // 둘 다 붙은 개체에서 서로 겹치지 않는다.
                        .overlay(alignment: .topLeading) {
                            if let ribbon {
                                RibbonIcon(ribbon: ribbon, size: 15).offset(x: -3, y: -2)
                            }
                        }
                        // 담김 표시는 우측 하단 — 위와 같은 이유다. 진화 가능한 아이도 담을 수
                        // 있어서 우측 상단을 같이 쓰면 체크가 화살표를 완전히 가린다.
                        .overlay(alignment: .bottomTrailing) {
                            if picked {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.accentColor)
                                    .offset(x: 3, y: 2)
                            }
                        }
                    // 진화 가능은 칸에서 바로 보여야 한다 — 아니면 개체를 하나씩 열어봐야 안다.
                    if canEvolve {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                            .offset(x: 3, y: -2)
                    }
                }
                // 본가 PC 는 칸에 이름도 게이지도 안 적는다 — 스프라이트가 곧 식별자다.
                // 지금 손댈 수 있는 것(진화 가능)만 표시하고, 진행도는 상세에서 본다.
            }
            .frame(width: 48, height: 50)
            .background(picked ? Color.accentColor.opacity(0.30)
                               : (isPartner ? Color.accentColor.opacity(0.22)
                                            : Color.secondary.opacity(0.16)),
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                // 파트너는 테두리로, 이로치는 금테로 — 이름표가 없으니 칸 자체가 말해야 한다.
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(individual.showsShiny ? Color.yellow.opacity(0.85)
                                                   : (isPartner ? Color.accentColor : .clear),
                                  lineWidth: 1.2)
            }
        }
        .buttonStyle(.plain)
    }
}
