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

    func testTopicAndComitativeFollowFinalConsonant() {
        XCTAssertEqual(KoreanParticle.topic.attach(to: "리자몽"), "리자몽은")
        XCTAssertEqual(KoreanParticle.topic.attach(to: "피카츄"), "피카츄는")
        XCTAssertEqual(KoreanParticle.comitative.attach(to: "리자몽"), "리자몽과")
        XCTAssertEqual(KoreanParticle.comitative.attach(to: "피카츄"), "피카츄와")
        XCTAssertEqual(KoreanParticle.topic.attach(to: "Pikachu"), "Pikachu은(는)")
    }

    /// 숫자는 읽는 소리로 — 멸망 카운트 "3으로/2로", 버전 "v2.5.4를". "#번호"는 이름 자리표시라 병기.
    func testNumbersFollowHowTheyAreRead() {
        XCTAssertEqual(KoreanParticle.direction.attach(to: "3"), "3으로")
        XCTAssertEqual(KoreanParticle.direction.attach(to: "2"), "2로")
        XCTAssertEqual(KoreanParticle.direction.attach(to: "1"), "1로", "일 — ㄹ 받침은 '로'")
        XCTAssertEqual(KoreanParticle.direction.attach(to: "0"), "0으로")
        XCTAssertEqual(KoreanParticle.object.attach(to: "10"), "10을", "십")
        XCTAssertEqual(KoreanParticle.object.attach(to: "100"), "100을", "백")
        XCTAssertEqual(KoreanParticle.object.attach(to: "2000"), "2000을", "천")
        XCTAssertEqual(KoreanParticle.object.attach(to: "v2.5.4"), "v2.5.4를", "사")
        XCTAssertEqual(KoreanParticle.object.attach(to: "v2.6.0"), "v2.6.0을", "영")
        XCTAssertEqual(KoreanParticle.object.attach(to: "#25"), "#25을(를)")
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

    /// 배틀 문구 — 받침 있는 이름(리자몽)과 없는 이름(피카츄) 모두. "\(subject)는"처럼 조사를 고정했던
    /// 자리가 "리자몽는"이 되던 문제도 함께 막는다.
    func testBattleCopyUsesTheMatchingParticle() {
        let l = L(.ko)
        XCTAssertEqual(l.battleFainted("리자몽"), "리자몽은 쓰러졌다!")
        XCTAssertEqual(l.battleFainted("피카츄"), "피카츄는 쓰러졌다!")
        XCTAssertEqual(l.battleWhatWillDo("리자몽"), "리자몽은 무엇을 할까?")
        XCTAssertEqual(l.battleOpponentSentOut("리자몽"), "상대는 리자몽을 내보냈다!")
        XCTAssertEqual(l.battleOpponentSentOut("피카츄"), "상대는 피카츄를 내보냈다!")
        XCTAssertEqual(l.battleChallengedBy("피카츄"), "피카츄가 배틀을 신청했다!")
        XCTAssertEqual(l.battleAgainst("리자몽"), "리자몽과의 배틀")
        XCTAssertEqual(l.battleAgainst("Trainer 4821"), "Trainer 4821과의 배틀", "숫자로 끝나면 읽는 소리(일 — ㄹ도 받침이라 과)")
        XCTAssertEqual(l.battleAgainst("Ash"), "Ash와(과)의 배틀", "라틴 문자는 병기")
        XCTAssertEqual(l.battleStatChanged("리자몽", "공격", 1), "리자몽의 공격이 올라갔다!")
        XCTAssertEqual(l.battleStatChanged("피카츄", "스피드", -2), "피카츄의 스피드가 크게 떨어졌다!")
        XCTAssertEqual(l.battleStatusApplied(l.battleOpposing("피카츄"), .paralysis), "상대 피카츄는 마비되었다!")
        XCTAssertEqual(l.battlePerishCount("피카츄", 3), "피카츄의 멸망 카운트가 3으로 되었다!")
        XCTAssertEqual(l.battlePerishCount("피카츄", 2), "피카츄의 멸망 카운트가 2로 되었다!")
        XCTAssertEqual(l.battleTransformed("메타몽", into: "리자몽"), "메타몽은 리자몽으로 변신했다!")
    }

    /// 버전 번호도 읽는 소리로 — 예전 문구는 "v2.5.4을"이었다(사 → 를).
    func testSkippedVersionCopyReadsTheNumber() {
        XCTAssertEqual(L(.ko).skippedVersion("2.5.4"), "v2.5.4를 건너뛰었어요")
        XCTAssertEqual(L(.ko).skippedVersion("2.6.0"), "v2.6.0을 건너뛰었어요")
    }

    /// 조사 선택은 한국어 문구에만 적용된다.
    func testOtherLanguagesAreUntouched() {
        XCTAssertEqual(L(.en).notifHatchBody("Unfezant"), "Unfezant hatched from the egg!")
        XCTAssertEqual(L(.ja).notifEvolveBody("デスカーン"), "デスカーン に進化しました！")
    }
}
