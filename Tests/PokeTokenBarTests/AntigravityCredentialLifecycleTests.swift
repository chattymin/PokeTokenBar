import XCTest
@testable import PokeTokenBar

/// 보관 중인 자격증명의 **관측 가능성과 폐기**.
///
/// 이 refresh token 은 만료도 교체도 되지 않는다 — 유출을 탐지할 방법이 없고, 시간이 지나도
/// 저절로 무해해지지 않는다. 그래서 노출 창을 닫는 유일한 수단이 주기적 폐기이고, 그 판단 근거가
/// "얼마나 오래 들고 있었나" 다. 두 가지가 정확해야 이 기능이 의미를 갖는다.
final class AntigravityCredentialLifecycleTests: XCTestCase {

    // MARK: 보관 기간이 갱신마다 리셋되면 안 된다

    /// 액세스 토큰 갱신은 **새 grant 가 아니다.** 갱신마다 도장을 새로 찍으면 설정 화면의 보관 기간이
    /// 매시간 0 으로 돌아가, 정확히 그 숫자를 보고 폐기 시점을 정하려던 사용자에게 거짓말을 한다.
    func testRefreshKeepsTheOriginalObtainedAt() async throws {
        let store = try seed(refreshToken: "long-lived", obtainedAt: Date().addingTimeInterval(-40 * 86_400))
        defer { cleanup(store) }

        let cache = AntigravityTokenCache(
            tokenFileURLs: [],
            persistentStoreURL: store,
            tokenRefresher: { token, _ in
                .success(AntigravityOAuthCredential(
                    accessToken: "minted", refreshToken: token,
                    expiresAt: Date().addingTimeInterval(3600)))
            },
            clientSecretSource: { ["GOCSPX-any"] })

        _ = try await cache.accessToken(allowKeychainPrompt: false)
        let summary = await cache.storedCredentialSummary()

        let days = try XCTUnwrap(summary.obtainedAt.map {
            Calendar.current.dateComponents([.day], from: $0, to: Date()).day
        })
        XCTAssertEqual(days, 40, "갱신은 보관 기간을 리셋하지 않는다")
    }

    /// refresh token 이 **바뀌면** 새 grant 다(재로그인·계정 전환) — 그때는 도장을 다시 찍는다.
    func testNewRefreshTokenRestartsTheClock() async throws {
        let store = try seed(refreshToken: "old-token", obtainedAt: Date().addingTimeInterval(-40 * 86_400))
        defer { cleanup(store) }

        let cache = AntigravityTokenCache(
            tokenFileURLs: [],
            persistentStoreURL: store,
            tokenRefresher: { _, _ in
                .success(AntigravityOAuthCredential(
                    accessToken: "minted", refreshToken: "brand-new-token",
                    expiresAt: Date().addingTimeInterval(3600)))
            },
            clientSecretSource: { ["GOCSPX-any"] })

        _ = try await cache.accessToken(allowKeychainPrompt: false)
        let summary = await cache.storedCredentialSummary()

        let age = try XCTUnwrap(summary.obtainedAt.map { Date().timeIntervalSince($0) })
        XCTAssertLessThan(age, 5, "새 refresh token 은 새 grant 다 — 시계를 다시 시작한다")
    }

    /// 기존 자격증명(obtainedAt 없음)의 진짜 나이는 모른다 — 갱신하면서 오늘 날짜를 찍으면
    /// 몇 달 된 토큰이 "0일째" 로 보여 폐기를 **미루게 만드는** 방향으로 틀린다.
    func testLegacyCredentialAgeStaysUnknownRatherThanFabricated() async throws {
        let store = try seed(refreshToken: "pre-existing", obtainedAt: nil)
        defer { cleanup(store) }

        let cache = AntigravityTokenCache(
            tokenFileURLs: [],
            persistentStoreURL: store,
            tokenRefresher: { token, _ in
                .success(AntigravityOAuthCredential(
                    accessToken: "minted", refreshToken: token,
                    expiresAt: Date().addingTimeInterval(3600)))
            },
            clientSecretSource: { ["GOCSPX-any"] })

        _ = try await cache.accessToken(allowKeychainPrompt: false)
        let summary = await cache.storedCredentialSummary()

        XCTAssertTrue(summary.exists)
        XCTAssertNil(summary.obtainedAt, "모르는 시작일을 지어내지 않는다")
    }

    /// 이 필드가 생기기 전에 저장된 파일도 그대로 읽혀야 한다(마이그레이션 없음).
    func testCredentialWithoutObtainedAtStillDecodes() throws {
        let legacy = Data("""
        {"accessToken":"a","refreshToken":"b","expiresAt":760000000}
        """.utf8)
        let decoded = try JSONDecoder().decode(AntigravityOAuthCredential.self, from: legacy)
        XCTAssertEqual(decoded.refreshToken, "b")
        XCTAssertNil(decoded.obtainedAt)
    }

    // MARK: 폐기

