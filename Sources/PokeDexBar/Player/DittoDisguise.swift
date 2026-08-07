import Foundation

/// 메타몽 위장 — 커먼 알에서 아주 드물게 나오고, 뮤의 모습을 하고 나온다.
///
/// **왜 뮤인가.** 메타몽과 뮤는 색이 같이 움직인다 — 둘 다 분홍이고, 이로치가 되면 둘 다 하늘색이
/// 된다(실제 스프라이트에서 확인). 메타몽이 실패한 뮤 복제체라는 이야기가 오래 돌아온 근거가 그것이고,
/// 그래서 이 위장은 화면이 스스로 설명한다.
///
/// **왜 눈은 안 바뀌나.** 메타몽의 변신은 눈까지 따라가지 못한다는 것이 원작의 설정이다. 그래서
/// 위장 스프라이트는 뮤의 몸에 메타몽의 눈과 입을 얹는다(`DittoDisguiseSprite`). 자세히 본 사람만
/// 알아채고, 알아챈 사람은 확신한다 — 이스터에그가 가져야 할 성질이다.
///
/// **왜 굳이 파트너로 두어야 풀리나.** 정체가 저절로 드러나면 사용자가 그 순간에 없을 수 있다.
/// 파트너로 지정하는 건 사용자가 하는 일이고, 그 뒤 10분은 앱을 열어 둘 만한 시간이다. 곁에 두고
/// 지켜본 사람에게만 드러난다는 점에서 위장을 푸는 조건으로도 말이 된다.
enum DittoDisguise {
    /// 정체.
    static let speciesID = 132
    /// 위장한 모습.
    static let disguisedAs = 151

    /// 위장 확률의 분모 — 커먼 알에 한해 1/128. 이로치(1/64)보다 두 배 귀하다.
    ///
    /// 커먼으로 한정한 건 원안 그대로다. 커먼은 알에서 가장 자주 나오는 등급이라 오래 하다 보면
    /// 언젠가는 만나게 되고, 동시에 **커먼 알에서 뮤가 나왔다**는 것 자체가 두 번째 단서가 된다 —
    /// 뮤는 레전더리라 커먼 알에서 나올 수 없다.
    static let denominator = 128

    /// 파트너로 이만큼 지내면 위장이 풀린다.
    static let revealSeconds = 600

    /// 위장 스프라이트의 슬러그. 실제 Showdown 경로가 아니라 이 앱이 만들어 내는 그림의 이름이라,
    /// 진짜 폼 슬러그(`charizard-megax`)와 안 겹치게 접두를 붙인다.
    static let formSlug = "ptb-ditto-disguise"

    /// 이 알이 메타몽인가. 미리 뽑은 roll(0~1)로 판정하는 순수 함수 — 부수효과 없이 테스트한다.
    static func hits(grade: Grade, roll: Double) -> Bool {
        grade == .common && roll < 1.0 / Double(denominator)
    }

    /// 위장을 풀 때가 됐나. 파트너로 지낸 **누적** 시간을 본다 — 파트너를 바꿨다 되돌려도
    /// 지금까지 함께한 시간은 사라지지 않아야 한다(`Individual.partnerDuration`).
    static func isReady(partnerSeconds: Int) -> Bool {
        partnerSeconds >= revealSeconds
    }
}
