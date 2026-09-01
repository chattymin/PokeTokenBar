import SwiftUI

/// 박스 칸이 등급을 말하는 색.
///
/// **알 뽑기 연출과 같은 색 사다리를 쓴다**(`RevealStage`) — 흰색·하늘색·보라색·주황색.
/// 사용자는 알을 뽑을 때마다, 그리고 부화 슬롯의 껍질에서 이미 그 색을 배운다. 박스에서
/// 새 색을 만들면 배울 것이 하나 더 느는데, 얻는 것이 없다.
enum BoxCellGrade {
    /// 레벨 라벨 뒤에 깔 색. **원색을 그대로 쓰지 않는다** — 칸이 48pt 라 라벨이 원색이면
    /// 스프라이트보다 그 알약이 먼저 보인다. 요구가 "은은한 표시" 였다.
    static let opacity = 0.30

    static func tint(_ grade: Grade) -> Color {
        (EggReveal.stages(for: grade).last ?? .white).color.opacity(opacity)
    }
}
