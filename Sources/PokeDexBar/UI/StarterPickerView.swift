import SwiftUI

/// 첫 실행 화면 — 전 세대 스타터 27마리 중 하나를 고른다. 고르는 것이 이 앱의 시작이라
/// 선택 전에는 다른 탭으로 갈 수 없다.
struct StarterPickerView: View {
    let store: PlayerStore
    let provider: any PokeProviding
    let onChosen: () -> Void

    @State private var choosing: Int?
    @State private var message: String?
    /// 선택 작업을 뷰 생애에 묶는다 — 안 그러면 팝오버가 닫혔다 다시 열려 새 뷰가 생겨도
    /// 이전 네트워크 조회가 백그라운드에서 계속 돌아 뒤늦게 착지할 수 있다.
    @State private var chooseTask: Task<Void, Never>?

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l.starterPickerTitle)
                .font(.system(size: 13, weight: .bold))
            Text(l.starterPickerSubtitle)
                .font(.system(size: 10)).foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(StarterCatalog.byGeneration, id: \.generation) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(l.generationLabel(entry.generation))
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
        .onDisappear {
            // 팝오버가 닫혀 뷰가 사라지면 진행 중인 선택 조회도 함께 끊는다 — 살려두면
            // 다음에 연 새 뷰의 선택과 경합해 조용히 지는 쪽이 생긴다.
            chooseTask?.cancel()
        }
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
        message = nil
        chooseTask = Task {
            let grade: Grade
            if let base = try? await provider.baseSpecies(id: speciesID) {
                grade = Grade(rarity: Rarity.from(captureRate: base.captureRate,
                                                  isLegendary: false, isMythical: false))
            } else {
                grade = .epic
            }
            // 그 사이 뷰가 사라져 취소됐으면(팝오버 닫힘 등) 착지하지 않는다 — 늦게 도착한
            // 조회가 다음 선택과 경합해 조용히 이기는 걸 막는다.
            guard !Task.isCancelled else { return }
            if store.chooseStarter(speciesID: speciesID, grade: grade) != nil {
                onChosen()
            } else {
                // 이미 스타터를 골랐거나(경합) 카탈로그 밖 — 다시 시도할 수 있게 되돌린다.
                choosing = nil
                message = l.starterPickFailed
            }
        }
    }
}
