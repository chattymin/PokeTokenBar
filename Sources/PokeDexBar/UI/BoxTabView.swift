import SwiftUI

/// 박스 — 보유 개체 목록. 도감이 "종을 모았나"라면 여기는 "무엇을 가졌나"다.
/// 파트너 지정·사탕 사용·진화가 여기서 일어난다(중복 개체를 각각 다루려면 개체 단위 화면이 필요하다).
struct BoxTabView: View {
    let store: PlayerStore
    /// 종 번호 → 진화 라인. 없으면 진화 후보를 알 수 없어 진화 버튼 자체를 숨긴다.
    let lines: [Int: EvoLine]
    /// 라인이 없을 때 호출 — 앱이 받아와 `lines` 를 채운다.
    let onNeedLine: (Int) -> Void

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

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(sorted) { individual in
                    row(individual)
                }
            }
        }
        .frame(height: 320)
    }

    private func row(_ individual: Individual) -> some View {
        let isPartner = individual.id == store.state.partnerID
        let line = lines[individual.baseID]
        let choices = line.map { store.evolutionChoices(individual, line: $0) } ?? []
        let ready = store.canEvolve(individual) && !choices.isEmpty
        return HStack(alignment: .top, spacing: 8) {
            SpriteView(speciesID: individual.speciesID, size: 40, shiny: individual.shiny)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("#\(individual.speciesID)")
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    if individual.shiny { Text("✨").font(.system(size: 10)) }
                    Text(individual.grade.label(store.language))
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.18), in: Capsule())
                    if isPartner {
                        Text(l.partnerBadge)
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                    Spacer()
                    Text(individual.nature.name(store.language))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }

                ProgressView(value: Self.progress(individual))
                    .progressViewStyle(.linear)
                    .frame(height: 4)

                HStack(spacing: 8) {
                    if !isPartner {
                        Button(l.makePartner) { store.setPartner(individual.id) }
                            .buttonStyle(.borderless).font(.system(size: 10))
                    }
                    if ready, let line {
                        ForEach(choices, id: \.self) { target in
                            // 번호(#134)가 아니라 이름으로 — line.names 에 없으면 #번호로 폴백.
                            let name = line.localizedName(target, store.language)
                            Button(choices.count > 1 ? l.evolveTo(name) : l.evolve) {
                                store.evolve(individualID: individual.id, to: target, line: line)
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                    Spacer()
                }

                candyRow(individual)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .task(id: individual.baseID) {
            if lines[individual.baseID] == nil { onNeedLine(individual.baseID) }
        }
    }

    /// 사탕 사용 줄 — 가진 사탕이 있을 때만 나온다. 상점에서 산 사탕을 쓰는 유일한 화면이다
    /// (파트너 아닌 개체는 경험치를 못 받으므로 경험치 사탕이 유일한 성장 수단이기도 하다).
    /// 버튼을 파트너·진화 줄 아래에 따로 두는 이유는 폭 — 네 버튼을 한 줄에 몰면 팝오버 콘텐츠
    /// 폭(332pt)에서 라벨이 잘린다.
    @ViewBuilder
    private func candyRow(_ individual: Individual) -> some View {
        let expCandies = store.count(of: .expCandy)
        // 이미 이로치면 반짝이는 사탕은 할 일이 없다 — `useShinyCandy` 도 그 경우 false 를 돌려준다.
        let shinyCandies = individual.shiny ? 0 : store.count(of: .shinyCandy)
        if expCandies > 0 || shinyCandies > 0 {
            HStack(spacing: 8) {
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
                Spacer()
            }
        }
    }
}

/// 박스 행의 사탕 버튼. 별도 타입으로 뽑은 이유는 **배선 자체를 테스트로 잠그기 위해서**다 —
/// 사탕이 상점에서 팔리는데 쓸 화면이 없던 결함을, 스토어 메서드를 직접 부르는 테스트는 못 잡았다.
/// DEBUG 계측은 `SpriteView.constructionCount` 와 같은 패턴(릴리스 바이너리엔 담기지 않는다).
struct CandyButton: View {
    let title: String
    let action: () -> Void

    #if DEBUG
    /// 테스트 전용 — 이번 렌더에서 만들어진 사탕 버튼(제목 + 눌렀을 때의 동작).
    /// 동작까지 담아 두어야 "버튼이 그려졌나"를 넘어 "눌렀을 때 실제로 사탕이 쓰이나"까지 잠근다.
    @MainActor static var constructed: [(title: String, action: () -> Void)] = []
    /// 수집은 테스트가 켤 때만 한다 — DEBUG 로 앱을 돌리면 박스를 그릴 때마다 클로저가 쌓여
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
        Button(title, action: action)
            .buttonStyle(.borderless)
            .font(.system(size: 10))
    }
}
