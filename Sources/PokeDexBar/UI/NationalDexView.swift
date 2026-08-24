import SwiftUI

/// 도감 — 1번부터 마지막 종까지 번호순 그리드. 희귀도로 나누지 않는다.
/// 읽기 전용이다(개체를 만지는 일은 박스에서 한다).
///
/// 1025칸을 한 번에 그리면 팝오버가 버벅이므로 `LazyVGrid` 로 보이는 칸만 만든다 —
/// 스프라이트 요청도 화면에 들어온 칸에서만 나간다.
///
/// 폼은 종 단위 칸 안에 접혀 있다 — 태생 폼이 여럿인 종(지방 모습·태생 무늬)은 칸을 탭하면
/// 폼 목록 상세가 열리고, 등록한 폼만 그림이 보인다(미등록은 실루엣 + 이름).
struct NationalDexView: View {
    let store: PlayerStore
    /// 알 보상 수령에 필요한 종 인덱스(네트워크). 스크린샷·테스트는 안 넘긴다 —
    /// 그때 알 미션 수령은 실패 문구로 떨어질 뿐 화면은 그대로 선다.
    let provider: (any PokeProviding)?

    nonisolated static let speciesRange = DexKey.speciesRange

    nonisolated static func progressText(caught: Int) -> String {
        "\(caught) / \(speciesRange.count)"
    }

