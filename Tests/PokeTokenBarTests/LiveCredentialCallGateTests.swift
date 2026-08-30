import XCTest
@testable import PokeTokenBar

/// 스위트가 **사용자 실계정 자격증명으로 라이브 endpoint 를 치지 않는다**는 계약.
///
/// `UsageStore.init` 의 한도 프로바이더 기본값이 실물이라, 스텁을 주입하지 않은 테스트 구성은
/// 그대로 진짜 프로바이더를 쓴다(예: `AntigravityRateLimitsProviderTests` 는 antigravity 만 주입하고
/// claude 는 기본값). 무프롬프트 경로가 키체인을 안 읽어 오래 무해해 보였지만, 그건 자격증명이
/// *파일*로 없을 때 얘기다 — `~/.claude/.credentials.json` 이 있는 기기(리눅스 Claude Code, 그리고
/// 키체인을 파일로 미러링한 맥)에선 무프롬프트 경로가 성공해 usage·profile 을 실제로 호출한다.
/// 스위트가 초록인 채 계정 토큰으로 네트워크를 치는 false confidence 가 정확히 이 부류다.
///
/// 게이트는 토큰 취득이 아니라 **네트워크 경계**에 있다 — 취득 앞에 두면 `KeychainAutoPathTests` 의
/// 사용자 경로 단언이 0 이 되어 짝인 자동경로 단언이 공허해진다(#210). 그래서 여기서도 키체인
/// 조회 횟수는 단언하지 않는다. 그건 `KeychainAutoPathTests` 의 계약이다.
final class LiveCredentialCallGateTests: XCTestCase {
    /// 자동 경로(`allowKeychainPrompt: false`)로 호출한다 — 결함의 실제 트리거이고,
    /// 프롬프트 경로와 달리 테스트 실행 중 키체인 다이얼로그를 띄울 위험이 없다.
    func testClaudeLimitsFetchDoesNotReachTheNetwork() async throws {
        do {
            _ = try await OAuthLimitsProvider().fetch(allowKeychainPrompt: false)
            XCTFail("swift test 프로세스에서 라이브 한도 조회가 수행됐다")
        } catch LimitsError.liveFetchNotPermitted {
            // 기대 경로 — 자격증명을 구할 수 있는 기기에서 게이트까지 도달했다.
        } catch {
            // 자격증명이 없으면 취득 단계에서 먼저 끝나 게이트에 닿지 않는다. 그 기기에선 이 테스트가
            // 검증할 것이 없으므로 통과가 아니라 skip 이다 — 통과로 세면 커버리지가 거짓말을 한다.
            throw XCTSkip("자격증명을 구할 수 없어 네트워크 경계에 도달하지 않음: \(error)")
        }
    }

    func testAntigravityLimitsFetchDoesNotReachTheNetwork() async throws {
        do {
            _ = try await AntigravityRateLimitsProvider().fetch(allowKeychainPrompt: false)
            XCTFail("swift test 프로세스에서 라이브 antigravity 한도 조회가 수행됐다")
        } catch LimitsError.liveFetchNotPermitted {
            // 기대 경로
        } catch {
            throw XCTSkip("자격증명을 구할 수 없어 네트워크 경계에 도달하지 않음: \(error)")
        }
    }

    /// 부류 봉쇄 — 새 한도 프로바이더가 게이트 없이 추가되는 것을 소스 스캔으로 막는다.
    /// 개별 프로바이더 테스트만 두면 *다음* 프로바이더는 또 빠진다(OpenCodeGo 만 게이트가 있고
    /// claude·antigravity 가 빠져 있던 것이 이 결함의 실제 모양이다). 위 두 테스트가 기기에 따라
    /// skip 되므로, 기기와 무관하게 도는 이 스캔이 실질적 안전망이다.
    func testEveryNetworkingLimitsProviderIsGated() throws {
        let core = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // PokeTokenBarTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo root
            .appendingPathComponent("Sources/PokeTokenBar/Core")
        let names = try FileManager.default.contentsOfDirectory(atPath: core.path)
        var scanned: [String] = []
        var offenders: [String] = []

        for name in names where name.hasSuffix("LimitsProvider.swift") {
            let source = try String(contentsOf: core.appendingPathComponent(name), encoding: .utf8)
            // 네트워크를 치지 않는 프로바이더(로컬 파일만 읽는 Codex 등)는 이 계약의 대상이 아니다.
            guard source.contains("URLSession") else { continue }
            scanned.append(name)
            // 주석 줄은 세지 않는다 — 게이트를 주석 처리해도 통과하면 이 스캔은 아무것도 지키지 않는다
            // (실제로 결함 주입 검증에서 주석 처리된 guard 를 통과시켰다).
            let hasLiveGate = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .contains { !$0.hasPrefix("//") && $0.contains("AppEnv.isBundledApp") }
            if !hasLiveGate {
                offenders.append(name)
            }
        }

        XCTAssertFalse(scanned.isEmpty, "스캔 대상이 0건 — 파일명 규약이 바뀌었는지 확인할 것")
        XCTAssertTrue(offenders.isEmpty, """
            한도 프로바이더가 실사용자 자격증명으로 네트워크를 칠 수 있는데 실행환경 게이트가 없다.
            네트워크 호출 직전에 `guard AppEnv.isBundledApp || AppEnv.isParityRun else { … }` 를 둘 것: \
            \(offenders.joined(separator: ", "))
            """)
    }
}
