import SwiftUI

/// 개체 상세 — 박스 그리드에서 한 마리를 눌러 들어온다.
/// 개체에 하는 일(파트너 지정·경험치 사탕·반짝이는 사탕·진화)은 전부 여기서만 일어난다.
struct IndividualDetailView: View {
    let store: PlayerStore
    let individual: Individual
    /// 진화 라인. 없으면 후보를 모르니 진화 버튼을 숨긴다(대신 `onNeedLine` 으로 받아온다).
    let line: EvoLine?
    let onNeedLine: (Int) -> Void
    let onBack: () -> Void

    private var l: L { store.l }
    private var isPartner: Bool { individual.id == store.state.partnerID }
    /// 폼 목록을 펼쳤나. 기본은 접힘 — 피카츄 15개·아르세우스 17개가 늘 펼쳐져 있으면
    /// 리본·사탕·진화가 전부 그 아래로 밀려난다.
    @State private var formsExpanded = false
    /// 아직 못 가는 진화 갈래를 펼쳤나. 기본은 접힘 — 이브이는 여덟 갈래 중 넷이
    /// 막혀 있고, 그것들이 펼쳐져 있으면 갈 수 있는 곳이 화면 밖으로 밀린다.
    @State private var blockedEvolutionsExpanded = false
    /// 이로치 반짝임의 방아쇠. 화면에 들어올 때 한 번 올린다 — 계속 반짝이면
    /// 특별하다는 신호가 아니라 배경 장식이 된다.
    @State private var sparkleBeat = 0
    /// 위장 중이 아니고 라인이 있고 더 진화할 곳이 없으면 알 발견 후보다 — `actions` 의 분기와
    /// `canTakeFoundEgg` 가 보는 것과 같은 조건. `expSection`·`foundEggSection` 이 이 값 하나로
    /// 갈려야 두 자리가 다른 답을 하지 않는다.
    private var isFoundEggCandidate: Bool {
        Self.isFoundEggCandidate(hasLine: line != nil, hasEvolutionChoices: !choices.isEmpty,
                                 isDisguised: individual.disguisedAs != nil)
    }

    /// 순수 함수 버전 — 뷰 인스턴스 없이 조건 자체를 테스트로 잠근다.
    nonisolated static func isFoundEggCandidate(hasLine: Bool, hasEvolutionChoices: Bool,
                                                isDisguised: Bool) -> Bool {
        hasLine && !hasEvolutionChoices && !isDisguised
    }

    /// 경험치 막대의 분모 — **무엇을 향한 진행인지**를 정한다. 진화할 곳이 남았으면 다음
    /// 단계까지, 더 갈 곳이 없으면 다음 알까지다.
    ///
    /// 최종형에 진화 임계(등급 기본값 × 3)를 쓰면 이미 지나 버린 값이라 막대가 100%에 붙은 채
    /// 아무 뜻도 없어진다 — 경험치는 오르는데 바는 안 움직인다.
    ///
    /// 상세 화면과 홈(`BoxTabView.progress`)이 **이 함수 하나만** 쓴다. 같은 개체가 두 화면에서
    /// 다른 퍼센트로 보이면 안 된다.
    private var threshold: Int {
        Self.expThreshold(individual: individual, isFoundEggCandidate: isFoundEggCandidate)
    }

    /// 순수 함수 버전.
    nonisolated static func expThreshold(individual: Individual, isFoundEggCandidate: Bool) -> Int {
        isFoundEggCandidate ? ExpBalance.eggThreshold(grade: individual.grade)
                            : ExpBalance.threshold(grade: individual.grade, stageIndex: individual.stageIndex)
    }
    private var choices: [Int] {
        // 위장 중엔 진화를 안 내민다. 이 화면이 받은 라인은 **위장한 종의 것**이라(이름 때문)
        // 정체의 진화 후보가 아니고, 애초에 위장 중인 아이에게 진화를 권하는 것 자체가
        // 정체를 흘리는 일이다.
        guard individual.disguisedAs == nil else { return [] }
        return line.map { store.evolutionChoices(individual, line: $0) } ?? []
    }