    /// 칸의 순수 판정 — 원종을 보유했으면 종 기본 그림, 아니면 보유한 첫 폼(후보 순서),
    /// 아무것도 없으면 실루엣. 뷰 밖 static 이라 테스트가 호스트 없이 잠근다.
    nonisolated static func cellState(speciesID: Int, dexForms: Set<String>)
        -> (caught: Bool, slug: String?) {
        let owned = DexKey.candidates(speciesID: speciesID).filter { dexForms.contains($0.key) }
        guard !owned.isEmpty else { return (false, nil) }
        if let base = owned.first(where: { $0.slug == nil }) { return (true, base.slug) }
        return (true, owned[0].slug)
    }

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 6), count: 6)

    /// 폼 상세를 열어 둔 종. nil 이면 그리드.
    @State private var detailSpeciesID: Int?

    /// `detailSpeciesID`·`missionsExpanded` 를 심을 수 있는 이니셜라이저 — 스크린샷 생성기가
    /// 탭 없이 그 장면을 렌더하는 데 쓴다(오프스크린 렌더는 제스처를 못 보낸다).
    init(store: PlayerStore, provider: (any PokeProviding)? = nil,
         detailSpeciesID: Int? = nil, missionsExpanded: Bool = false) {
        self.store = store
        self.provider = provider
        _detailSpeciesID = State(initialValue: detailSpeciesID)
        _missionsExpanded = State(initialValue: missionsExpanded)
    }

    // MARK: 미션

    @State private var missionsExpanded = false
    @State private var claimingID: String?
    @State private var missionError: String?
    @State private var claimTask: Task<Void, Never>?

    var body: some View {
        if let speciesID = detailSpeciesID {
            formDetail(speciesID)
        } else {
            grid
        }
    }

    // MARK: 미션 섹션

    /// 접이식 미션 목록 — 수령한 미션은 사라지고, 달성한 미션이 있으면 접혀 있어도 배지가 알린다.
    @ViewBuilder
    private var missionsSection: some View {
        let statuses = store.dexMissionStatuses().filter { !$0.claimed }
        let claimable = statuses.count(where: \.claimable)
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { missionsExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: missionsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    Text(store.l.missionSection).font(.system(size: 10, weight: .semibold))
                    if claimable > 0 {
                        Text(store.l.missionClaimableBadge(claimable))
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if missionsExpanded {
                ForEach(statuses) { status in missionRow(status) }
                if let missionError {
                    Text(missionError).font(.system(size: 8)).foregroundStyle(.orange)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .onDisappear { claimTask?.cancel() }
    }

    private func missionRow(_ status: PlayerStore.DexMissionStatus) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(missionTitle(status.mission))
                        .font(.system(size: 9, weight: .medium))
                    Text("\(status.done)/\(status.target)")
                        .font(.system(size: 8).monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(rewardText(status.mission.rewards))
                    .font(.system(size: 8)).foregroundStyle(.tertiary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(status.claimable ? Color.accentColor : Color.secondary)
                            .frame(width: max(2, geo.size.width
                                * CGFloat(status.done) / CGFloat(max(1, status.target))))
                    }
                }
                .frame(height: 3)
            }
            if status.claimable {
                // 알 보상인데 빈 슬롯이 없으면 스토어 판정이 막는다 — 버튼은 그 판정 그대로.
                Button(claimingID == status.id ? "…" : store.l.missionClaim) { claim(status) }
                    .buttonStyle(.borderedProminent).controlSize(.mini)
                    .disabled(!store.canClaimDexMission(status.mission) || claimingID != nil)
            }
        }
        .padding(.vertical, 2)
    }

    private func missionTitle(_ mission: DexMission) -> String {
        switch mission.kind {
        case .species(let n): store.l.missionSpecies(n)
        case .generation(let n): store.l.missionGeneration(n)
        case .completion: store.l.missionCompletion
        }
    }

    private func rewardText(_ rewards: [DexMissionReward]) -> String {
        rewards.map { reward in
            switch reward {
            case .egg(let grade):
                store.l.missionRewardEgg(grade.label(store.language))
            case .expCandy(let n):
                "\(ShopItem.expCandy.label(store.language)) ×\(n)"
            case .shinyCandy(let n):
                "\(ShopItem.shinyCandy.label(store.language)) ×\(n)"
            case .rainbowCharm:
                ShopItem.rainbowCharm.label(store.language)
            }
        }.joined(separator: " · ")
    }

    /// 수령. 알 보상은 상점 뽑기와 같은 흐름으로 종을 네트워크 인덱스에서 고른다.
    private func claim(_ status: PlayerStore.DexMissionStatus) {
        missionError = nil
        let eggCount = DexMissions.eggCount(in: status.mission.rewards)
        guard eggCount > 0 else {
            if !store.claimDexMission(status.mission) { missionError = store.l.missionNeedsSlot }
            return
        }
        claimingID = status.id
        claimTask = Task {
            defer { claimingID = nil }
            guard let provider,
                  let index = try? await provider.baseSpeciesIndex(), !index.isEmpty else {
                // 그 사이 뷰가 사라져 취소됐으면 착지하지 않는다(상점 뽑기와 같은 규칙).
                guard !Task.isCancelled else { return }
                missionError = store.l.shopDrawFetchFailed
                return
            }
            guard !Task.isCancelled else { return }
            var picks: [(speciesID: Int, growthRate: GrowthRate)] = []
            for reward in status.mission.rewards {
                guard case .egg(let grade) = reward else { continue }
                let species = EggBalance.pickSpecies(from: index, grade: grade,
                                                     roll: store.nextRandomUnit())
                picks.append((species,
                              index.first(where: { $0.id == species })?.growthRate ?? .mediumFast))
            }
            if !store.claimDexMission(status.mission, eggSpecies: picks) {
                missionError = store.l.missionNeedsSlot
            }
        }
    }

    // MARK: 그리드

    private var grid: some View {
        // 저장 집합을 셀마다 다시 읽지 않게 진입에서 한 번만 꺼낸다.
        let dexForms = store.state.dexForms
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(store.l.collection).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(Self.progressText(caught: store.state.dex.count))
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    missionsSection
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Self.speciesRange, id: \.self) { id in
                            cell(id, dexForms: dexForms)
                        }
                    }
                }
            }
            .frame(height: 300)
        }
    }

    private func cell(_ speciesID: Int, dexForms: Set<String>) -> some View {
        let state = Self.cellState(speciesID: speciesID, dexForms: dexForms)
        let hasFormRows = DexKey.candidates(speciesID: speciesID).count > 1
        return VStack(spacing: 1) {
            // 못 잡은 종은 실루엣 — 모습은 보이되 정체는 가린다.
            SpriteView(speciesID: speciesID, form: state.slug, size: 32, silhouette: !state.caught)
                .frame(width: 32, height: 32)
                .opacity(state.caught ? 1 : 0.55)
            Text("\(speciesID)")
                .font(.system(size: 7)).monospacedDigit()
                .foregroundStyle(state.caught ? .secondary : .tertiary)
        }
        .frame(width: 44, height: 46)
        .background(Color.secondary.opacity(state.caught ? 0.10 : 0.04),
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { if hasFormRows { detailSpeciesID = speciesID } }
    }

    // MARK: 폼 상세

    private func formDetail(_ speciesID: Int) -> some View {
        let candidates = DexKey.candidates(speciesID: speciesID)
        let dexForms = store.state.dexForms
        let ownedCount = candidates.filter { dexForms.contains($0.key) }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    detailSpeciesID = nil
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                Text("#\(speciesID)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                Spacer()
                Text(store.l.dexFormProgress(ownedCount, candidates.count))
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(candidates, id: \.key) { candidate in
                        formRow(speciesID: speciesID, candidate: candidate,
                                owned: dexForms.contains(candidate.key))
                    }
                }
            }
            .frame(height: 300)
        }
    }

    /// 폼 한 행 — 등록이면 그림 + 이름, 미등록이면 실루엣 + 이름. **이름은 가리지 않는다** —
    /// 뭘 모아야 하는지가 보여야 수집 목표가 된다(실루엣이 모습만 가린다).
    private func formRow(speciesID: Int, candidate: DexFormCandidate, owned: Bool) -> some View {
        HStack(spacing: 8) {
            SpriteView(speciesID: speciesID, form: candidate.slug, size: 32, silhouette: !owned)
                .frame(width: 32, height: 32)
                .opacity(owned ? 1 : 0.55)
            Text(candidate.label?.text(store.language) ?? store.l.dexBaseForm)
                .font(.system(size: 10))
                .foregroundStyle(owned ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(owned ? 0.10 : 0.04),
                    in: RoundedRectangle(cornerRadius: 6))
    }
}
