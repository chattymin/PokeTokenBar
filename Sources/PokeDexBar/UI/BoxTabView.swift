import SwiftUI

/// 박스 — 보유 개체 목록. 도감이 "종을 모았나"라면 여기는 "무엇을 가졌나"다.
/// 파트너 지정과 진화가 여기서 일어난다(중복 개체를 각각 다루려면 개체 단위 화면이 필요하다).
struct BoxTabView: View {
    let store: PlayerStore
    /// 종 번호 → 진화 라인. 없으면 진화 후보를 알 수 없어 진화 버튼 자체를 숨긴다.
    let lines: [Int: EvoLine]
    /// 라인이 없을 때 호출 — 앱이 받아와 `lines` 를 채운다.
    let onNeedLine: (Int) -> Void

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
                    Text(individual.grade.label)
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.18), in: Capsule())
                    if isPartner {
                        Text("파트너")
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                    Spacer()
                    Text(individual.nature.name(.systemDefault))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }

                ProgressView(value: Self.progress(individual))
                    .progressViewStyle(.linear)
                    .frame(height: 4)

                HStack(spacing: 8) {
                    if !isPartner {
                        Button("파트너로") { store.setPartner(individual.id) }
                            .buttonStyle(.borderless).font(.system(size: 10))
                    }
                    if ready {
                        ForEach(choices, id: \.self) { target in
                            Button(choices.count > 1 ? "#\(target) 로 진화" : "진화") {
                                if let line { store.evolve(individualID: individual.id,
                                                           to: target, line: line) }
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .task(id: individual.baseID) {
            if lines[individual.baseID] == nil { onNeedLine(individual.baseID) }
        }
    }
}
