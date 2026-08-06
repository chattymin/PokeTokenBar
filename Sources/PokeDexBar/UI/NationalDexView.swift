import SwiftUI

/// 도감 — 1번부터 마지막 종까지 번호순 그리드. 희귀도로 나누지 않는다.
/// 읽기 전용이다(개체를 만지는 일은 박스에서 한다).
///
/// 1025칸을 한 번에 그리면 팝오버가 버벅이므로 `LazyVGrid` 로 보이는 칸만 만든다 —
/// 스프라이트 요청도 화면에 들어온 칸에서만 나간다.
struct NationalDexView: View {
    let store: PlayerStore
    /// 스프라이트를 칸에 꽉 채울지(설정).
    var fillFrame = true

    nonisolated static let speciesRange = 1...1025

    nonisolated static func progressText(caught: Int) -> String {
        "\(caught) / \(speciesRange.count)"
    }

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 6), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(store.l.collection).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(Self.progressText(caught: store.state.dex.count))
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Self.speciesRange, id: \.self) { id in
                        cell(id)
                    }
                }
            }
            .frame(height: 300)
        }
    }

    private func cell(_ speciesID: Int) -> some View {
        let caught = store.state.dex.contains(speciesID)
        return VStack(spacing: 1) {
            // 못 잡은 종은 실루엣 — 모습은 보이되 정체는 가린다.
            SpriteView(speciesID: speciesID, size: 32, silhouette: !caught, fillFrame: fillFrame)
                .frame(width: 32, height: 32)
                .opacity(caught ? 1 : 0.55)
            Text("\(speciesID)")
                .font(.system(size: 7)).monospacedDigit()
                .foregroundStyle(caught ? .secondary : .tertiary)
        }
        .frame(width: 44, height: 46)
        .background(Color.secondary.opacity(caught ? 0.10 : 0.04),
                    in: RoundedRectangle(cornerRadius: 6))
    }
}
