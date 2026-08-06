import SwiftUI

/// 박스 — 보유 개체 그리드. 도감이 "종을 모았나"라면 여기는 "무엇을 가졌나"다.
/// 그리드는 한눈에 보는 용도만 맡고, 개체를 만지는 일(파트너 지정·사탕·진화)은 전부
/// `IndividualDetailView` 로 넘긴다 — 중복 개체가 흔해서 행마다 버튼을 늘어놓으면 못 읽는다.
struct BoxTabView: View {
    let store: PlayerStore
    /// 종 번호 → 진화 라인. 없으면 진화 후보를 알 수 없어 진화 버튼 자체를 숨긴다.
    let lines: [Int: EvoLine]
    /// 라인이 없을 때 호출 — 앱이 받아와 `lines` 를 채운다.
    let onNeedLine: (Int) -> Void
    /// 상세를 열어 둔 개체. 팝오버가 소유해 탭을 옮기면 닫힌다.
    @Binding var selection: UUID?

    private var l: L { store.l }

    /// 현재 단계의 경험치 진행도(0…1). 순수 함수라 테스트로 잠근다.
    nonisolated static func progress(_ individual: Individual) -> Double {
        let threshold = ExpBalance.threshold(grade: individual.grade,
                                             stageIndex: individual.stageIndex)
        guard threshold > 0 else { return 0 }
        return min(1, max(0, Double(individual.exp) / Double(threshold)))
    }

    /// 최근 획득 순.
    private var sorted: [Individual] {
        store.state.box.sorted { $0.obtainedAt > $1.obtainedAt }
    }

    /// 선택된 개체를 **id 로 다시 찾는다** — 진화하면 speciesID 가 바뀌고 정렬 순서도 바뀌므로
    /// 인덱스나 값 복사본을 들고 있으면 상세가 옛 모습에 머문다.
    private var selected: Individual? {
        selection.flatMap { id in store.state.box.first { $0.id == id } }
    }

    private let columns = Array(repeating: GridItem(.fixed(56), spacing: 6), count: 5)

    var body: some View {
        Group {
            if let selected {
                IndividualDetailView(store: store, individual: selected,
                                     line: lines[selected.baseID],
                                     onNeedLine: onNeedLine,
                                     onBack: { selection = nil })
            } else {
                grid
            }
        }
        .frame(height: 320)
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(l.box).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(l.boxCount(store.state.box.count))
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            if store.state.box.isEmpty {
                Spacer()
                Text(l.boxEmpty)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(sorted) { individual in
                            BoxCell(individual: individual,
                                    regionLabel: individual.region?.shortLabel(store.language),
                                    isPartner: individual.id == store.state.partnerID,
                                    hasRibbon: individual.ribbon(at: store.currentDate()) != nil,
                                    canEvolve: readyToEvolve(individual),
                                    progress: Self.progress(individual),
                                    partnerBadge: l.partnerBadge) {
                                selection = individual.id
                            }
                            // 진화 가능 표시를 그리려면 라인이 필요하다 — 보이는 칸만 요청한다.
                            .task(id: individual.baseID) {
                                if lines[individual.baseID] == nil { onNeedLine(individual.baseID) }
                            }
                        }
                    }
                }
            }
        }
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
    /// 지방 표시(`알로라`). 원종이면 nil — 칸이 좁아 있을 때만 보여준다.
    let regionLabel: String?
    let isPartner: Bool
    /// 리본을 하나라도 단 개체 — 칸에서 바로 보여야 "오래 데리고 다닌 아이"가 구분된다.
    let hasRibbon: Bool
    let canEvolve: Bool
    let progress: Double
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

    init(individual: Individual, regionLabel: String? = nil, isPartner: Bool,
         hasRibbon: Bool = false, canEvolve: Bool, progress: Double, partnerBadge: String,
         onTap: @escaping () -> Void) {
        self.individual = individual
        self.regionLabel = regionLabel
        self.isPartner = isPartner
        self.hasRibbon = hasRibbon
        self.canEvolve = canEvolve
        self.progress = progress
        self.partnerBadge = partnerBadge
        self.onTap = onTap
        #if DEBUG
        if Self.isRecording { Self.constructed.append((individual.id, onTap)) }
        #endif
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 1) {
                ZStack(alignment: .topTrailing) {
                    SpriteView(speciesID: individual.speciesID, form: individual.spriteForm,
                               size: 40, shiny: individual.shiny)
                        .frame(width: 40, height: 40)
                    if let regionLabel {
                        // 칸 폭(56pt)을 넘지 않게 잠근다 — "Galarian" 처럼 긴 이름이 타일 밖으로
                        // 삐져나오면 옆 칸과 겹쳐 보인다.
                        Text(regionLabel)
                            .font(.system(size: 6, weight: .bold))
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .padding(.horizontal, 3).padding(.vertical, 0.5)
                            .background(Color.secondary.opacity(0.45), in: Capsule())
                            .frame(maxWidth: 50)
                            .offset(x: 5, y: 30)
                    }
                    // 진화 가능은 칸에서 바로 보여야 한다 — 아니면 개체를 하나씩 열어봐야 안다.
                    if hasRibbon {
                        Text("🎗").font(.system(size: 9)).offset(x: -16, y: -13)
                    }
                    if canEvolve {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                            .offset(x: 3, y: -2)
                    }
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 40, height: 3)
                Text(isPartner ? partnerBadge : "#\(individual.speciesID)")
                    .font(.system(size: 7, weight: isPartner ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isPartner ? Color.accentColor : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 56, height: 60)
            .background(Color.secondary.opacity(isPartner ? 0.16 : 0.07),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if individual.shiny {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.yellow.opacity(0.8), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