    func testSummaryReportsNothingWhenNoCredentialIsStored() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = AntigravityTokenCache(
            tokenFileURLs: [], persistentStoreURL: dir.appendingPathComponent("absent.json"))
        let summary = await cache.storedCredentialSummary()

        XCTAssertFalse(summary.exists)
        XCTAssertNil(summary.obtainedAt)
    }

    func testRevokeWithNothingStoredIsNotAnError() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = AntigravityTokenCache(
            tokenFileURLs: [], persistentStoreURL: dir.appendingPathComponent("absent.json"))
        let result = await cache.revokeStoredCredential()

        XCTAssertEqual(result, .nothingStored)
    }

    /// **실패해도 로컬 파일을 지우면 안 된다.** 지우면 사용자는 재시도 수단을 잃고, 서버의 토큰은
    /// 살아 있는 채로 "정리됐다" 고 오해한다 — 폐기 기능이 정확히 반대 결과를 만든다.
    /// `swift test` 는 번들 앱이 아니라 네트워크 게이트에서 막히므로, 그 경로가 곧 실패 경로다.
    func testFailedRevokeKeepsTheLocalCredential() async throws {
        let store = try seed(refreshToken: "still-valid", obtainedAt: Date())
        defer { cleanup(store) }

        let cache = AntigravityTokenCache(tokenFileURLs: [], persistentStoreURL: store)
        let result = await cache.revokeStoredCredential()

        guard case .failed = result else {
            return XCTFail("게이트에 막힌 폐기는 실패로 보고돼야 한다: \(result)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path),
                      "폐기 실패 시 로컬 보관본을 지우면 재시도할 수 없다")
        let summary = await cache.storedCredentialSummary()
        XCTAssertTrue(summary.exists, "여전히 보관 중이라고 보고해야 한다")
    }

    /// 폐기는 나가는 호출이라 다른 라이브 호출과 같은 경계 뒤에 있어야 한다 —
    /// 스위트가 사용자 토큰을 실제로 폐기하면 되돌릴 수 없다.
    func testRevokeIsGatedFromReachingGoogleInTests() async throws {
        let store = try seed(refreshToken: "must-not-be-revoked", obtainedAt: Date())
        defer { cleanup(store) }

        let cache = AntigravityTokenCache(tokenFileURLs: [], persistentStoreURL: store)
        let result = await cache.revokeStoredCredential()
        XCTAssertEqual(result, .failed("live call not permitted"))
    }

    func testRevokeRequestMatchesGoogleRevokeSpec() throws {
        let request = AntigravityTokenCache.makeRevokeRequest(refreshToken: "tok/en+with=chars")
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, AntigravityTokenCache.googleRevokeURL)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertTrue(body.hasPrefix("token="), "revoke endpoint 는 form-encoded token 하나를 받는다")
        XCTAssertFalse(body.contains("tok/en+with=chars"), "토큰은 퍼센트 인코딩돼야 한다")
    }

    /// 서버가 폐기를 확인했을 때만 로컬이 지워진다.
    func testSuccessfulRevokeClearsLocalCredential() async throws {
        let store = try seed(refreshToken: "doomed", obtainedAt: Date())
        defer { cleanup(store) }

        let seen = Attempt()
        let cache = AntigravityTokenCache(
            tokenFileURLs: [], persistentStoreURL: store,
            credentialRevoker: { token in
                seen.value = token
                return .revoked
            })

        let result = await cache.revokeStoredCredential()

        XCTAssertEqual(result, .revoked)
        XCTAssertEqual(seen.value, "doomed", "보관 중인 refresh token 을 폐기해야 한다")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
        let summary = await cache.storedCredentialSummary()
        XCTAssertFalse(summary.exists)
    }

    /// 서버가 거절하면 로컬은 그대로 — 재시도 가능해야 하고, 살아 있는 토큰을 "정리됨" 으로
    /// 표시해서도 안 된다.
    func testServerRejectedRevokeKeepsLocalCredential() async throws {
        let store = try seed(refreshToken: "still-alive", obtainedAt: Date())
        defer { cleanup(store) }

        let cache = AntigravityTokenCache(
            tokenFileURLs: [], persistentStoreURL: store,
            credentialRevoker: { _ in .failed("http 500") })

        let result = await cache.revokeStoredCredential()

        XCTAssertEqual(result, .failed("http 500"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path))
        let summary = await cache.storedCredentialSummary()
        XCTAssertTrue(summary.exists)
    }

    // MARK: helpers

    private final class Attempt: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: String?
        var value: String? {
            get { lock.lock(); defer { lock.unlock() }; return storage }
            set { lock.lock(); storage = newValue; lock.unlock() }
        }
    }


    private func seed(refreshToken: String, obtainedAt: Date?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("antigravity-credential.json")
        let credential = AntigravityOAuthCredential(
            accessToken: "stale", refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(-300), obtainedAt: obtainedAt)
        try JSONEncoder().encode(credential).write(to: url, options: .atomic)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
