import XCTest
@testable import PokeTokenBar

/// #44 가 넣은 자동 갱신이 **한 번도 성공한 적 없이** 스위트를 초록으로 통과한 부류를 막는다.
/// 그 테스트는 `tokenRefresher` 스텁이 성공을 흉내내서, 프로덕션이 실제로 보내는 요청 바디
/// (`client_secret` 누락 → Google 400)를 아무도 보지 않았다.
final class AntigravityTokenRefreshTests: XCTestCase {

    // MARK: 요청 규격 — 결함이 있던 바로 그 지점

    func testRefreshRequestCarriesClientSecret() throws {
        let request = AntigravityTokenCache.makeRefreshRequest(
            refreshToken: "refresh-abc", clientSecret: "GOCSPX-secret")
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        let fields = Dictionary(uniqueKeysWithValues: body.split(separator: "&").map { pair -> (String, String) in
            let parts = pair.split(separator: "=", maxSplits: 1)
            return (String(parts[0]), parts.count > 1 ? String(parts[1]) : "")
        })

        // Google 의 refresh_token 그랜트는 이 클라이언트에서 confidential 이다 —
        // client_secret 이 없으면 400 `client_secret is missing.` 이 확정이다.
        XCTAssertEqual(fields["client_secret"], "GOCSPX-secret")
        XCTAssertEqual(fields["grant_type"], "refresh_token")
        XCTAssertEqual(fields["refresh_token"], "refresh-abc")
        XCTAssertEqual(fields["client_id"], AntigravityRateLimitsProvider.googleClientID)
        XCTAssertEqual(request.httpMethod, "POST")
    }

