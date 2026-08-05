import SwiftUI

/// 첫 실행 화면 — 전 세대 스타터 27마리 중 하나를 고른다. 고르는 것이 이 앱의 시작이라
/// 선택 전에는 다른 탭으로 갈 수 없다.
struct StarterPickerView: View {
    let store: PlayerStore
    let provider: any PokeProviding
    let onChosen: () -> Void

    @State private var choosing: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("함께 시작할 포켓몬을 고르세요")
                .font(.system(size: 13, weight: .bold))
            Text("고른 포켓몬이 첫 파트너가 됩니다. 토큰을 쓸수록 경험치가 쌓여요.")
                .font(.system(size: 10)).foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(StarterCatalog.byGeneration, id: \.generation) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(entry.generation)세대")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            HStack(spacing: 8) {
                                ForEach(entry.speciesIDs, id: \.self) { id in
                                    starterCell(id)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 300)
        }
        .padding(13)
        .frame(width: PopoverMetrics.width)
    }

    private func starterCell(_ speciesID: Int) -> some View {
        Button {
            choose(speciesID)
        } label: {
            SpriteView(speciesID: speciesID, size: 64, animated: true)
                .frame(width: 76, height: 76)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(choosing != nil)
        .opacity(choosing == nil || choosing == speciesID ? 1 : 0.4)
    }

    /// 등급은 그 종의 포획률에서 온다. 조회에 실패하면 에픽으로 둔다 — 스타터는 대부분 포획률 45다.
    private func choose(_ speciesID: Int) {
        choosing = speciesID
        Task {
            let grade: Grade
            if let base = try? await provider.baseSpecies(id: speciesID) {
                grade = Grade(rarity: Rarity.from(captureRate: base.captureRate,
                                                  isLegendary: false, isMythical: false))
            } else {
                grade = .epic
            }
            store.chooseStarter(speciesID: speciesID, grade: grade)
            onChosen()
        }
    }
}
