import XCTest
@testable import PokeTokenBar

/// 회귀 가드: `allowKeychainPrompt: false` 는 "프롬프트를 안 띄운다"가 아니라
/// **"Keychain 을 아예 조회하지 않는다"** 는 계약이다. no-UI 쿼리(`kSecUseAuthenticationUIFail`
/// /`LAContext`)로도 잠긴·미승인 login 키체인의 '암호 입력' 다이얼로그는 억제되지 않는다 —
/// 실측: 캐시 만료 폴 도중 `SecItemCopyMatching` 이 13초간 블록하며 팝업을 띄웠다.
///
/// 왜 store 쪽 가드로는 부족한가: `UsageStoreTests.testAutoRefreshUsesNoPromptPathManualUsesPromptPath`
/// 는 store 가 **넘기는 플래그 값**만 본다. 자동 경로에 `false` 를 올바르게 넘기면서 프로바이더
/// 안에서 키체인을 읽는 구현은 그 가드를 통과한다(#210 이 그렇게 들어왔다 — 스위트 초록,
/// 실측 조회 2회/폴). 이 테스트는 프로바이더 쪽 계약을 조회 횟수로 센다.
///
/// 프로바이더가 늘면 `automaticProbes` 에 한 줄 추가한다.
final class KeychainAutoPathTests: XCTestCase {

    func testAutomaticPathNeverQueriesTheKeychain() async {
        // 게이트가 켜져 있으면 조회 전에 throw 되어 이 테스트는 구조상 실패할 수 없다.
        // 강제로 내려서 "가드가 있어서 0" 과 "게이트가 막아서 0" 을 구분한다.
        let savedGate = KeychainAccessGate.isDisabled
        KeychainAccessGate.isDisabled = false
        defer { KeychainAccessGate.isDisabled = savedGate }

        for probe in Self.automaticProbes {
            KeychainReader.resetQueryCountForTesting()
            await probe.run()
            XCTAssertEqual(
                KeychainReader.queryCount, 0,
                """
                \(probe.name): 자동 폴링이 Keychain 을 \(KeychainReader.queryCount)회 조회했다. \
                자동 경로는 파일 크리덴셜·캐시로만 답하고, 없으면 stale 로 두어야 한다 — \
                키체인 조회는 사용자가 갱신을 누른 경로(allowKeychainPrompt: true)에서만.
                """)
        }
    }

    /// 사용자 동작 경로는 반대로 키체인을 **읽어야** 한다. 이게 없으면 위 단언은
    /// "아무도 키체인을 안 읽는다" 로도 만족되어 무엇도 지키지 않는다.
    func testManualPathDoesQueryTheKeychain() async {
        let savedGate = KeychainAccessGate.isDisabled
        KeychainAccessGate.isDisabled = false
        defer { KeychainAccessGate.isDisabled = savedGate }

        KeychainReader.resetQueryCountForTesting()
        _ = try? await AntigravityRateLimitsProvider().fetch(allowKeychainPrompt: true)
        XCTAssertGreaterThan(
            KeychainReader.queryCount, 0,
            "사용자 갱신 경로는 키체인을 읽어야 한다 — 0 이면 위 자동경로 단언이 공허해진다")
    }

    private struct Probe {
        let name: String
        let run: @Sendable () async -> Void
    }

    private static let automaticProbes: [Probe] = [
        Probe(name: "claude_code") {
            _ = try? await OAuthLimitsProvider().fetch(allowKeychainPrompt: false)
        },
        Probe(name: "antigravity") {
            _ = try? await AntigravityRateLimitsProvider().fetch(allowKeychainPrompt: false)
        },
    ]
}