    /// form 바디의 값은 unreserved 만 남기고 전부 이스케이프해야 한다. `.urlQueryAllowed` 는
    /// `+`·`=`·`&`·`/` 를 통과시켜 — `+` 는 공백으로 디코드되고 `=`·`&` 는 구분자라 — 그런 문자가
    /// 든 토큰이 조용히 다른 값으로 전달된다.
    func testRefreshBodyEscapesFormDelimiters() throws {
        let request = AntigravityTokenCache.makeRefreshRequest(
            refreshToken: "a+b=c&d/e", clientSecret: "s+x")
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })

        XCTAssertTrue(body.contains("refresh_token=a%2Bb%3Dc%26d%2Fe"), "구분자가 그대로 새면 안 된다: \(body)")
        XCTAssertTrue(body.contains("client_secret=s%2Bx"))
        // 필드가 4개면 & 는 정확히 3개 — 값 안의 & 가 필드를 쪼개지 않았다는 뜻이다.
        XCTAssertEqual(body.filter { $0 == "&" }.count, 3)
    }

    func testRefreshWithoutDiscoveredSecretSkipsTheNetwork() async {
        // 후보를 못 찾았으면 보내봐야 400 이다 — 네트워크를 치지 않고 즉시 clientRejected.
        let outcome = await AntigravityTokenCache.refreshGoogleToken(
            refreshToken: "refresh-abc", clientSecret: nil)
        XCTAssertEqual(outcome, .clientRejected)
    }

    // MARK: client_secret 후보 추출

    /// 실측 바이너리에서 secret 두 개는 **구분자 없이 맞닿아** 있다. 탐욕적 매칭이면 둘이 한 덩어리로
    /// 붙고 뒤따르는 문자열까지 삼킨다 — 이 픽스처가 그 배치를 그대로 재현한다.
    func testExtractsBothAdjacentSecrets() {
        let blob = "https://auth.cloud.google/authorize"
            + "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"
            + "GOCSPX-zzzz-yyyy_xxxx-wwww_vvvv9876"
            + "https://cloudcode-pa.googleapis.com"
        let found = AntigravityClientSecret.candidates(in: Data(blob.utf8))

        XCTAssertEqual(found, [
            "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",
            "GOCSPX-zzzz-yyyy_xxxx-wwww_vvvv9876",
        ], "맞닿은 두 secret 을 각각 28자로 끊어내야 한다")
    }

    func testIgnoresTruncatedSecretAtEndOfData() {
        // 잘린 접두사에 뒤 바이트를 끌어다 붙이면 안 된다(경계 넘어 읽기).
        let found = AntigravityClientSecret.candidates(in: Data("padding GOCSPX-tooshort".utf8))
        XCTAssertTrue(found.isEmpty)
    }

    func testRejectsNonSecretCharactersInBody() {
        // 본문 28자 안에 base64url 밖 문자가 섞이면 secret 이 아니다.
        let blob = "GOCSPX-AAAAAAAAAA!BBBBBBBBBBBBBBBB"
        XCTAssertTrue(AntigravityClientSecret.candidates(in: Data(blob.utf8)).isEmpty)
    }

    /// IDE 와 CLI 는 같은 secret 을 각자 품는다 — 같은 값을 두 번 대보면 Google 요청만 낭비된다.
    /// 실제 설치 경로에 의존하면 Antigravity 유무에 따라 결과가 갈리므로 바이너리 목록을 주입한다.
    func testDeduplicatesAcrossBinaries() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let shared = "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"
        let cliOnly = "GOCSPX-zzzz-yyyy_xxxx-wwww_vvvv9876"
        let ide = dir.appendingPathComponent("language_server")
        let cli = dir.appendingPathComponent("agy")
        try Data("junk\(shared)junk".utf8).write(to: ide)
        try Data("junk\(shared)\(cliOnly)junk".utf8).write(to: cli)

        let found = AntigravityClientSecret.candidates(binaryURLs: [ide, cli])
        XCTAssertEqual(found, [shared, cliOnly], "중복은 접고 발견 순서는 유지한다")
    }

    func testMissingBinariesYieldNoCandidates() {
        let absent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        XCTAssertTrue(AntigravityClientSecret.candidates(binaryURLs: [absent]).isEmpty)
    }

    // MARK: 후보 선택 — 틀린 secret 은 건너뛰고 맞는 것을 기억한다

    func testPicksTheSecretGoogleAccepts() async throws {
        let store = try seedCredential(expired: true)
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }

        let attempts = Attempts()
        let cache = AntigravityTokenCache(
            tokenFileURLs: [],
            persistentStoreURL: store,
            tokenRefresher: { token, secret in
                attempts.record(secret)
                // 첫 후보는 우리 client_id 의 짝이 아니다 — Google 은 invalid_client 로 답한다.
                guard secret == "GOCSPX-right" else { return .clientRejected }
                return .success(AntigravityOAuthCredential(
                    accessToken: "minted", refreshToken: token,
                    expiresAt: Date().addingTimeInterval(3600)))
            },
            clientSecretSource: { ["GOCSPX-wrong", "GOCSPX-right"] })

        KeychainReader.resetQueryCountForTesting()
        let token = try await cache.accessToken(allowKeychainPrompt: false)

        XCTAssertEqual(token, "minted")
        XCTAssertEqual(attempts.secrets, ["GOCSPX-wrong", "GOCSPX-right"])
        XCTAssertEqual(KeychainReader.queryCount, 0, "자동 경로는 Keychain 을 읽지 않는다")
    }

    func testResolvedSecretIsReusedWithoutRescanning() async throws {
        let store = try seedCredential(expired: true)
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }

        let attempts = Attempts()
        let scans = Attempts()
        let cache = AntigravityTokenCache(
            tokenFileURLs: [],
            persistentStoreURL: store,
            tokenRefresher: { token, secret in
                attempts.record(secret)
                guard secret == "GOCSPX-right" else { return .clientRejected }
                // 두 번째 호출도 갱신을 타도록 만료된 토큰을 돌려준다.
                return .success(AntigravityOAuthCredential(
                    accessToken: "minted", refreshToken: token,
                    expiresAt: Date().addingTimeInterval(-30)))
            },
            clientSecretSource: {
                scans.record("scan")
                return ["GOCSPX-wrong", "GOCSPX-right"]
            })

        _ = try? await cache.accessToken(allowKeychainPrompt: false)
        _ = try? await cache.accessToken(allowKeychainPrompt: false)

        XCTAssertEqual(scans.secrets.count, 1, "바이너리 스캔은 프로세스당 1회")
        XCTAssertEqual(attempts.secrets.filter { $0 == "GOCSPX-wrong" }.count, 1,
                       "확정된 뒤에는 틀린 후보를 다시 대보지 않는다")
    }

    /// 확정해 둔 secret 이 나중에 거절되면(Google 회전·Antigravity 신규 릴리스) 다시 훑어야 한다 —
    /// 안 그러면 죽은 secret 을 프로세스가 끝날 때까지 붙들고 매 폴을 실패시킨다.
    func testRotatedSecretIsRediscovered() async throws {
        let store = try seedCredential(expired: true)
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }

        let accepted = Locked("GOCSPX-first")
        let scans = Attempts()
        let cache = AntigravityTokenCache(
            tokenFileURLs: [],
            persistentStoreURL: store,
            tokenRefresher: { token, secret in
                guard secret == accepted.value else { return .clientRejected }
                return .success(AntigravityOAuthCredential(
                    accessToken: "minted-\(secret ?? "")", refreshToken: token,
                    expiresAt: Date().addingTimeInterval(-30)))
            },
            clientSecretSource: {
                scans.record("scan")
                return [accepted.value]
            })

        let first = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(first, "minted-GOCSPX-first")

        // Google 이 secret 을 회전시켰다 — 확정본은 이제 invalid_client 다.
        accepted.value = "GOCSPX-rotated"
        let second = try await cache.accessToken(allowKeychainPrompt: false)

        XCTAssertEqual(second, "minted-GOCSPX-rotated", "거절된 secret 을 붙들면 안 된다")
        XCTAssertEqual(scans.secrets.count, 2, "거절 후에는 바이너리를 다시 훑는다")
    }

    /// Antigravity 미설치(또는 설치 경로 변경) — 후보가 없으면 네트워크를 치지 않고 조용히 끝난다.
    func testNoCandidatesFailsWithoutTouchingNetworkOrKeychain() async throws {
        let store = try seedCredential(expired: true)
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }

        let attempts = Attempts()
        let cache = AntigravityTokenCache(
            tokenFileURLs: [],
            persistentStoreURL: store,
            tokenRefresher: { _, secret in
                attempts.record(secret)
                return .transient
            },
            clientSecretSource: { [] })

        KeychainReader.resetQueryCountForTesting()
        do {
            _ = try await cache.accessToken(allowKeychainPrompt: false)
            XCTFail("후보가 없으면 토큰을 내줄 수 없다")
        } catch LimitsError.keychainInteractionNotAllowed {
            // 기대한 경로
        }
        XCTAssertTrue(attempts.secrets.isEmpty, "후보가 없는데 Google 을 부르면 안 된다")
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    /// 후보를 전부 대봤는데 모두 invalid_client — 일시 실패가 아니므로 transient 로 접으면 안 된다.
    /// 그리고 **실패가 이어져도 바이너리를 다시 훑지 않는다** — 갱신이 계속 실패하는 동안 5분마다
    /// 300MB 를 재스캔하면 실패 상태가 그대로 상시 부하가 된다.
    func testAllCandidatesRejectedStopsRescanningBinaries() async throws {
        let store = try seedCredential(expired: true)
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }

        let attempts = Attempts()
        let scans = Attempts()
        let cache = AntigravityTokenCache(
            tokenFileURLs: [],
            persistentStoreURL: store,
            tokenRefresher: { _, secret in
                attempts.record(secret)
                return .clientRejected
            },
            clientSecretSource: {
                scans.record("scan")
                return ["GOCSPX-a", "GOCSPX-b"]
            })

        _ = try? await cache.accessToken(allowKeychainPrompt: false)
        _ = try? await cache.accessToken(allowKeychainPrompt: false)

        XCTAssertEqual(attempts.secrets, ["GOCSPX-a", "GOCSPX-b", "GOCSPX-a", "GOCSPX-b"],
                       "매 폴마다 후보를 끝까지 대본다")
        XCTAssertEqual(scans.secrets.count, 1, "스캔 결과는 재사용한다")
    }

    // MARK: 일시 실패가 Keychain 프롬프트로 승격되지 않는다

    func testTransientFailureKeepsCredentialForNextPoll() async throws {
        let store = try seedCredential(expired: true)
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }

        let cache = AntigravityTokenCache(
            tokenFileURLs: [],
            persistentStoreURL: store,
            tokenRefresher: { _, _ in .transient },
            clientSecretSource: { ["GOCSPX-any"] })

        KeychainReader.resetQueryCountForTesting()
        do {
            _ = try await cache.accessToken(allowKeychainPrompt: false)
            XCTFail("갱신 실패 시 자동 경로는 토큰을 내주지 않는다")
        } catch LimitsError.keychainInteractionNotAllowed {
            // 기대한 경로
        }

        XCTAssertEqual(KeychainReader.queryCount, 0, "네트워크 블립이 Keychain 조회로 승격되면 안 된다")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path),
                      "일시 실패로 자격증명을 버리면 다음 폴이 복구할 수단을 잃는다")
    }

    func testDeadCredentialStopsAfterFirstCandidate() async throws {
        let store = try seedCredential(expired: true)
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }

        let attempts = Attempts()
        let cache = AntigravityTokenCache(
            tokenFileURLs: [],
            persistentStoreURL: store,
            tokenRefresher: { _, secret in
                attempts.record(secret)
                return .credentialRejected
            },
            clientSecretSource: { ["GOCSPX-a", "GOCSPX-b"] })

        _ = try? await cache.accessToken(allowKeychainPrompt: false)

        XCTAssertEqual(attempts.secrets, ["GOCSPX-a"],
                       "invalid_grant 은 secret 이 맞다는 뜻 — 남은 후보를 대볼 이유가 없다")
    }

    // MARK: 사용자 탭이 곧바로 프롬프트로 가지 않는다

    /// 유효한 refresh token 이 디스크에 있는데도 갱신 버튼이 Keychain 을 먼저 열면, 팝업을 없애려고
    /// 만든 버튼이 매 탭마다 팝업을 낸다. Keychain 게이트를 닫아 두면 프롬프트 경로가 결정적으로
    /// `keychainAccessDisabled` 를 던지므로, 토큰이 돌아온다는 것 자체가 "갱신이 먼저 시도됐다"의 증거다.
    func testUserTapRefreshesBeforeReachingTheKeychain() async throws {
        let saved = KeychainAccessGate.isDisabled
        KeychainAccessGate.isDisabled = true
        defer { KeychainAccessGate.isDisabled = saved }

        let store = try seedCredential(expired: true)
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }

        let cache = AntigravityTokenCache(
            tokenFileURLs: [],
            persistentStoreURL: store,
            tokenRefresher: { token, _ in
                .success(AntigravityOAuthCredential(
                    accessToken: "refreshed-without-prompt", refreshToken: token,
                    expiresAt: Date().addingTimeInterval(3600)))
            },
            clientSecretSource: { ["GOCSPX-right"] })

        KeychainReader.resetQueryCountForTesting()
        let token = try await cache.accessToken(allowKeychainPrompt: true)

        XCTAssertEqual(token, "refreshed-without-prompt")
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    // MARK: helpers

    private func seedCredential(expired: Bool) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("antigravity-credential.json")
        let credential = AntigravityOAuthCredential(
            accessToken: "stale-access-token",
            refreshToken: "long-lived-refresh-token",
            expiresAt: Date().addingTimeInterval(expired ? -300 : 3600))
        try JSONEncoder().encode(credential).write(to: url, options: .atomic)
        return url
    }

    private final class Locked: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: String
        init(_ value: String) { storage = value }
        var value: String {
            get { lock.lock(); defer { lock.unlock() }; return storage }
            set { lock.lock(); storage = newValue; lock.unlock() }
        }
    }

    private final class Attempts: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        var secrets: [String] {
            lock.lock(); defer { lock.unlock() }
            return storage
        }
        func record(_ value: String?) {
            lock.lock(); defer { lock.unlock() }
            storage.append(value ?? "<nil>")
        }
    }
}
