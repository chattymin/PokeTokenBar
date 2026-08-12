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

    /// 고른 아이들을 보내면 받을 포인트 합.
    @MainActor static func pickedTotal(_ individuals: [Individual], store: PlayerStore) -> Int {
        individuals.reduce(0) { $0 + (store.releaseValue($1) ?? 0) }
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
        .frame(height: 320)
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
                            if selecting {
                                // 못 고르는 아이(파트너)를 눌러도 아무 일도 안 일어난다.
                                guard Self.isPickable(individual, store: store) else { return }
                                if picked.contains(individual.id) {
                                    picked.remove(individual.id)
                                } else {
                                    picked.insert(individual.id)
                                }
                                bulkStep = 0   // 담은 것이 바뀌면 확인은 처음부터
                            } else {
                                selection = individual.id
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
    private var boxHeader: some View {
        HStack(spacing: 8) {
            pageButton(systemName: "chevron.left", enabled: currentPage > 0) {
                page = currentPage - 1
            }
            VStack(spacing: 0) {
                Text(l.boxTitle(currentPage + 1)).font(.system(size: 11, weight: .semibold))
                Text(l.boxSlotUsage(store.state.box.count, Self.pageSize * pageCount))
                    .font(.system(size: 8)).monospacedDigit().foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            pageButton(systemName: "chevron.right", enabled: currentPage < pageCount - 1) {
                page = currentPage + 1
            }
            Button(selecting ? l.bulkDone : l.bulkSelect) {
                selecting.toggle()
                // 모드를 나가면 담은 것도 확인 단계도 비운다 — 다음에 열었을 때 지난 선택이
                // 남아 있으면 무엇을 보내는지 모르는 채로 누르게 된다.
                if !selecting { picked = []; bulkStep = 0 }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.accentColor)
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
        let chosen = store.state.box.filter { picked.contains($0.id) }
        let steps = BulkRelease.confirmSteps(for: chosen)
        VStack(alignment: .leading, spacing: 4) {
            if bulkStep > 0 {
                Text(l.bulkConfirm(chosen.count))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                // 위험한 아이들만 이름으로 — 스무 마리를 다 나열하면 아무도 안 읽는다.
                let names = BulkRelease.risky(chosen).map {
                    $0.displayName(speciesName: Self.speciesName($0, in: lines, store.language),
                                   store.language)
                }
                if !names.isEmpty {
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
                    if bulkStep < steps {
                        bulkStep += 1
                    } else {
                        store.releaseManyToProfessor(individualIDs: Array(picked))
                        // 모드에는 머무른다 — 정리는 보통 한 번에 안 끝나고, 보낸 직후가
                        // 다음 것을 고르기 가장 좋은 순간이다. 담은 것만 비운다.
                        picked = []
                        bulkStep = 0
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
                    // 진화 가능은 칸에서 바로 보여야 한다 — 아니면 개체를 하나씩 열어봐야 안다.
                    if canEvolve {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                            .offset(x: 3, y: -2)
                    }
                    if picked {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
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
