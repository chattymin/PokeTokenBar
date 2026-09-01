import XCTest
@testable import PokeTokenBar

/// claude.ai 세션 키 기반 한도 조회 — 자격증명 저장, 조직 선택, OAuth 폴백 체인.
///
/// 실 엔드포인트는 Cloudflare 챌린지 때문에 CI 에서 검증할 수 없다(curl 은 403, URLSession 만 200).
/// 그래서 HTTP 계층을 시임으로 갈아끼고, 픅스처는 실 응답에서 식별정보만 지운 것을 쓴다.

// MARK: 픅스처 (실 응답 기반 — uuid·이름만 익명화)

private let orgsJSON = """
[
  {"uuid":"org-personal","name":"user@example.com's Organization",
   "capabilities":["chat"],"rate_limit_tier":"default_claude_ai"},
  {"uuid":"org-api","name":"Individual Org",
   "capabilities":["api","api_individual"],"rate_limit_tier":"auto_api_evaluation"},
  {"uuid":"org-team","name":"Team Plan",
   "capabilities":["raven","chat"],"rate_limit_tier":"default_raven"}
]
"""

/// 로그인만 해두고 안 쓰는 조직 — utilization 0, resets_at null. 실제로 이 응답이 먼저 온다.
private let idleUsageJSON = """
{"five_hour":{"utilization":0,"resets_at":null},
 "seven_day":{"utilization":0,"resets_at":null},
 "seven_day_opus":null,"seven_day_sonnet":null,
 "limits":[{"kind":"session","group":"session","percent":0,"severity":"normal","resets_at":null}]}
"""

/// 실제로 쓰는 조직 — 값이 있다.
private let activeUsageJSON = """
{"five_hour":{"utilization":7,"resets_at":"2026-08-21T17:20:00.186770+00:00"},
 "seven_day":{"utilization":30,"resets_at":"2026-08-25T23:00:00.186790+00:00"},
 "seven_day_opus":null,"seven_day_sonnet":null,
 "limits":[{"kind":"session","group":"session","percent":7,"severity":"normal",
            "resets_at":"2026-08-21T17:20:00.186770+00:00"}]}
"""

private let forbiddenJSON = """
{"type":"error","error":{"type":"permission_error","message":"Invalid authorization for organization"}}
"""

private func ok(_ json: String) -> SessionKeyHTTPResponse {
    SessionKeyHTTPResponse(status: 200, data: Data(json.utf8), retryAfter: nil)
}

private func fail(_ status: Int, _ json: String = "{}", retryAfter: TimeInterval? = nil) -> SessionKeyHTTPResponse {
    SessionKeyHTTPResponse(status: status, data: Data(json.utf8), retryAfter: retryAfter)
}

// MARK: 시임

/// path → 응답. 조직별 usage 를 병렬로 조회하므로 actor 로 감싼다(기록 배열 경합 방지).
private actor StubSessionKeyHTTP: SessionKeyHTTPClient {
    private var responses: [String: SessionKeyHTTPResponse]
    private(set) var requestedPaths: [String] = []
    private(set) var seenSessionKeys: [String] = []

    init(_ responses: [String: SessionKeyHTTPResponse]) { self.responses = responses }

    func get(_ url: URL, sessionKey: String) async throws -> SessionKeyHTTPResponse {
        requestedPaths.append(url.path)
        seenSessionKeys.append(sessionKey)
        return responses[url.path] ?? fail(404)
    }

    func paths() -> [String] { requestedPaths }
    func keys() -> [String] { seenSessionKeys }
}

private struct StubOAuthLimits: ClaudeLimitsProviding {
    let status: LimitStatus?
    let error: any Error
    init(status: LimitStatus?, error: any Error = LimitsError.keychainInteractionNotAllowed) {
        self.status = status
        self.error = error
    }
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        guard let status else { throw error }
        return status
    }
}

