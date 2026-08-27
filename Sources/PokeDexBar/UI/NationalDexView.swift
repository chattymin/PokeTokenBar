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
    /// 도감 상세의 프로필(키·몸무게·도감설명)이 네트워크에 산다. 스크린샷·테스트는 안 넘긴다 —
    /// 그때 상세는 로딩 문구까지만 그린다.
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
         detailSpeciesID: Int? = nil, missionsExpanded: Bool = false,
         collectionsExpanded: Bool = false, entrySpeciesID: Int? = nil,
         entryProfile: SpeciesProfile? = nil) {
        self.store = store
        self.provider = provider
        _detailSpeciesID = State(initialValue: detailSpeciesID)
        _missionsExpanded = State(initialValue: missionsExpanded)
        _collectionsExpanded = State(initialValue: collectionsExpanded)
        _entrySpeciesID = State(initialValue: entrySpeciesID)
        _entryProfile = State(initialValue: entryProfile)
    }

    // MARK: 도감 상세(종 항목)

    /// 열려 있는 종 항목. 폼 목록(`detailSpeciesID`)과 별개의 화면이다.
    @State private var entrySpeciesID: Int?
    @State private var entryProfile: SpeciesProfile?
    @State private var entryFailed = false
    @State private var entryTask: Task<Void, Never>?
    /// 도감설명에서 보고 있는 세대. nil 이면 그 언어의 최신 세대.
    @State private var entryGeneration: Int?

    // MARK: 미션

    @State private var missionsExpanded = false
    @State private var collectionsExpanded = false
    @State private var justClaimedCollectionID: String?
    /// 방금 받은 미션 id — "가방에 담았어요" 확인을 그 자리에 잠깐 남긴다. 보상이 전부
    /// 아이템이라 알 연출은 여기 없다 — 확정권의 개봉은 상점의 알 뽑기에서 일어난다.
    @State private var justClaimedID: String?

    var body: some View {
        if let speciesID = detailSpeciesID {
            formDetail(speciesID)
        } else if let speciesID = entrySpeciesID {
            speciesEntry(speciesID)
        } else {
            grid
        }
    }

    // MARK: 미션 섹션

    /// 접이식 미션 목록 — 수령한 미션은 사라지고, 달성한 미션이 있으면 접혀 있어도 배지가 알린다.
    @ViewBuilder
    private var missionsSection: some View {
        let statuses = store.dexMissionStatuses().filter { !$0.claimed || $0.id == justClaimedID }
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
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
            if status.id == justClaimedID {
                // **받아졌다는 확인** — 줄이 말없이 사라지면 버튼이 고장 난 것으로 읽힌다.
                // 확정권·사탕은 가방으로 가므로 어디 갔는지도 이 문구가 말한다.
                Text(store.l.missionClaimedToBag)
                    .font(.system(size: 8, weight: .semibold)).foregroundStyle(Color.accentColor)
            } else if status.claimable {
                Button(store.l.missionClaim) { claim(status) }
                    .buttonStyle(.borderedProminent).controlSize(.mini)
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
            case .eggTicket(let grade):
                ShopItem.eggTicket(for: grade)?.label(store.language) ?? ""
            case .item(let item, let n):
                "\(item.label(store.language)) ×\(n)"
            case .rainbowCharm:
                ShopItem.rainbowCharm.label(store.language)
            case .pokemon(let speciesID, _, _):
                DexMissionReward.speciesName(speciesID, store.language)
            }
        }.joined(separator: " · ")
    }

    /// 수령 — 아이템뿐이라 동기이고 실패할 길이 없다(버튼이 `claimable` 로만 선다).
    /// 받은 줄은 확인 문구를 단 채 잠깐 남았다가, 다음에 열 때 사라진다.
    private func claim(_ status: PlayerStore.DexMissionStatus) {
        guard store.claimDexMission(status.mission) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { justClaimedID = status.id }
    }

    /// 수령 확인 문구 — 포켓몬이 든 보상은 가방이 아니라 **박스**로 가므로 문구가 갈린다
    /// ("가방에 담았어요"가 레지기가스에게는 거짓말이 된다).
    private func claimedText(_ rewards: [DexMissionReward]) -> String {
        let hasPokemon = rewards.contains { if case .pokemon = $0 { true } else { false } }
        return hasPokemon ? store.l.collectionJoinedBox : store.l.missionClaimedToBag
    }

    // MARK: 컬렉션 섹션

    /// 주제별 수집 세트 — 배지는 도감에서 파생되고, 보상 있는 세트만 받기가 있다.
    /// 줄을 누르면 구성원이 펼쳐진다: 잡은 종은 그림, 못 잡은 종은 실루엣 — "뭐가 빠졌나" 가
    /// 이 화면의 존재 이유다.
    @ViewBuilder
    private var collectionsSection: some View {
        let statuses = store.collectionStatuses()
        let claimable = statuses.count(where: \.claimable)
        let badges = statuses.count(where: \.completed)
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { collectionsExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: collectionsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    Text(store.l.collectionSection).font(.system(size: 10, weight: .semibold))
                    Text("\(badges)/\(statuses.count)")
                        .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
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
            if collectionsExpanded {
                ForEach(statuses) { status in collectionRow(status) }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    /// 세트 구성원 띠 — 잡은 종은 컬러, 못 잡은 종은 실루엣. **목록과 도감 상세가 같이 쓴다**
    /// (한쪽만 고쳐지는 부류를 구조로 막는다). `highlight` 는 지금 보고 있는 종 — 상세에서
    /// "이 무리 안의 내 위치" 를 테두리로 표시한다.
    private func collectionMembers(_ entry: CollectionSet, highlight: Int? = nil) -> some View {
        let dex = store.state.dex
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 20), spacing: 2)],
                         alignment: .leading, spacing: 2) {
            ForEach(entry.speciesIDs, id: \.self) { species in
                SpriteView(speciesID: species, size: 18, silhouette: !dex.contains(species))
                    .frame(width: 20, height: 20)
                    .opacity(dex.contains(species) ? 1 : 0.55)
                    .overlay {
                        if species == highlight {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.accentColor, lineWidth: 1)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { openEntry(species) }
            }
        }
    }

    private func collectionRow(_ status: PlayerStore.CollectionStatus) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if status.completed {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 9)).foregroundStyle(Color.yellow)
                }
                Text(CollectionCatalog.label(status.id, store.language))
                    .font(.system(size: 9, weight: .medium))
                Text("\(status.done)/\(status.target)")
                    .font(.system(size: 8).monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                if status.id == justClaimedCollectionID {
                    Text(claimedText(status.collection.rewards))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                } else if status.claimable {
                    Button(store.l.missionClaim) {
                        guard store.claimCollection(status.collection) else { return }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            justClaimedCollectionID = status.id
                        }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.mini)
                }
            }
            // 보상을 적는다 — 안 적었더니 "다 모으면 뭘 주는데?" 가 됐다(사용자 질문).
            // 이제 모든 세트가 보상을 주므로 줄도 항상 나온다.
            Text(rewardText(status.collection.rewards))
                .font(.system(size: 8)).foregroundStyle(.tertiary)
            // 구성원은 **항상 보인다** — 처음엔 줄을 눌러야 펼쳐졌는데, 숨은 기능은 없는
            // 기능이다(사용자 지적). 큰 세트(화석 25종)는 줄바꿈으로 흐른다.
            collectionMembers(status.collection)
        }
        .padding(.vertical, 2)
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
                    collectionsSection
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
        // **모든 칸이 상세를 연다.** 예전에는 모습이 여럿인 종만 폼 목록을 열었고 나머지는
        // 눌러도 아무 일이 없었다 — 이제 종 항목(도감설명·키·몸무게·컬렉션)이 모두에게 있다.
        .onTapGesture { openEntry(speciesID) }
    }

    private func openEntry(_ speciesID: Int) {
        entryProfile = nil
        entryFailed = false
        entryGeneration = nil   // 종을 바꾸면 그 종의 최신 세대부터
        entrySpeciesID = speciesID
        entryTask?.cancel()
        // 미등록 종은 정보를 가리므로 요청도 안 보낸다 — 실루엣에 도감설명을 붙일 일이 없다.
        guard store.state.dex.contains(speciesID), let provider else { return }
        entryTask = Task {
            let profile = try? await provider.speciesProfile(id: speciesID)
            guard !Task.isCancelled else { return }
            // 그 사이 다른 종을 열었으면 착지하지 않는다(늦게 온 조회가 새 화면을 덮는 부류).
            guard entrySpeciesID == speciesID else { return }
            if let profile { entryProfile = profile } else { entryFailed = true }
        }
    }

    // MARK: 종 항목 화면

    /// 한 종의 도감 항목 — 본가 도감 페이지의 축소판. 미등록이면 실루엣 + "???" 로 가린다
    /// (이 앱의 도감 실루엣 규칙 그대로 — 모습은 보이되 정체는 가린다).
    private func speciesEntry(_ speciesID: Int) -> some View {
        let caught = store.state.dex.contains(speciesID)
        let l = store.l
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    entryTask?.cancel()
                    entrySpeciesID = nil
                } label: {
                    Label(l.collection, systemImage: "chevron.left").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("#\(speciesID)")
                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        SpriteView(speciesID: speciesID, size: 72, bob: true,
                                   animated: caught, silhouette: !caught)
                            .frame(width: 72, height: 72)
                        VStack(alignment: .leading, spacing: 3) {
                            // 이름·분류·타입은 전부 프로필(네트워크)에서 온다 — 오기 전엔 번호.
                            Text(caught ? (entryProfile?.name(store.language) ?? "#\(speciesID)")
                                        : l.dexEntryUnknown)
                                .font(.system(size: 13, weight: .semibold))
                            if caught, let profile = entryProfile {
                                Text(profile.genus(store.language))
                                    .font(.system(size: 9)).foregroundStyle(.secondary)
                                Text(profile.typesText(store.language))
                                    .font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }

                    if caught {
                        entryFacts(speciesID)
                    } else {
                        // 미등록 — 본가처럼 아무것도 말하지 않는다. 부화가 곧 열쇠다.
                        Text(l.dexEntryUnknown)
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }

                    // 소속 컬렉션 — 이 종이 어느 이야기의 조각인지. 미등록이어도 보인다:
                    // "얘를 잡으면 클론의 진실이 한 칸 찬다" 가 잡을 이유가 된다.
                    let memberships = CollectionCatalog.containing(species: speciesID)
                    if !memberships.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(l.collectionSection)
                                .font(.system(size: 10, weight: .semibold))
                            ForEach(memberships) { entry in
                                let progress = CollectionCatalog.progress(
                                    of: entry, dex: store.state.dex)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 5) {
                                        if progress.done >= progress.target {
                                            Image(systemName: "medal.fill")
                                                .font(.system(size: 9))
                                                .foregroundStyle(Color.yellow)
                                        }
                                        Text(CollectionCatalog.label(entry.id, store.language))
                                            .font(.system(size: 9, weight: .medium))
                                        Text("\(progress.done)/\(progress.target)")
                                            .font(.system(size: 8).monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    // 목록과 같은 구성원 띠 — 지금 보는 종이 테두리로 서고,
                                    // 다른 칩을 누르면 그 종의 항목으로 건너간다.
                                    collectionMembers(entry, highlight: speciesID)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 8))
                    }

                    // 모습이 여럿이면 폼 목록으로 — 기존 화면을 그대로 잇는다.
                    if DexKey.candidates(speciesID: speciesID).count > 1 {
                        Button(l.dexFormsButton(DexKey.candidates(speciesID: speciesID).count)) {
                            detailSpeciesID = speciesID
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
            .frame(height: 300)
        }
        .onDisappear { entryTask?.cancel() }
    }

    /// 키·몸무게·도감설명 — 네트워크 프로필이 오기 전엔 로딩, 실패면 안내.
    @ViewBuilder
    private func entryFacts(_ speciesID: Int) -> some View {
        let l = store.l
        if let profile = entryProfile {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.dexHeight).font(.system(size: 8)).foregroundStyle(.tertiary)
                    Text(profile.heightText)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.dexWeight).font(.system(size: 8)).foregroundStyle(.tertiary)
                    Text(profile.weightText)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
                Spacer()
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            // **세대별 도감설명** — 세대마다 문장이 다른 것이 본가 도감의 재미라 전부 싣는다
            // (처음엔 최신 한 건만 골랐다가 사용자 지적으로 바꿨다). 한국어는 6세대(X/Y)부터
            // 존재하므로 ko 사용자에게는 6~9세대 칩이 뜬다 — 없는 세대를 영어로 채우기보다
            // "한국어 도감은 여기부터" 를 정직하게 보인다.
            let generations = profile.flavorGenerations(store.language)
            if !generations.isEmpty {
                let shown = entryGeneration.flatMap { generations.contains($0) ? $0 : nil }
                    ?? generations.last!
                HStack(spacing: 4) {
                    ForEach(generations, id: \.self) { generation in
                        Button(l.generationLabel(generation)) {
                            entryGeneration = generation
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 8, weight: shown == generation ? .bold : .regular))
                        .foregroundStyle(shown == generation
                                         ? AnyShapeStyle(Color.accentColor)
                                         : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(shown == generation ? 0.15 : 0.06),
                                    in: Capsule())
                    }
                    Spacer()
                }
                Text(profile.flavor(store.language, generation: shown) ?? "")
                    .font(.system(size: 10))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if entryFailed {
            Text(l.dexEntryUnavailable).font(.system(size: 9)).foregroundStyle(.orange)
        } else {
            Text(l.dexEntryLoading).font(.system(size: 9)).foregroundStyle(.tertiary)
        }
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
