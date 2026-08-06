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
    private var threshold: Int {
        ExpBalance.threshold(grade: individual.grade, stageIndex: individual.stageIndex)
    }
    private var choices: [Int] {
        line.map { store.evolutionChoices(individual, line: $0) } ?? []
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
        .task(id: individual.baseID) {
            if line == nil { onNeedLine(individual.baseID) }
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
            SpriteView(speciesID: individual.speciesID, form: individual.spriteForm, size: 72,
                       animated: true, shiny: individual.shiny, antialias: true)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(displayName).font(.system(size: 13, weight: .semibold))
                    if individual.shiny { Text("✨").font(.system(size: 11)) }
                }
                HStack(spacing: 4) {
                    Text("#\(individual.speciesID)")
                        .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    if let region = individual.region {
                        Text(region.label(store.language))
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
                    Text(l.ribbonCandyRate(TokenFormatter.compact(ribbon.tokensPerCandy)))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
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

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(l.detailExp).font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Text("\(TokenFormatter.compact(individual.exp)) / \(TokenFormatter.compact(threshold))")
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: BoxTabView.progress(individual))
                .progressViewStyle(.linear).frame(height: 5)
            if !isPartner {
                Text(l.detailPartnerOnlyExp)
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
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
                ForEach(choices, id: \.self) { target in
                    let name = line.localizedName(target, store.language)
                    let need = store.requirement(for: target, line: line)
                    let met = store.meetsRequirement(need, for: individual)
                    VStack(alignment: .leading, spacing: 2) {
                        DetailActionButton(title: choices.count > 1 ? l.evolveTo(name) : l.evolve,
                                           prominent: met) {
                            store.evolve(individualID: individual.id, to: target, line: line)
                        }
                        .disabled(!met)
                        .opacity(met ? 1 : 0.55)
                        // 못 누르는 버튼은 이유를 말해야 한다 — 아니면 고장으로 읽힌다.
                        if !met, let hint = requirementHint(need) {
                            Text(hint).font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                    }
                }
            } else if line != nil, choices.isEmpty {
                Text(l.detailMaxStage).font(.system(size: 9)).foregroundStyle(.tertiary)
            }

            formSection
            candySection
        }
    }

    /// 폼 — 그 폼이 있는 종에만 나온다. 못 바꾸는 폼도 목록에 남기고 **이유를 적는다**:
    /// 목록에서 빼면 큐레무 블랙이 이 게임에 있다는 사실 자체를 알 수가 없다.
    @ViewBuilder
    private var formSection: some View {
        ForEach(FormKind.allCases, id: \.self) { kind in
            let choices = store.formChoices(individual, kind: kind)
            ForEach(choices, id: \.slug) { form in
                let can = store.canChange(individual, to: form)
                let name = form.displayName(base: baseName, store.language)
                VStack(alignment: .leading, spacing: 2) {
                    if can {
                        FormButton(title: l.changeToForm(name, remaining: formStock(form))) {
                            store.changeForm(individualID: individual.id, to: form)
                        }
                    } else {
                        DetailActionButton(title: name, prominent: false) {}
                            .disabled(true).opacity(0.55)
                        Text(formBlockReason(form)).font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        if individual.form != nil {
            DetailActionButton(title: l.revertForm, prominent: false) {
                store.revertForm(individualID: individual.id)
            }
        }
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

    /// 아직 못 갖춘 조건을 사람 말로. 조건이 없으면 nil.
    private func requirementHint(_ need: EvoRequirement) -> String? {
        switch need {
        case .none: nil
        case .item(let item): l.evolveNeedsItem(item)
        case .friendship:
            l.evolveNeedsTime(Individual.togetherText(
                seconds: max(0, EvoRequirement.friendshipSeconds
                             - individual.partnerDuration(at: store.currentDate())), l))
        }
    }

    /// 폼 접두를 붙이기 전의 종 이름.
    private var baseName: String {
        line?.localizedName(individual.speciesID, store.language) ?? "#\(individual.speciesID)"
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

/// 상세 화면의 액션 버튼 — 폭을 꽉 채워 누를 곳이 분명하게.
struct DetailActionButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

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
