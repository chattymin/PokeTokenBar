import XCTest
@testable import PokeTokenBar

/// 한국어 조사 선택 — 이름의 마지막 음절 받침으로 고르고, 판정할 수 없으면 병기 형태를 유지한다.
final class KoreanParticleTests: XCTestCase {

    func testSubjectFollowsFinalConsonant() {
        XCTAssertEqual(KoreanParticle.subject.attach(to: "유니란"), "유니란이")
        XCTAssertEqual(KoreanParticle.subject.attach(to: "피카츄"), "피카츄가")
    }

    func testObjectFollowsFinalConsonant() {
        XCTAssertEqual(KoreanParticle.object.attach(to: "꼬부기"), "꼬부기를")
        XCTAssertEqual(KoreanParticle.object.attach(to: "리자몽"), "리자몽을")
    }

    /// "으로/로"는 받침 없음과 ㄹ 받침이 같은 쪽이다 — 이 분기가 빠지면 "알으로"가 된다.
    func testDirectionTreatsRieulLikeNoFinalConsonant() {
        XCTAssertEqual(KoreanParticle.direction.attach(to: "란쿨루스"), "란쿨루스로")
        XCTAssertEqual(KoreanParticle.direction.attach(to: "듀란"), "듀란으로")
        XCTAssertEqual(KoreanParticle.direction.attach(to: "희귀 알"), "희귀 알로")
        XCTAssertEqual(KoreanParticle.direction.attach(to: "레트라"), "레트라로")
    }

    /// 받침을 알 수 없는 끝(안농 글자, 이름 로딩 전 번호, 라틴 문자, 빈 문자열)은 병기 형태 그대로.
    func testNonHangulEndingKeepsBothForms() {
        XCTAssertEqual(KoreanParticle.subject.attach(to: "안농 [A]"), "안농 [A]이(가)")
        XCTAssertEqual(KoreanParticle.object.attach(to: "#123"), "#123을(를)")
        XCTAssertEqual(KoreanParticle.direction.attach(to: "Pikachu"), "Pikachu(으)로")
        XCTAssertEqual(KoreanParticle.subject.attach(to: ""), "이(가)")
    }

    /// 실제 문구 — 스크린샷으로 보고된 "유니란이(가)"·"듀란(으)로"·"란쿨루스(으)로"가 사라진다.
    func testKoreanCopyUsesTheMatchingParticle() {
        let l = L(.ko)
        XCTAssertEqual(l.notifHatchBody("유니란"), "알에서 유니란이 나왔어요!")
        XCTAssertEqual(l.notifShinyHatchBody("뚜벅쵸", odds: 48), "이로치 뚜벅쵸가 태어났어요! (1/48)")
        XCTAssertEqual(l.notifEvolveBody("듀란"), "듀란으로 진화했어요!")
        XCTAssertEqual(l.statusEvolved("란쿨루스"), "란쿨루스로 진화했어요!")
        XCTAssertEqual(l.eggConfirm("레트라", l.eggName(.rare)), "레트라를 놓아주고 희귀 알로 바꿀까요?")
    }

    /// 조사 선택은 한국어 문구에만 적용된다.
    func testOtherLanguagesAreUntouched() {
        XCTAssertEqual(L(.en).notifHatchBody("Unfezant"), "Unfezant hatched from the egg!")
        XCTAssertEqual(L(.ja).notifEvolveBody("デスカーン"), "デスカーン に進化しました！")
    }
}
