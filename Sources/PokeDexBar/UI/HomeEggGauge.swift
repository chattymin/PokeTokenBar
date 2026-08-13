import SwiftUI

/// 홈 파트너 카드의 알 게이지 — 이름·레벨 배지와 같은 줄 오른쪽 끝에 선다.
///
/// **왜 알 모양인가.** 바로 아래 줄에 경험치 바가 있다. 둘 다 가로 막대면 어느 쪽이 무엇인지
/// 구분이 안 된다(사탕 미터가 주황을 가져가며 이미 한 번 겪은 문제다). 세로로 차오르는 알은
/// 형태부터 다르고, **부화 슬롯에 뜨는 그 알**(`EggIcon`)과 같은 그림이라 무엇을 채우고
/// 있는지가 설명 없이 읽힌다.
///
/// **같은 알을 두 장 겹친다.** 반투명 사각형을 위에 덮는 방법도 있지만 그러면 알 바깥의 투명
/// 영역까지 사각형이 비친다. 아래에 흐린 알을 깔고 위에 진한 알을 아래에서부터 잘라 얹으면
/// 실루엣이 저절로 지켜지고, 마스크나 CALayer 필터를 안 쓰므로 오프스크린 캡처에서도
/// 화면과 똑같이 나온다(`.brightness` 류가 스크린샷에서 사라지는 함정 — CLAUDE.md).
struct HomeEggGauge: View {
    let grade: Grade
    /// 0…1. 계산은 상세 화면과 같은 순수 함수(`IndividualDetailView.eggProgress`)를 쓴다 —
    /// 두 화면이 같은 알을 다른 퍼센트로 그리면 안 된다.
    let progress: Double
    /// 흔들 것인가. **꽉 찼다고 흔들지 않는다** — `shouldShake` 참고.
    let shaking: Bool
    let action: () -> Void

    var size: CGFloat = 22

    /// 아직 안 찬 부분의 진하기. 0 이면 빈 알이 안 보여 게이지가 아니라 "알이 없다"로 읽힌다.
    private static let dimOpacity: Double = 0.15

    #if DEBUG
    /// 눌렀을 때 실제로 알을 받는지까지 테스트가 잠글 수 있게 동작을 들고 있는다 —
    /// `FoundEggAnnouncementCard`·`ProfessorOfferButton` 과 같은 패턴.
    @MainActor static var constructed: [(progress: Double, shaking: Bool, action: () -> Void)] = []
    @MainActor static var isRecording = false
    @MainActor static func resetConstructed() {
        isRecording = true
        constructed = []
    }
    #endif

    init(grade: Grade, progress: Double, shaking: Bool, size: CGFloat = 22,
         action: @escaping () -> Void) {
        self.grade = grade
        self.progress = progress
        self.shaking = shaking
        self.size = size
        self.action = action
        #if DEBUG
        if Self.isRecording { Self.constructed.append((progress, shaking, action)) }
        #endif
    }

    /// 흔들 조건. **꽉 찬 것만으로는 안 흔든다** — 빈 부화 슬롯이 없으면 눌러도 아무 일이
    /// 안 나는데, 흔들어 부르는 건 거짓말이다. 그 상태의 이유는 아래 알림 카드가 말한다.
    /// 순수 함수라 테스트로 잠근다.
    nonisolated static func shouldShake(full: Bool, hasFreeSlot: Bool) -> Bool {
        full && hasFreeSlot
    }

    /// 아래에서부터 차오른 높이(pt). 0…1 밖의 값이 와도 알 안에 머문다.
    nonisolated static func filledHeight(progress: Double, size: CGFloat) -> CGFloat {
        guard progress.isFinite else { return 0 }
        return size * min(1, max(0, progress))
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                EggIcon(grade: grade, size: size).opacity(Self.dimOpacity)
                EggIcon(grade: grade, size: size)
                    .frame(height: Self.filledHeight(progress: progress, size: size),
                           alignment: .bottom)
                    .clipped()
            }
            .frame(width: size * 0.82, height: size, alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rotationEffect(.degrees(shaking ? 7 : 0), anchor: .bottom)
        .animation(shaking
                   ? .easeInOut(duration: 0.12).repeatForever(autoreverses: true)
                   : .default,
                   value: shaking)
        .help(progressHelp)
    }

    /// 마우스를 올리면 얼마나 왔는지 숫자로 — 작은 그림이라 눈대중이 안 되는 구간이 있다.
    private var progressHelp: String {
        "\(Int(min(1, max(0, progress)) * 100))%"
    }
}
