import XCTest
@testable import PokeTokenBar

/// GUI 앱은 로그인 셸 환경을 상속하지 않는다. 사용량 로그 위치를 가리키는 override 변수를
/// 프로세스 환경에서만 읽으면, `~/.zshrc` 에 export 해 둔 사용자는 앱에서만 조용히 0 을 보고
/// CLI·테스트에서는 정상이라 재현이 안 된다. 이 스위트는 그 분기를 고정한다.
final class UsageEnvironmentTests: XCTestCase {

    // MARK: 조회 정책

    /// 프로세스 환경에 전부 있으면 셸을 **띄우지 않는다**. 이 가드가 없으면 "일단 항상 셸을 물어보는"
    /// 구현이 통과하고, override 를 안 쓰는 대다수 사용자가 기동마다 spawn 비용(실측 ~0.44s)을 문다.
    func testAllPresentInProcessEnvironmentSkipsShellLookup() {
        var shellCalls: [[String]] = []
        let out = UsageEnvironment.resolve(
            names: ["A_HOME", "B_HOME"],
            processEnvironment: ["A_HOME": "/a", "B_HOME": "/b"],
            shellLookup: { shellCalls.append($0); return [:] })

        XCTAssertEqual(out, ["A_HOME": "/a", "B_HOME": "/b"])
        XCTAssertTrue(shellCalls.isEmpty, "프로세스 환경에 다 있는데 셸을 띄웠다: \(shellCalls)")
    }

    /// 없는 것이 하나라도 있으면 **없는 것만 모아 한 번** 물어본다. 이름마다 부르면 프로바이더가
    /// 늘수록 기동이 그만큼 느려진다.
    func testMissingNamesBatchedIntoSingleShellLookup() {
        var shellCalls: [[String]] = []
        let out = UsageEnvironment.resolve(
            names: ["A_HOME", "B_HOME", "C_HOME"],
            processEnvironment: ["B_HOME": "/b"],
            shellLookup: {
                shellCalls.append($0)
                return ["A_HOME": "/shell/a", "C_HOME": "/shell/c"]
            })

        XCTAssertEqual(shellCalls.count, 1, "셸 조회는 1회여야 한다: \(shellCalls)")
        XCTAssertEqual(shellCalls.first, ["A_HOME", "C_HOME"], "없는 이름만 넘겨야 한다")
        XCTAssertEqual(out, ["A_HOME": "/shell/a", "B_HOME": "/b", "C_HOME": "/shell/c"])
    }

    /// 결함 트리거 분기: 프로세스 환경에 **없어서** 셸에서만 값이 오는 경우.
    /// 회귀(프로세스 환경만 읽기)는 정확히 이 케이스에서만 드러나고, 값이 양쪽에 다 있는
    /// 케이스로 테스트하면 통과해 버린다.
    func testValueVisibleOnlyToLoginShellIsPickedUp() {
        let out = UsageEnvironment.resolve(
            names: ["COPILOT_HOME"],
            processEnvironment: [:],
            shellLookup: { _ in ["COPILOT_HOME": "/Users/someone/relocated"] })

        XCTAssertEqual(out["COPILOT_HOME"], "/Users/someone/relocated",
                       "GUI 앱에서만 안 보이던 값을 못 집었다 — 회귀")
    }

    /// `export FOO=` 는 "여기 있다"가 아니다. 빈 값을 값으로 받으면 존재하지 않는 경로를
    /// 스캔하고 조용히 0 을 받는다.
    func testBlankProcessValueFallsBackToShell() {
        let out = UsageEnvironment.resolve(
            names: ["HERMES_HOME"],
            processEnvironment: ["HERMES_HOME": "   "],
            shellLookup: { _ in ["HERMES_HOME": "/real"] })
        XCTAssertEqual(out["HERMES_HOME"], "/real")
    }

    /// 셸이 공백만 돌려줘도 미설정으로 본다(위와 같은 이유, 반대 방향).
    func testBlankShellValueIsDiscarded() {
        let out = UsageEnvironment.resolve(
            names: ["HERMES_HOME"],
            processEnvironment: [:],
            shellLookup: { _ in ["HERMES_HOME": "  \n "] })
        XCTAssertNil(out["HERMES_HOME"])
    }

    // MARK: 배치 마커 파싱

    /// 값이 여러 개면 마커 쌍도 여러 개다. 순서가 아니라 **이름으로** 짝을 찾아야
    /// 인터랙티브 프로파일이 중간에 찍는 noise 에 밀리지 않는다.
    func testParseMarkedValuePicksPairByNameAcrossNoise() {
        let raw = """
        neofetch banner line
        <<<BIN:A_HOME:/first:BIN>>>oh-my-zsh noise<<<BIN:B_HOME:/second:BIN>>>
        trailing noise
        """
        XCTAssertEqual(BinaryLocator.parseMarkedValue(raw, name: "A_HOME"), "/first")
        XCTAssertEqual(BinaryLocator.parseMarkedValue(raw, name: "B_HOME"), "/second")
        XCTAssertNil(BinaryLocator.parseMarkedValue(raw, name: "C_HOME"), "없는 이름은 nil")
    }

    /// 미설정 변수는 빈 값으로 돌아온다 — 빈 문자열을 값으로 승격하면 안 된다.
    func testParseMarkedValueTreatsEmptyPairAsAbsent() {
        XCTAssertNil(BinaryLocator.parseMarkedValue("<<<BIN:A_HOME::BIN>>>", name: "A_HOME"))
    }