/// 폴백이 어떤 `allowKeychainPrompt` 로 불렸는지 기록하는 스텁 — 값 자체가 검증 대상이라
/// 상태를 돌려주는 것만으로는 부족하다(프롬프트 억제는 반환값에 안 드러난다).
private final class RecordingOAuthLimits: ClaudeLimitsProviding, @unchecked Sendable {
    private(set) var seenAllowPrompt: [Bool] = []
    let status: LimitStatus?
    init(status: LimitStatus?) { self.status = status }
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        seenAllowPrompt.append(allowKeychainPrompt)
        guard let status else { throw LimitsError.keychainInteractionNotAllowed }
        return status
    }
}

private func limitStatus(fiveHour: Double) -> LimitStatus {
    try! JSONDecoder().decode(
        LimitStatus.self, from: Data("{\"five_hour\":{\"utilization\":\(fiveHour)}}".utf8))
}

private let orgsPath = "/api/organizations"
private func usagePath(_ id: String) -> String { "/api/organizations/\(id)/usage" }

// MARK: 테스트

final class SessionKeyLimitsTests: XCTestCase {
    private var tempDir: URL!
    private var store: SessionKeyStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ptb-sk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = SessionKeyStore(fileURL: tempDir.appendingPathComponent("session-key.json"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func seed(_ key: String = "sk-ant-sid02-\(String(repeating: "a", count: 60))",
                      org: String? = nil) throws {
        try store.save(SessionKeyCredential(key: key, organizationID: org))
    }

    // MARK: 저장소

    func testStoreRoundTripsCredentialWithOwnerOnlyPermissions() throws {
        try seed(org: "org-team")
        let loaded = store.load()
        XCTAssertEqual(loaded?.organizationID, "org-team")
        XCTAssertTrue(loaded?.key.hasPrefix("sk-ant-sid02-") == true)

        // 평문 파일이므로 소유자 외 읽기는 막아야 한다 (앱 소유 Keychain 항목은 금지 부류 — defect-log).
        let mode = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.int16Value, 0o600, "세션 키 파일은 0600 이어야 한다")

        store.clear()
        XCTAssertNil(store.load(), "삭제 후에는 자격증명이 없어야 한다")
    }

    func testStoreRejectsMalformedKeys() {
        for bad in ["", "   ", "abc", "not-a-key-but-long-enough-to-pass-length-checks-only",
                    "sk-ant-\u{0}embedded-nul-plus-padding-to-reach-minimum-length-xxxx"] {
            XCTAssertThrowsError(try SessionKeyStore.normalize(bad), "\"\(bad.prefix(12))…\" 는 거부돼야 한다") { error in
                XCTAssertEqual(error as? LimitsError, LimitsError.sessionKeyMalformed)
            }
        }
    }

    func testStoreNormalizesSurroundingWhitespace() throws {
        let raw = "  sk-ant-sid02-\(String(repeating: "b", count: 60))\n"
        XCTAssertEqual(try SessionKeyStore.normalize(raw), raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: 조직 선택

    /// 핵심 회귀 가드: 참조 구현(`organizations.first!`)은 이 픅스처에서 영구히 0% 를 표시한다.
    /// API 전용 조직의 403 을 건너뛰고, 실제로 사용 중인 조직을 골라야 한다.
    func testFetchSkipsForbiddenOrgAndPicksTheOneWithUsage() async throws {
        try seed()
        let http = StubSessionKeyHTTP([
            orgsPath: ok(orgsJSON),
            usagePath("org-personal"): ok(idleUsageJSON),
            usagePath("org-api"): fail(403, forbiddenJSON),
            usagePath("org-team"): ok(activeUsageJSON),
        ])
        let provider = SessionKeyLimitsProvider(store: store, http: http)

        let limits = try await provider.fetch(allowKeychainPrompt: false)

        XCTAssertEqual(limits.fiveHour?.utilization, 7)
        XCTAssertEqual(limits.sevenDay?.utilization, 30)
        // 고른 조직은 캐시돼야 한다 — 매 폴링마다 조직 목록을 다시 훑지 않도록.
        XCTAssertEqual(store.load()?.organizationID, "org-team")
    }

    /// 세션 키 경로는 Keychain 을 건드리지 않으므로 프롬프트 플래그와 무관하게 같은 결과를 내야 한다.
    func testFetchIgnoresKeychainPromptFlag() async throws {
        try seed(org: "org-team")
        let http = StubSessionKeyHTTP([usagePath("org-team"): ok(activeUsageJSON)])
        let provider = SessionKeyLimitsProvider(store: store, http: http)

        for allow in [false, true] {
            let limits = try await provider.fetch(allowKeychainPrompt: allow)
            XCTAssertEqual(limits.fiveHour?.utilization, 7, "allowKeychainPrompt=\(allow)")
        }
    }

    func testFetchReusesCachedOrgWithoutListingOrganizations() async throws {
        try seed(org: "org-team")
        let http = StubSessionKeyHTTP([
            orgsPath: ok(orgsJSON),
            usagePath("org-team"): ok(activeUsageJSON),
        ])
        let provider = SessionKeyLimitsProvider(store: store, http: http)

        _ = try await provider.fetch(allowKeychainPrompt: false)

        let paths = await http.paths()
        XCTAssertEqual(paths, [usagePath("org-team")],
                       "캐시된 조직이 있으면 목록 조회 없이 usage 만 쳐야 한다")
    }

    /// 조직에서 빠졌거나 권한이 사라진 경우(403) — 목록을 다시 훑어 살아있는 조직으로 옮겨간다.
    func testFetchRerunsDiscoveryWhenCachedOrgLosesAccess() async throws {
        try seed(org: "org-api")
        let http = StubSessionKeyHTTP([
            orgsPath: ok(orgsJSON),
            usagePath("org-personal"): ok(idleUsageJSON),
            usagePath("org-api"): fail(403, forbiddenJSON),
            usagePath("org-team"): ok(activeUsageJSON),
        ])
        let provider = SessionKeyLimitsProvider(store: store, http: http)

        let limits = try await provider.fetch(allowKeychainPrompt: false)

        XCTAssertEqual(limits.fiveHour?.utilization, 7)
        XCTAssertEqual(store.load()?.organizationID, "org-team", "캐시는 살아있는 조직으로 갱신돼야 한다")
    }

    /// 후보가 하나뿐이면(chat 없는 조직 제외) 그걸 쓴다 — 대부분 사용자의 경로.
    func testFetchUsesSingleChatOrgWithoutProbingApiOnlyOrgs() async throws {
        try seed()
        let single = """
        [{"uuid":"org-solo","name":"Me","capabilities":["chat"]},
         {"uuid":"org-api","name":"API","capabilities":["api"]}]
        """
        let http = StubSessionKeyHTTP([
            orgsPath: ok(single),
            usagePath("org-solo"): ok(activeUsageJSON),
        ])
        let provider = SessionKeyLimitsProvider(store: store, http: http)

        let limits = try await provider.fetch(allowKeychainPrompt: false)

        XCTAssertEqual(limits.fiveHour?.utilization, 7)
        let paths = await http.paths()
        XCTAssertFalse(paths.contains(usagePath("org-api")), "API 전용 조직은 아예 조회하지 않는다")
    }

    // MARK: 스키마 변동 방어 (응답이 우리 기대와 다를 때)

    /// `capabilities`/`name` 이 빠진 응답 — 필터로 후보를 0개로 만들거나 이름 없이 크래시하면 안 된다.
    /// 외부 JSON 이라 우리가 막을 수 없는 변화다.
    func testOrganizationsKeepRowsMissingCapabilitiesAndFallBackToUUIDName() async throws {
        let drifted = """
        [{"uuid":"org-unknown-shape"}]
        """
        let http = StubSessionKeyHTTP([
            orgsPath: ok(drifted),
            usagePath("org-unknown-shape"): ok(activeUsageJSON),
        ])
        let provider = SessionKeyLimitsProvider(store: store, http: http)

        let orgs = try await provider.organizations(sessionKey: "sk-ant-sid02-\(String(repeating: "d", count: 60))")

        XCTAssertEqual(orgs.map(\.id), ["org-unknown-shape"], "capabilities 가 없으면 후보로 남겨야 한다")
        XCTAssertEqual(orgs.first?.name, "org-unknown-shape", "이름이 없으면 uuid 로 표시한다")
    }

    /// chat 조직이 하나도 없는 계정(API 전용) — 필터 결과가 비면 전체를 후보로 되돌려 최소한 시도한다.
    func testFetchFallsBackToAllRowsWhenNoChatCapableOrgExists() async throws {
        try seed()
        let apiOnly = """
        [{"uuid":"org-api-1","name":"API One","capabilities":["api"]}]
        """
        let http = StubSessionKeyHTTP([
            orgsPath: ok(apiOnly),
            usagePath("org-api-1"): ok(activeUsageJSON),
        ])
        let provider = SessionKeyLimitsProvider(store: store, http: http)

        let limits = try await provider.fetch(allowKeychainPrompt: false)

        XCTAssertEqual(limits.fiveHour?.utilization, 7, "chat 조직이 없으면 남은 조직이라도 조회한다")
    }

    /// 레거시 창(`five_hour`/`seven_day`)이 빠지고 `limits[]` 만 오는 형태 — 신형 응답에서 관측된 조합이다.
    /// percent 가 없어도 resets_at 이 있으면 사용 중으로 봐야 한다(빈 조직으로 오판하면 0% 를 표시한다).
    func testUsageDetectionUsesLimitsArrayWhenLegacyWindowsAreAbsent() async throws {
        let emptyShape = "{}"
        let limitsOnly = """
        {"limits":[{"kind":"session","group":"session",
                    "resets_at":"2026-08-21T17:20:00.186770+00:00"}]}
        """
        let rows = """
        [{"uuid":"org-empty","name":"Empty","capabilities":["chat"]},
         {"uuid":"org-new","name":"New shape","capabilities":["chat"]}]
        """
        let http = StubSessionKeyHTTP([
            orgsPath: ok(rows),
            usagePath("org-empty"): ok(emptyShape),
            usagePath("org-new"): ok(limitsOnly),
        ])
        let provider = SessionKeyLimitsProvider(store: store, http: http)

        let orgs = try await provider.organizations(sessionKey: "sk-ant-sid02-\(String(repeating: "e", count: 60))")

        XCTAssertEqual(orgs.map(\.hasUsageData), [false, true],
                       "limits[] 의 resets_at 만으로도 사용 중 조직을 알아내야 한다")
    }

    // MARK: 오류 매핑

    func testFetchThrowsMissingWhenNoCredentialStored() async {
        let http = StubSessionKeyHTTP([:])
        let provider = SessionKeyLimitsProvider(store: store, http: http)
        do {
            _ = try await provider.fetch(allowKeychainPrompt: false)
            XCTFail("자격증명이 없으면 던져야 한다")
        } catch {
            XCTAssertEqual(error as? LimitsError, LimitsError.sessionKeyMissing)
        }
        let paths = await http.paths()
        XCTAssertTrue(paths.isEmpty, "키가 없으면 네트워크를 치지 않는다")
    }

    /// [회귀·실측] 키가 죽으면 claude.ai 는 401 이 아니라 **403** 을 준다 — 실제 앱에서 세션 키
    /// 한 글자를 바꿔 확인했다(usage 와 organizations 가 함께 403, 로그 `session key limits failed:
    /// httpStatus(403)`). `/api/organizations` 는 조직 스코프가 아니므로 여기서의 403 은 "그 조직에
    /// 권한 없음"이 아니라 **이 키로는 아무것도 못 본다**는 뜻이다.
    ///
    /// 이게 `httpStatus(403)` 으로 새 나가면 `UsageStore.updateAuthExpired` 가 401/403 을 OAuth
    /// 만료로 분류해, 세션 키 사용자에게 "Claude Code 를 한 번 실행하면 자동 갱신됩니다"라는 듣지
    /// 않는 안내와 Keychain 을 읽는 재시도 버튼이 나간다 — 세션 키 만료 안내를 따로 만든 의미가 없어진다.
    ///
    /// **조직 단위 403 은 건드리지 않는다**: 캐시된 조직의 usage 가 403 이면 그건 진짜로 그 조직
    /// 권한 문제이고, `fetch` 가 이미 재탐색으로 처리한다(그 경로는 이 매핑을 타지 않는다).
    func testForbiddenOrganizationListMapsToInvalidKey() async throws {
        try seed()
        let http = StubSessionKeyHTTP([orgsPath: fail(403)])
        let provider = SessionKeyLimitsProvider(store: store, http: http)
        do {
            _ = try await provider.fetch(allowKeychainPrompt: false)
            XCTFail("403 은 키 무효로 매핑돼야 한다 — 실측상 죽은 키의 실제 응답이다")
        } catch {
            XCTAssertEqual(error as? LimitsError, LimitsError.sessionKeyInvalid)
        }
    }

    func testUnauthorizedOrganizationListMapsToInvalidKey() async throws {
        try seed()
        let http = StubSessionKeyHTTP([orgsPath: fail(401)])
        let provider = SessionKeyLimitsProvider(store: store, http: http)
        do {
            _ = try await provider.fetch(allowKeychainPrompt: false)
            XCTFail("401 은 키 무효로 매핑돼야 한다")
        } catch {
            XCTAssertEqual(error as? LimitsError, LimitsError.sessionKeyInvalid)
        }
    }

    /// 캐시된 조직에서 401 이 오면 키 자체가 죽은 것 — 조직 탐색을 다시 하지 않는다(403 과 구분).
    func testUnauthorizedUsageMapsToInvalidKeyWithoutRediscovery() async throws {
        try seed(org: "org-team")
        let http = StubSessionKeyHTTP([
            orgsPath: ok(orgsJSON),
            usagePath("org-team"): fail(401),
        ])
        let provider = SessionKeyLimitsProvider(store: store, http: http)
        do {
            _ = try await provider.fetch(allowKeychainPrompt: false)
            XCTFail("401 은 키 무효로 매핑돼야 한다")
        } catch {
            XCTAssertEqual(error as? LimitsError, LimitsError.sessionKeyInvalid)
        }
        let paths = await http.paths()
        XCTAssertFalse(paths.contains(orgsPath), "401 에서는 조직 재탐색을 하지 않는다")
    }

    func testRateLimitedMapsToBackoffErrorWithRetryAfter() async throws {
        try seed(org: "org-team")
        let http = StubSessionKeyHTTP([usagePath("org-team"): fail(429, "{}", retryAfter: 120)])
        let provider = SessionKeyLimitsProvider(store: store, http: http)
        do {
            _ = try await provider.fetch(allowKeychainPrompt: false)
            XCTFail("429 는 rateLimited 로 매핑돼야 한다")
        } catch LimitsError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 120)
        } catch {
            XCTFail("예상과 다른 오류: \(error)")
        }
    }

    /// 200 이 하나도 없으면(전부 403) 키는 유효하지만 볼 조직이 없다 — 별도 안내가 필요하다.
    func testNoAccessibleOrganizationIsItsOwnError() async throws {
        try seed()
        let http = StubSessionKeyHTTP([
            orgsPath: ok(orgsJSON),
            usagePath("org-personal"): fail(403, forbiddenJSON),
            usagePath("org-api"): fail(403, forbiddenJSON),
            usagePath("org-team"): fail(403, forbiddenJSON),
        ])
        let provider = SessionKeyLimitsProvider(store: store, http: http)
        do {
            _ = try await provider.fetch(allowKeychainPrompt: false)
            XCTFail("접근 가능한 조직이 없으면 던져야 한다")
        } catch {
            XCTAssertEqual(error as? LimitsError, LimitsError.sessionKeyNoOrganization)
        }
    }

    // MARK: 조직 후보 목록 (설정 UI 드롭다운)

    func testOrganizationsReportsCandidatesWithAccessAndUsageFlags() async throws {
        let http = StubSessionKeyHTTP([
            orgsPath: ok(orgsJSON),
            usagePath("org-personal"): ok(idleUsageJSON),
            usagePath("org-api"): fail(403, forbiddenJSON),
            usagePath("org-team"): ok(activeUsageJSON),
        ])
        let provider = SessionKeyLimitsProvider(store: store, http: http)

        let orgs = try await provider.organizations(sessionKey: "sk-ant-sid02-\(String(repeating: "c", count: 60))")

        // API 전용 조직은 후보에서 빠지고, 접근 가능한 것만 순서를 유지해 남는다.
        XCTAssertEqual(orgs.map(\.id), ["org-personal", "org-team"])
        XCTAssertEqual(orgs.map(\.hasUsageData), [false, true])
        XCTAssertEqual(orgs.last?.name, "Team Plan")
    }

    // MARK: 체인 (세션 키 우선 → OAuth 폴백)

    func testChainPrefersSessionKeyAndNeverCallsFallback() async throws {
        try seed(org: "org-team")
        let http = StubSessionKeyHTTP([usagePath("org-team"): ok(activeUsageJSON)])
        let chain = ChainedLimitsProvider(
            primary: SessionKeyLimitsProvider(store: store, http: http),
            fallback: StubOAuthLimits(status: limitStatus(fiveHour: 99)))

        let limits = try await chain.fetch(allowKeychainPrompt: false)

        XCTAssertEqual(limits.fiveHour?.utilization, 7, "세션 키 결과가 우선이어야 한다")
    }

    func testChainFallsBackToOAuthWhenNoSessionKeyStored() async throws {
        let http = StubSessionKeyHTTP([:])
        let chain = ChainedLimitsProvider(
            primary: SessionKeyLimitsProvider(store: store, http: http),
            fallback: StubOAuthLimits(status: limitStatus(fiveHour: 42)))

        let limits = try await chain.fetch(allowKeychainPrompt: false)

        XCTAssertEqual(limits.fiveHour?.utilization, 42, "키가 없으면 기존 OAuth 경로로 내려가야 한다")
    }

    /// 키가 없어서 실패한 경우엔 기존 안내(자격증명 없음)를 그대로 보여준다.
    func testChainSurfacesFallbackErrorWhenSessionKeyIsAbsent() async {
        let http = StubSessionKeyHTTP([:])
        let chain = ChainedLimitsProvider(
            primary: SessionKeyLimitsProvider(store: store, http: http),
            fallback: StubOAuthLimits(status: nil, error: LimitsError.credentialMissingAccountOAuth))
        do {
            _ = try await chain.fetch(allowKeychainPrompt: false)
            XCTFail("둘 다 실패하면 던져야 한다")
        } catch {
            XCTAssertEqual(error as? LimitsError, LimitsError.credentialMissingAccountOAuth)
        }
    }

    /// 키를 넣어놨는데 죽었으면 그 사실이 더 유용하다 — OAuth 실패 메시지로 덮지 않는다.
    func testChainSurfacesSessionKeyErrorWhenKeyIsPresentButBroken() async throws {
        try seed()
        let http = StubSessionKeyHTTP([orgsPath: fail(401)])
        let chain = ChainedLimitsProvider(
            primary: SessionKeyLimitsProvider(store: store, http: http),
            fallback: StubOAuthLimits(status: nil, error: LimitsError.keychainInteractionNotAllowed))
        do {
            _ = try await chain.fetch(allowKeychainPrompt: false)
            XCTFail("둘 다 실패하면 던져야 한다")
        } catch {
            XCTAssertEqual(error as? LimitsError, LimitsError.sessionKeyInvalid,
                           "키 재입력 안내를 덮어쓰면 사용자가 원인을 알 수 없다")
        }
    }

    /// 키가 죽었어도 OAuth 가 살아있으면 한도는 계속 보여야 한다(섹션이 사라지지 않게).
    func testChainStillFallsBackWhenSessionKeyIsBroken() async throws {
        try seed()
        let http = StubSessionKeyHTTP([orgsPath: fail(401)])
        let chain = ChainedLimitsProvider(
            primary: SessionKeyLimitsProvider(store: store, http: http),
            fallback: StubOAuthLimits(status: limitStatus(fiveHour: 42)))

        let limits = try await chain.fetch(allowKeychainPrompt: false)

        XCTAssertEqual(limits.fiveHour?.utilization, 42)
    }

    /// [회귀] 키를 넣어 둔 사용자에게는 폴백이 **Keychain 을 열지 못한다.** 이 기능의 존재 이유가
    /// 그 프롬프트를 없애는 것이라, 죽은 키 때문에 수동 갱신에서 프롬프트가 되살아나면 기능이
    /// 스스로를 무효화한다. `allowKeychainPrompt` 를 그대로 넘기던 원래 코드로 되돌리면 실패한다.
    func testConfiguredButBrokenKeyNeverLetsFallbackOpenTheKeychain() async throws {
        try seed()
        let fallback = RecordingOAuthLimits(status: limitStatus(fiveHour: 42))
        let chain = ChainedLimitsProvider(
            primary: SessionKeyLimitsProvider(store: store, http: StubSessionKeyHTTP([orgsPath: fail(401)])),
            fallback: fallback)

        _ = try await chain.fetch(allowKeychainPrompt: true)   // 수동 갱신 버튼 경로

        XCTAssertEqual(fallback.seenAllowPrompt, [false],
                       "세션 키가 설정돼 있으면 수동 갱신이라도 Keychain 을 열면 안 된다")
    }

    /// A||B 의 반대편 — 키가 **없는** 사용자는 기존 동작 그대로다. 수동 갱신은 여전히 Keychain 을
    /// 읽어야 하고, 위 가드가 그 경로까지 막으면 키를 안 쓰는 사람의 한도가 조용히 죽는다.
    func testWithoutAStoredKeyManualRefreshStillReachesTheKeychain() async throws {
        let fallback = RecordingOAuthLimits(status: limitStatus(fiveHour: 7))
        let chain = ChainedLimitsProvider(
            primary: SessionKeyLimitsProvider(store: store, http: StubSessionKeyHTTP([:])),
            fallback: fallback)

        _ = try await chain.fetch(allowKeychainPrompt: true)

        XCTAssertEqual(fallback.seenAllowPrompt, [true],
                       "키가 없으면 수동 갱신은 예전처럼 Keychain 을 읽는다")
    }
}

// MARK: 저장 위치 격리 (PTB_STATE_DIR)

/// companion 상태와 같은 격리 규약을 따르는지 — QA·데모 실행이 실제 자격증명을 건드리면 안 된다.
/// (환경변수를 바꾸므로 별도 클래스: XCTest 는 클래스 단위로 직렬 실행한다.)
final class SessionKeyStoreLocationTests: XCTestCase {
    func testDefaultPathHonorsStateDirOverride() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ptb-statedir-\(UUID().uuidString)", isDirectory: true)
        setenv("PTB_STATE_DIR", dir.path, 1)
        defer { unsetenv("PTB_STATE_DIR") }

        let store = SessionKeyStore()
        XCTAssertEqual(store.fileURL.deletingLastPathComponent().standardizedFileURL,
                       dir.standardizedFileURL,
                       "PTB_STATE_DIR 이 있으면 그 디렉토리에 저장해야 한다")

        try store.save(SessionKeyCredential(key: "sk-ant-sid02-\(String(repeating: "f", count: 60))",
                                            organizationID: "org"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
        try? FileManager.default.removeItem(at: dir)
    }

    /// 공백만 있는 값은 무시 — `URL(fileURLWithPath:)` 가 CWD 상대경로로 해석하는 것을 막는다.
    func testBlankStateDirFallsBackToAppSupport() {
        setenv("PTB_STATE_DIR", "   ", 1)
        defer { unsetenv("PTB_STATE_DIR") }
        XCTAssertEqual(SessionKeyStore().fileURL.lastPathComponent, "session-key.json")
        XCTAssertTrue(SessionKeyStore().fileURL.path.contains("Application Support"),
                      "공백 값은 무시하고 기본 위치를 쓴다")
    }
}
