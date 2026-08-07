import SwiftUI

/// 다음 사탕까지 — **경험치 바와 헷갈리지 않게** 일부러 다른 물건처럼 생겼다.
///
/// 둘은 성격이 다르다: 경험치는 *이 개체가 자라는* 정도라 화면의 주인공이고, 사탕은 리본이
/// 곁들여 만들어 내는 산출이다. 그런데 처음엔 둘 다 같은 `ProgressView` 에 홈에서는 색까지
/// 같아서(주황 5px) 어느 쪽이 무엇인지 읽히지 않았다.
///
/// 그래서 셋을 한꺼번에 갈라 둔다:
/// - **색**: 경험치는 강조색, 사탕은 주황(사탕 아이콘·발견 카드와 같은 계열).
/// - **높이**: 5pt 대 3pt.
/// - **폭**: 경험치는 한 줄을 다 쓰고, 사탕은 글자 사이에 낀다.
struct CandyMeter: View {
    /// 0~1.
    let progress: Double
    /// 남은 토큰 표기.
    let remaining: String
    let label: String

    /// 경험치 바(5pt)보다 확실히 얇아야 한다 — 1pt 차이는 눈에 안 띈다.
    static let height: CGFloat = 3

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 8)).foregroundStyle(.orange)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.20))
                    Capsule().fill(Color.orange)
                        .frame(width: geo.size.width * min(1, max(0, progress)))
                }
            }
            .frame(height: Self.height)
            Text(remaining)
                .font(.system(size: 9)).monospacedDigit().foregroundStyle(.tertiary)
        }
        // 글자 사이에 낀 얇은 선이라 세로 여백을 조금 줘야 위아래 줄과 안 붙는다.
        .padding(.vertical, 1)
    }
}