    /// 이름이 다른 이름의 접두사여도 섞이지 않는다(`A_HOME` vs `A_HOME_EXTRA`).
    func testParseMarkedValueDoesNotConfusePrefixNames() {
        let raw = "<<<BIN:A_HOME_EXTRA:/extra:BIN>>><<<BIN:A_HOME:/plain:BIN>>>"
        XCTAssertEqual(BinaryLocator.parseMarkedValue(raw, name: "A_HOME_EXTRA"), "/extra")
    }

    // MARK: 셸 주입 가드

    func testShellSafeEnvironmentNameRejectsInjectionShapes() {
        for good in ["GROK_HOME", "A1_B2", "X"] {
            XCTAssertTrue(BinaryLocator.isShellSafeEnvironmentName(good), good)
        }
        // 소문자·유니코드 대문자·메타문자·빈 문자열은 모두 거부.
        for bad in ["", "grok_home", "A-B", "A B", "A;rm -rf /", "Σ", "А", "٣", "A$B"] {
            XCTAssertFalse(BinaryLocator.isShellSafeEnvironmentName(bad), bad)
        }
    }

    /// 이름이 전부 거부되면 셸을 띄우지 않고 즉시 빈 결과.
    func testShellEnvironmentValuesRejectsAllUnsafeNamesWithoutSpawning() {
        XCTAssertTrue(BinaryLocator.shellEnvironmentValues([]).isEmpty)
        XCTAssertTrue(BinaryLocator.shellEnvironmentValues(["bad name", "x"]).isEmpty)
    }

    // MARK: 레지스트리 무결성 (부류 재발 방지)

    /// 사용량 위치 override 변수를 `UsageEnvironment` 를 거치지 않고 프로세스 환경에서 직독하면
    /// 이 테스트가 깨진다. 새 프로바이더가 같은 실수를 반복하는 것을 기계로 막는 지점이다.
    ///
    /// 허용 목록은 "사용자가 셸에 export 해 두는 값이 아닌 것"만 담는다:
    /// - `UsageEnvironment` 자신(프로세스 환경을 읽는 유일한 정당한 위치)
    /// - `BinaryLocator`: 자식 프로세스 환경 구성과 `SHELL` — 앱이 쓰는 값이지 사용자 override 가 아니다
    /// - `CompanionStore`: `PTB_STATE_DIR` 은 개발/QA 격리용
    /// - `OAuthLimitsProvider`: 의도적으로 프로세스 환경만 본다(자동 폴링 경로에서 셸 spawn 금지 —
    ///   해당 함수 주석 참조). 값이 필요한 사용량 스캔 쪽이 이미 셸 조회를 한다.
    /// - `AppEnv`: `PTB_PARITY` 라이브 검증 플래그 — CompanionStore 의 PTB_STATE_DIR 과 같은 QA 부류
    func testNoProviderReadsUsageLocationEnvDirectly() throws {
        let allowed: Set<String> = [
            "UsageEnvironment.swift",
            "BinaryLocator.swift",
            "CompanionStore.swift",
            "OAuthLimitsProvider.swift",
            "AppEnv.swift",
        ]
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // PokeTokenBarTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo root
            .appendingPathComponent("Sources/PokeTokenBar")

        var offenders: [String] = []
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard !allowed.contains(url.lastPathComponent) else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("ProcessInfo.processInfo.environment[") {
                offenders.append("\(url.lastPathComponent):\(index + 1)")
            }
        }

        XCTAssertTrue(offenders.isEmpty, """
            사용량 위치 환경변수는 UsageEnvironment 를 통해 읽어야 한다(GUI 앱은 셸 환경 미상속).
            직독 지점: \(offenders.joined(separator: ", "))
            """)
    }

    /// 실제로 조회되는 이름 집합이 프로바이더 override 와 어긋나지 않게 고정한다.
    func testRegisteredNamesCoverEveryProviderOverride() {
        for name in [
            "CLAUDE_CONFIG_DIR", "OPENCODE_DATA_DIR", "HERMES_HOME", "COPILOT_HOME", "GROK_HOME",
            "CLOUD_CODE_URL", "PI_CODING_AGENT_DIR", "PI_CODING_AGENT_SESSION_DIR",
        ] {
            XCTAssertTrue(UsageEnvironment.names.contains(name), "\(name) 이 조회 대상에서 빠졌다")
        }
        XCTAssertEqual(Set(UsageEnvironment.names).count, UsageEnvironment.names.count, "이름 중복")
        for name in UsageEnvironment.names {
            XCTAssertTrue(BinaryLocator.isShellSafeEnvironmentName(name), "\(name) 은 셸 조회가 거부한다")
        }
    }
}

/// 사용자 상태 파일 접근 게이트 — 스토어마다 복사되던 판정을 한 곳으로 모은 뒤의 단일 진실.
final class UserLocationGateTests: XCTestCase {
    func testInjectedPathIsAlwaysLive() {
        let tmp = URL(fileURLWithPath: "/tmp/whatever.json")
        XCTAssertTrue(AppEnv.persistsToUserLocation(injectedFileURL: tmp, isBundledApp: false))
        XCTAssertTrue(AppEnv.persistsToUserLocation(injectedFileURL: tmp, isBundledApp: true))
    }

    /// 이 한 줄이 스위트가 사용자 파일을 건드리지 않게 하는 전부다.
    func testDefaultPathIsInertUnlessBundled() {
        XCTAssertFalse(AppEnv.persistsToUserLocation(injectedFileURL: nil, isBundledApp: false))
        XCTAssertTrue(AppEnv.persistsToUserLocation(injectedFileURL: nil, isBundledApp: true))
    }

    /// `swift test` 는 번들 실행이 아니다 — 이 전제가 깨지면 위 게이트가 통째로 무의미해진다.
    func testTestBinaryIsNotABundledApp() {
        XCTAssertFalse(AppEnv.isBundledApp)
    }
}