    /// 종 이름 — 라인을 아직 못 받았으면 번호로 폴백한다.
    /// 접두는 하나만 붙인다: 메가·거다이맥스를 취하고 있으면 그쪽이, 아니면 지방 이름이.
    private var displayName: String {
        individual.displayName(speciesName: baseName, store.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    portrait
                    facts
                    expSection
                    ribbonSection
                    actions
                }
            }
        }
        .task(id: individual.id) {
            if line == nil { onNeedLine(individual.displayLineID) }
            // 다른 개체를 열면 그 개체의 반짝임이 새로 난다.
            if individual.showsShiny { sparkleBeat += 1 }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                    Text(l.backToBox).font(.system(size: 10))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            Spacer()
        }
    }

    private var portrait: some View {
        HStack(spacing: 10) {
            // 이로치는 초상 둘레가 반짝인다 — 이름 옆 ✨ 는 작아서, 박스에서 열어 보는 순간
            // "이 아이가 그 아이"라는 게 먼저 보여야 한다.
            ZStack {
                if individual.showsShiny {
                    ShinySparkles(specs: SparkleSpec.ring(count: 7, radius: 0.44),
                                  trigger: sparkleBeat)
                        .frame(width: 96, height: 96)
                }
                SpriteView(speciesID: individual.displaySpeciesID, form: individual.spriteForm, size: 72,
                           animated: true, shiny: individual.showsShiny, antialias: true)
                    .frame(width: 72, height: 72)
            }
            .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(displayName).font(.system(size: 13, weight: .semibold))
                    if individual.showsShiny { Text("✨").font(.system(size: 11)) }
                }
                HStack(spacing: 4) {
                    // 위장 중엔 번호도 감춘다 — 이름이 "???" 인데 아래에 번호가 적혀 있으면
                    // 그 번호가 곧 정답이 된다.
                    Text(individual.disguisedAs == nil
                         ? "#\(individual.displaySpeciesID)" : "#\(Individual.unknownName)")
                        .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    if let region = individual.region {
                        Text(region.label(store.language))
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.18), in: Capsule())
                    }
                    if let birth = individual.birthFormLabel(store.language) {
                        Text(birth)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.18), in: Capsule())
                    }
                }
                if isPartner {
                    Text(l.partnerBadge)
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            Spacer()
        }
    }

    private var facts: some View {
        HStack(spacing: 0) {
            fact(l.detailGrade, individual.grade.label(store.language))
            fact(l.detailNature, individual.nature.name(store.language))
            fact(l.detailPartnerTokens, TokenFormatter.compact(individual.partnerTokens))
            fact(l.detailPartnerTime,
                 Individual.togetherText(seconds: individual.partnerDuration(at: store.currentDate()), l))
        }
    }

    /// 리본 — 지금 단계와, 다음 단계까지 얼마나 남았는지.
    @ViewBuilder
    private var ribbonSection: some View {
        let seconds = individual.partnerDuration(at: store.currentDate())
        VStack(alignment: .leading, spacing: 2) {
            if let ribbon = individual.ribbon(at: store.currentDate()) {
                HStack(spacing: 5) {
                    RibbonIcon(ribbon: ribbon, size: 22)
                    Text(ribbon.label(store.language))
                        .font(.system(size: 10, weight: .bold))
                    // 리본이 하는 일 둘을 한 줄로 — 따로 쓰면 세 줄이 되고, 그 아래 폼 목록이
                    // 길어 리본이 화면에서 밀려난다.
                    Text(l.ribbonRate(TokenFormatter.compact(ribbon.tokensPerCandy),
                                      percent: ribbon.foragePermille / 10))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                // 다음 사탕까지 — 리본이 지금 무엇을 채우고 있는지 보이는 유일한 자리다.
                candyProgressRow(ribbon)
                let targets = store.forageTargets(individual)
                if targets.isEmpty {
                    Text(l.ribbonForageDone).font(.system(size: 9)).foregroundStyle(.tertiary)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass").font(.system(size: 8))
                        Text(Self.targetSummary(targets, l)).lineLimit(1)
                    }
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            } else {
                Text(l.ribbonNone).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            if let upcoming = Ribbon.next(after: seconds) {
                Text(l.ribbonNext(upcoming.ribbon.label(store.language),
                                  Individual.togetherText(seconds: upcoming.remaining, l)))
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    /// 다음 사탕까지 얼마나 왔나. 홈 파트너 카드와 같은 부품을 쓴다 — 두 화면이 같은 말을 한다.
    private func candyProgressRow(_ ribbon: Ribbon) -> some View {
        CandyMeter(progress: Self.candyProgress(individual, ribbon),
                   remaining: TokenFormatter.compact(
                       max(0, ribbon.tokensPerCandy - individual.candyProgress)),
                   label: l.ribbonNextCandy)
    }

    /// 0~1. 리본 단계가 올라 필요량이 줄면 이미 쌓은 진행분이 100% 를 넘을 수 있어 자른다.
    nonisolated static func candyProgress(_ individual: Individual, _ ribbon: Ribbon) -> Double {
        guard ribbon.tokensPerCandy > 0 else { return 0 }
        return min(1, max(0, Double(individual.candyProgress) / Double(ribbon.tokensPerCandy)))
    }

    /// 찾는 도구 목록을 한 줄로. 아르세우스는 17개라 전부 적으면 카드가 목록에 잡아먹힌다 —
    /// 앞의 둘만 적고 나머지는 개수로 접는다.
    static func targetSummary(_ names: [String], _ l: L) -> String {
        guard names.count > 2 else { return names.joined(separator: ", ") }
        return names.prefix(2).joined(separator: ", ") + " " + l.ribbonForageMore(names.count - 2)
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 경험치 막대 — 진화할 곳이 있으면 다음 진화 임계, 없으면(알 발견 후보) 알 임계로 찬다.
    /// 예전엔 여기 항상 진화 임계만 그렸다 — 최종형은 못 채우는 막대가 되어(임계가 진화 3단계치)
    /// 그 바로 아래 알 발견 막대와 같은 개체의 같은 경험치를 두 다른 분모로 두 번 보여줬다.
    /// 이제 분모는 `threshold` 하나뿐이다.
    private var expSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(l.detailExp).font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Text("\(TokenFormatter.compact(individual.exp)) / \(TokenFormatter.compact(threshold))")
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: expProgress)
                .progressViewStyle(.linear).frame(height: 5)
            if !isPartner {
                Text(l.detailPartnerOnlyExp)
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    /// 0…1. `threshold` 가 0일 리는 없지만(등급 기본값은 항상 양수) 방어적으로 자른다.
    private var expProgress: Double {
        threshold > 0 ? min(1, max(0, Double(individual.exp) / Double(threshold))) : 0
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isPartner {
                DetailActionButton(title: l.makePartner, prominent: false) {
                    store.setPartner(individual.id)
                }
            }

            if store.canEvolve(individual), !choices.isEmpty, let line {
                evolutionSection(line)
            } else if let line, choices.isEmpty {
                // `foundEggReady` 가 위장 여부까지 본다(`isFoundEggCandidate`) — 위장 중엔
                // 받은 라인이 위장한 종의 것이라(이름 때문) 진짜 최종형인지 알 수 없고,
                // `canTakeFoundEgg` 도 위장 중이면 거절한다. 이 화면도 같은 질문을 해야 한다.
                if foundEggReady {
                    foundEggSection(line)
                } else {
                    Text(l.detailMaxStage).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }

            // 사탕이 폼보다 먼저 — 사탕은 늘 하는 일이고 폼은 도구를 갖춘 뒤에나 누른다.
            // 접힌 폼 섹션 아래에 사탕을 두면 "가진 사탕이 없어요"가 화면 맨 밑에 홀로 떨어진다.
            candySection
            formSection
        }
    }

    /// 알 발견 버튼을 낼 조건 — 후보이고 경험치가 알 임계(=`threshold`, 후보일 때는 알 임계와
    /// 같다)를 채웠을 때. 후보가 아니면 뒤 항은 의미가 없지만 `&&` 가 단락 평가하므로 안전하다.
    private var foundEggReady: Bool { isFoundEggCandidate && individual.exp >= threshold }

    /// 발견되는 알의 종 이름 — 그 개체의 **baseID**(원종)다. 리자몽이 알리는 것은 파이리 알이지
    /// 리자몽 알이 아니다. 라인이 아직 없으면 번호로 폴백한다.
    private var foundEggSpeciesName: String {
        line?.localizedName(individual.baseID, store.language) ?? "#\(individual.baseID)"
    }

    /// 더 진화하지 않는 아이의 경험치가 가는 곳.
    ///
    /// 전에는 여기에 "더 진화하지 않아요" 한 줄만 있었다 — 그 아이의 경험치가 어디로 가는지
    /// 알 길이 없었고, 실제로 아무 데도 안 갔다. 막대는 위 `expSection` 이 이미 알 임계로
    /// 그리므로(`isFoundEggCandidate`) 여기서는 다시 그리지 않는다 — 두 막대가 다른 분모를
    /// 갖고 따로 놀면 임계에 닿았는데 위 막대는 33%인 것처럼 보이는 결함이 난다.
    ///
    /// **버튼 하나가 곧 "받는다" 동작이다** — 누르면 그 자리에서 경험치가 깎이고 알이 부화
    /// 슬롯에 들어간다. 중간에 보관되는 물건은 없다. **빈 슬롯이 없으면 숨기지 않고 비활성으로
    /// 둔다** — 경험치는 그대로 남아 잃는 게 없다는 걸 보여야 한다. `DetailActionButton` 은
    /// 자체 비활성 상태가 없어 `.disabled` + `.opacity` 로 표시한다 — 이 파일의 `formRow` 가
    /// 못 쓰는 폼에 쓰는 것과 같은 관례다.
    @ViewBuilder
    private func foundEggSection(_ line: EvoLine) -> some View {
        // 버튼의 활성 조건은 `canTakeFoundEgg` 하나다 — 뷰가 따로 조건을 만들면 스토어와
        // 갈라질 수 있다(위장 판정이 실제로 한 번 갈렸다).
        let canTake = store.canTakeFoundEgg(individual, line: line)
        VStack(alignment: .leading, spacing: 3) {
            DetailActionButton(title: l.eggFound(foundEggSpeciesName), prominent: true) {
                store.takeFoundEgg(individualID: individual.id, line: line)
            }
            .disabled(!canTake)
            .opacity(canTake ? 1 : 0.55)
            if !canTake {
                Text(l.eggFoundNoFreeSlot).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    /// 진화 — **지금 갈 수 있는 곳만 버튼**이고, 못 가는 곳은 한 줄로 접는다.
    ///
    /// 전에는 갈래마다 전폭 버튼 하나와 "○○의돌 필요 · 파트너로 두면 물어 와요" 한 줄을 냈다.
    /// 이브이는 갈래가 여덟이라 상세가 605pt 가 됐고(팝오버 본문은 320pt), 같은 안내가 네 번
    /// 반복됐다. 폼에서 겪은 것과 같은 병이라 같은 방식으로 고친다 —
    /// **이유는 접힌 줄에 한 번만.**
    ///
    /// 못 가는 곳을 아예 숨기지는 않는다: 글레이시아가 이 게임에 있다는 걸 알 수 없게 된다.
    @ViewBuilder
    private func evolutionSection(_ line: EvoLine) -> some View {
        let open = choices.filter { store.meetsRequirement(store.requirement(for: $0, line: line),
                                                           for: individual) }
        let blocked = choices.filter { !open.contains($0) }
        ForEach(open, id: \.self) { target in
            DetailActionButton(title: choices.count > 1
                               ? l.evolveTo(line.localizedName(target, store.language)) : l.evolve,
                               prominent: true) {
                store.evolve(individualID: individual.id, to: target, line: line)
            }
        }
        if !blocked.isEmpty { blockedEvolutions(blocked, line) }
    }

    /// 아직 못 가는 갈래 — 접으면 필요한 것들만, 펼치면 어디로 가는지까지.
    @ViewBuilder
    private func blockedEvolutions(_ blocked: [Int], _ line: EvoLine) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { blockedEvolutionsExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: blockedEvolutionsExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                Text(l.evolutionLocked(blocked.count)).font(.system(size: 10, weight: .medium))
                if !blockedEvolutionsExpanded {
                    Text(Self.blockedSummary(blocked, line: line, store: store))
                        .font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        if blockedEvolutionsExpanded {
            ForEach(blocked, id: \.self) { target in
                HStack(spacing: 5) {
                    Text(line.localizedName(target, store.language))
                        .font(.system(size: 10))
                    Spacer()
                    Text(Self.shortNeed(store.requirement(for: target, line: line), l: l))
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .padding(.leading, 17)
            }
            // 얻는 방법은 **여기 한 번만** — 갈래마다 붙이면 그 문장이 화면을 먹는다.
            ForEach(Self.blockedHints(blocked, line: line, individual: individual, store: store),
                    id: \.self) { hint in
                Text(hint).font(.system(size: 9)).foregroundStyle(.tertiary)
                    .padding(.leading, 17)
            }
        }
    }

    /// 접힌 줄에 쓸 요약 — 필요한 것들을 중복 없이 나열한다.
    @MainActor static func blockedSummary(_ blocked: [Int], line: EvoLine,
                                          store: PlayerStore) -> String {
        var names: [String] = []
        for target in blocked {
            let name = shortNeed(store.requirement(for: target, line: line), l: store.l)
            if !names.contains(name) { names.append(name) }
        }
        return names.joined(separator: " · ")
    }

    /// 펼쳤을 때 아래에 붙일 안내 — **막힌 갈래가 실제로 기다리는 것만** 말한다. 종류마다 한 줄씩,
    /// 갈래마다가 아니다(이브이는 여덟이라 갈래마다 붙이면 그 문장이 화면을 먹는다).
    ///
    /// 도구 문장을 무조건 내면 조건이 친밀도뿐인 아이(루리리)가 있지도 않은 도구를 기다리는 것처럼
    /// 보인다 — 갈래마다 조건을 보고 쓰던 안내를 섹션에 한 줄로 접으면서 그 조건 분기가 빠졌었다.
    ///
    /// 친밀도 문턱은 종과 무관한 단일 값(`EvoRequirement.friendshipSeconds`)이라, 친밀도 갈래가
    /// 여럿이어도 남은 시간은 하나뿐이다.
    @MainActor static func blockedHints(_ blocked: [Int], line: EvoLine,
                                        individual: Individual, store: PlayerStore) -> [String] {
        let needs = blocked.map { store.requirement(for: $0, line: line) }
        var hints: [String] = []
        if needs.contains(where: { if case .item = $0 { return true } else { return false } }) {
            hints.append(store.l.evolutionLockedHint)
        }
        if needs.contains(.friendship) {
            let remaining = max(0, EvoRequirement.friendshipSeconds
                                - individual.partnerDuration(at: store.currentDate()))
            hints.append(store.l.evolveNeedsTime(
                Individual.togetherText(seconds: remaining, store.l)))
        }
        return hints
    }

    /// 조건을 짧게 — 접힌 줄에 들어가야 하므로 문장이 아니라 이름만.
    nonisolated static func shortNeed(_ need: EvoRequirement, l: L) -> String {
        switch need {
        case .none: ""
        case .item(let item): item.label(l.lang)
        case .friendship: l.evolveNeedsFriendshipShort
        }
    }

    /// 폼 — 그 폼이 있는 종에만 나온다. 못 바꾸는 폼도 **목록에는 남긴다**(빼면 큐레무 블랙이
    /// 이 게임에 있다는 사실 자체를 알 수가 없다). 다만 **이유는 섹션에 한 번만** 적는다:
    /// 피카츄는 15개, 아르세우스는 17개라 폼마다 같은 안내를 붙이면 그 문장이 화면을 통째로
    /// 먹는다(실측: 상세 스크롤 1,800px). 그래서 목록이 길 때만 접는다(`formFoldThreshold`).
    @ViewBuilder
    private var formSection: some View {
        let forms = FormKind.allCases.flatMap { store.formChoices(individual, kind: $0) }
        if !forms.isEmpty {
            let usable = forms.filter { store.canChange(individual, to: $0) }
            if forms.count < Self.formFoldThreshold || formsExpanded {
                if forms.count >= Self.formFoldThreshold { formSectionHeader(forms, usable) }
                // 쓸 수 있는 것이 먼저 — 못 쓰는 걸 위에 두면 매번 지나쳐야 한다.
                ForEach(usable + forms.filter { !usable.contains($0) }, id: \.slug) { form in
                    formRow(form, enabled: usable.contains(form))
                }
            } else {
                formSectionHeader(forms, usable)
            }
        }
        if individual.form != nil {
            DetailActionButton(title: l.revertForm, prominent: false) {
                store.revertForm(individualID: individual.id)
            }
        }
    }

    /// 여섯 이상이면 접는다. 실제 분포가 여기서 딱 갈린다: 96종이 5개 이하이고, 그 위는
    /// 아르세우스·실버디(17)와 피카츄(15) 셋뿐이다. 문턱을 3으로 뒀더니 리자몽(메가 X/Y +
    /// 거다이맥스 = 3)까지 접혀 버렸다 — 짧은 목록을 접는 건 한 번 더 누르게 만들 뿐이다.
    static let formFoldThreshold = 6

    /// 접기 머리줄 — 가진 것/전체와, 무엇이 있어야 열리는지를 **여기 한 번만** 적는다.
    private func formSectionHeader(_ forms: [PokemonForm], _ usable: [PokemonForm]) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { formsExpanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: formsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(l.formSection).font(.system(size: 11, weight: .semibold))
                    Text("\(usable.count)/\(forms.count)")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                }
                if let needs = Self.formNeedSummary(forms, usable: usable, store: store, l: l) {
                    Text(needs).font(.system(size: 9)).foregroundStyle(.tertiary)
                        .padding(.leading, 17)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func formRow(_ form: PokemonForm, enabled: Bool) -> some View {
        let name = form.displayName(base: baseName, store.language)
        return VStack(alignment: .leading, spacing: 2) {
            if enabled {
                FormButton(title: l.changeToForm(name, remaining: formStock(form))) {
                    store.changeForm(individualID: individual.id, to: form)
                }
            } else {
                DetailActionButton(title: name, prominent: false) {}
                    .disabled(true).opacity(0.55)
                // 펼쳤을 때만 폼별 이유를 적는다 — 접힌 머리줄이 이미 요약을 하고 있다.
                Text(formBlockReason(form)).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    /// "변장 트렁크 14 · 다이버섯 1" — 못 여는 폼들이 **무엇을 기다리는지** 도구별로 센다.
    /// 전부 열 수 있으면 nil(할 말이 없다).
    nonisolated static func formNeedSummary(_ forms: [PokemonForm], usable: [PokemonForm],
                                            store: PlayerStore, l: L) -> String? {
        let blocked = forms.filter { !usable.contains($0) }
        guard !blocked.isEmpty else { return nil }
        var counts: [(name: String, count: Int)] = []
        for form in blocked {
            let name = switch form.source {
            case .shop(let item): item.label(l.lang)
            case .foraged(let item): item.label(l.lang)
            }
            if let index = counts.firstIndex(where: { $0.name == name }) { counts[index].count += 1 }
            else { counts.append((name, 1)) }
        }
        return counts.map { "\($0.name) \($0.count)" }.joined(separator: " · ")
    }

    /// 남은 개수 표시용. 물어 온 도구는 없어지지 않으므로 개수가 의미 없어 0 을 돌려
    /// 표기를 생략한다 — "×1" 이 계속 붙어 있으면 소모품으로 오해한다.
    private func formStock(_ form: PokemonForm) -> Int {
        if case .shop(let item) = form.source { return store.count(of: item) }
        return 0
    }

    /// 왜 못 바꾸는가. 도구가 없는 것과 합체 상대가 없는 것은 할 일이 전혀 다르다.
    private func formBlockReason(_ form: PokemonForm) -> String {
        if !store.hasItem(for: form) {
            switch form.source {
            case .shop(let item): return l.formNeedsItem(item.label(store.language))
            case .foraged(let item): return l.formNeedsForagedItem(item.label(store.language))
            }
        }
        let partner = form.fusionPartner.map { line?.localizedName($0, store.language) ?? "#\($0)" }
        return l.formNeedsFusionPartner(partner ?? "")
    }

    /// 폼 접두를 붙이기 전의 종 이름.
    private var baseName: String {
        line?.localizedName(individual.displaySpeciesID, store.language) ?? "#\(individual.displaySpeciesID)"
    }

    /// 사탕 — 상점에서 산 사탕을 쓰는 유일한 화면이다.
    /// 재고가 0이어도 안내를 남긴다(예전엔 줄 자체가 사라져서 어디서 쓰는지 알 수가 없었다).
    @ViewBuilder
    private var candySection: some View {
        let expCandies = store.count(of: .expCandy)
        // 이미 이로치면 반짝이는 사탕은 할 일이 없다 — `useShinyCandy` 도 그 경우 false 를 돌려준다.
        let shinyCandies = individual.shiny ? 0 : store.count(of: .shinyCandy)
        if expCandies > 0 || shinyCandies > 0 {
            if expCandies > 0 {
                // 임계를 넘긴 개체에도 열어 둔다 — `useExpCandy` 는 임계를 보지 않고, 초과분은
                // 진화 때 다음 단계로 이월되므로(`evolve` 의 `exp - threshold`) 낭비가 아니다.
                CandyButton(title: l.useExpCandy(expCandies)) {
                    _ = store.useExpCandy(on: individual.id)
                }
            }
            if shinyCandies > 0 {
                CandyButton(title: l.useShinyCandy(shinyCandies)) {
                    _ = store.useShinyCandy(on: individual.id)
                }
            }
        } else {
            Text(l.detailNoCandy).font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}

/// 폼 변경 버튼. 사탕과 같은 이유로 별도 타입 — 아이템은 파는데 쓸 화면이 없는 결함이 이 앱에서
/// 한 번 나갔다. 배선을 테스트로 잠근다.
struct FormButton: View {
    let title: String
    let action: () -> Void

    #if DEBUG
    @MainActor static var constructed: [(title: String, action: () -> Void)] = []
    @MainActor static var isRecording = false
    @MainActor static func resetConstructed() {
        isRecording = true
        constructed = []
    }
    #endif

    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
        #if DEBUG
        if Self.isRecording { Self.constructed.append((title, action)) }
        #endif
    }

    var body: some View {
        DetailActionButton(title: title, prominent: true, action: action)
    }
}

/// 상세 화면의 액션 버튼 — 폭을 꽉 채워 누를 곳이 분명하게. 진화 버튼과 알 발견 버튼이
/// 둘 다 이 타입을 거치므로, "이 조건에서 어떤 버튼이 뜨는가"를 잠그려면 여기서 수집해야
/// 한다 — `BoxCell`·`CandyButton` 이 쓰는 것과 같은 `#if DEBUG` 레코더 패턴.
struct DetailActionButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

    #if DEBUG
    @MainActor static var constructed: [(title: String, action: () -> Void)] = []
    @MainActor static var isRecording = false
    @MainActor static func resetConstructed() {
        isRecording = true
        constructed = []
    }
    #endif

    init(title: String, prominent: Bool, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.action = action
        #if DEBUG
        if Self.isRecording { Self.constructed.append((title, action)) }
        #endif
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: prominent ? .semibold : .regular))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(prominent ? Color.accentColor : Color.secondary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

/// 사탕 버튼. 별도 타입으로 뽑은 이유는 **배선 자체를 테스트로 잠그기 위해서**다 —
/// 사탕이 상점에서 팔리는데 쓸 화면이 없던 결함을, 스토어 메서드를 직접 부르는 테스트는 못 잡았다.
struct CandyButton: View {
    let title: String
    let action: () -> Void

    #if DEBUG
    /// 테스트 전용 — 이번 렌더에서 만들어진 사탕 버튼(제목 + 눌렀을 때의 동작).
    /// 동작까지 담아 두어야 "버튼이 그려졌나"를 넘어 "눌렀을 때 실제로 사탕이 쓰이나"까지 잠근다.
    @MainActor static var constructed: [(title: String, action: () -> Void)] = []
    /// 수집은 테스트가 켤 때만 한다 — DEBUG 로 앱을 돌리면 화면을 그릴 때마다 클로저가 쌓여
    /// 영영 안 빠진다(`SpriteView.constructionCount` 는 Int 라 커질 수가 없었다).
    @MainActor static var isRecording = false
    @MainActor static func resetConstructed() {
        isRecording = true
        constructed = []
    }
    #endif

    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
        #if DEBUG
        if Self.isRecording { Self.constructed.append((title, action)) }
        #endif
    }

    var body: some View {
        DetailActionButton(title: title, prominent: false, action: action)
    }
}
