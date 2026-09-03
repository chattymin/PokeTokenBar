import Foundation
import Security

/// Antigravity 공식 한도 조회 추상화 — 실 구현 또는 테스트 스텁 주입.
public protocol AntigravityLimitsProviding: Sendable {
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus
}

public struct AntigravityRateLimitsProvider: AntigravityLimitsProviding, Sendable {
    public static let primaryURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!
    public static let dailyURL = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!
    public static let googleTokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    public static let googleClientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"

    private let tokenCache: AntigravityTokenCache

    public init() {
        self.tokenCache = .shared
    }

    init(tokenCache: AntigravityTokenCache) {
        self.tokenCache = tokenCache
    }

    public func fetch(allowKeychainPrompt: Bool = false) async throws -> AntigravityRateLimitStatus {
        let token = try await tokenCache.accessToken(allowKeychainPrompt: allowKeychainPrompt)
        do {
            return try await fetchStatus(accessToken: token)
        } catch let error as LimitsError {
            guard case .httpStatus(let httpStatus) = error, httpStatus == 401 else {
                throw error
            }
            let refreshed = try await tokenCache.accessToken(
                allowKeychainPrompt: allowKeychainPrompt, bypassCache: true)
            guard refreshed != token else {
                await tokenCache.invalidate()
                throw error
            }
            return try await fetchStatus(accessToken: refreshed)
        }
    }

    private func fetchStatus(accessToken: String) async throws -> AntigravityRateLimitStatus {
        // OAuthLimitsProvider.fetchStatus 와 동일 규약 — 네트워크 경계에서만 막는다(자격증명 읽기는 통과).
        guard AppEnv.isBundledApp || AppEnv.isParityRun else { throw LimitsError.liveFetchNotPermitted }
        var endpoints: [URL] = []
        if let envURLString = UsageEnvironment.value("CLOUD_CODE_URL"),
           let envURL = URL(string: envURLString + "/v1internal:retrieveUserQuotaSummary") {
            endpoints.append(envURL)
        }
        endpoints.append(Self.dailyURL)
        endpoints.append(Self.primaryURL)

        var lastError: Error?
        for endpoint in endpoints {
            var request = URLRequest(url: endpoint, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("antigravity/2.9.1", forHTTPHeaderField: "User-Agent")
            request.httpBody = Data("{}".utf8)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        return try JSONDecoder().decode(AntigravityRateLimitStatus.self, from: data)
                    }
                    if http.statusCode == 429 {
                        throw LimitsError.rateLimited(retryAfter: OAuthLimitsProvider.retryAfterSeconds(http))
                    }
                    if http.statusCode == 401 || http.statusCode == 403 {
                        // 이유는 상태코드가 아니라 본문에 있다. 남기지 않으면 원인 추적이 남의 로그
                        // 고고학이 된다 — 실측 403 의 원인(antigravity-cli 는 이 메서드를 아예 호출하지
                        // 않는다)을 알아내는 데 CLI 로그를 뒤져야 했다. 자격증명은 요청 헤더에만 있고
                        // 응답 본문에는 없다. 길이는 잘라서 로그 회전 예산을 지킨다.
                        let reason = String(data: data.prefix(200), encoding: .utf8)?
                            .replacingOccurrences(of: "\n", with: " ")
                            .trimmingCharacters(in: .whitespaces) ?? "<본문 해석 불가>"
                        AppLog.writeIfChanged("antigravity-http-\(http.statusCode)",
                                              "antigravity limits http \(http.statusCode): \(reason)")
                        throw LimitsError.httpStatus(http.statusCode)
                    }
                    lastError = LimitsError.httpStatus(http.statusCode)
                    continue
                }
            } catch let error as LimitsError {
                throw error
            } catch {
                lastError = error
            }
        }
        throw lastError ?? LimitsError.httpStatus(500)
    }
}

/// refresh 시도의 결말. `Credential?` 하나로 뭉뚱그리면 **"자격증명이 죽었다"와 "지금 네트워크가
/// 안 된다"가 같은 처리**를 받는다 — 후자까지 Keychain 프롬프트로 승격돼 일시 장애가 팝업이 된다.
public enum AntigravityRefreshOutcome: Sendable, Equatable {
    case success(AntigravityOAuthCredential)
    /// `invalid_grant` — refresh token 자체가 죽었다. 재시도로 풀리지 않고 Keychain 재취득이 답.
    case credentialRejected
    /// `invalid_client` / secret 누락 — 이 client_secret 이 틀렸다. 다음 후보로 넘어간다.
    case clientRejected
    /// 네트워크·5xx·파싱 실패 — 캐시를 버리지 않고 다음 폴에서 다시 시도한다.
    case transient
}

/// 사용자가 설정에서 "연결 해제" 를 눌렀을 때의 결말.
public enum AntigravityRevokeResult: Sendable, Equatable {
    case revoked
    /// 보관 중인 자격증명이 없다 — 이미 정리된 상태다(오류가 아니다).
    case nothingStored
    /// 서버가 거절했거나 네트워크가 안 됐다. **로컬 파일은 지우지 않는다** — 지워버리면 사용자는
    /// 재시도 수단을 잃고, 서버의 토큰은 살아 있는 채로 "해제됐다"고 오해하게 된다.
    case failed(String)
}

/// 폐기 호출의 주입 지점 — `AntigravityTokenRefresher` 와 같은 이유로 존재한다. 게이트 뒤의
/// 네트워크 코드는 스위트에서 한 줄도 실행되지 않으므로, 주입 없이는 "200 이면 지우고 실패하면
/// 남긴다" 는 계약을 검증할 방법이 없다. (`.nothingStored` 는 호출 전에 판정되므로 반환하지 않는다.)
public typealias AntigravityCredentialRevoker =
    @Sendable (_ refreshToken: String) async -> AntigravityRevokeResult

public typealias AntigravityTokenRefresher =
    @Sendable (_ refreshToken: String, _ clientSecret: String?) async -> AntigravityRefreshOutcome

actor AntigravityTokenCache {
    static let shared = AntigravityTokenCache()
    private var cachedCredential: AntigravityOAuthCredential?
    private let tokenFileURLs: [URL]
    private let persistentStoreURL: URL?
    private let tokenRefresher: AntigravityTokenRefresher
    private let clientSecretSource: @Sendable () -> [String]
    private let credentialRevoker: AntigravityCredentialRevoker

    /// 확정된 client_secret — **메모리에만** 둔다. 평문 자격증명 파일 옆에 같이 저장하면 그 파일
    /// 하나로 갱신 가능한 액세스가 완성돼, secret 을 커밋하지 않기로 한 이유가 그대로 무효가 된다.
    private var resolvedClientSecret: String?
    /// 바이너리 스캔 결과 캐시 — 프로세스당 1회면 충분하다(수십 ms × 설치 바이너리 수).
    private var discoveredCandidates: [String]?

    init(
        tokenFileURLs: [URL]? = nil,
        persistentStoreURL: URL? = nil,
        tokenRefresher: AntigravityTokenRefresher? = nil,
        clientSecretSource: (@Sendable () -> [String])? = nil,
        credentialRevoker: AntigravityCredentialRevoker? = nil
    ) {
        self.credentialRevoker = credentialRevoker ?? { await Self.revokeAtGoogle(refreshToken: $0) }
        self.clientSecretSource = clientSecretSource ?? { AntigravityClientSecret.candidates() }
        self.tokenFileURLs = tokenFileURLs ?? Self.defaultTokenFileURLs
        if let persistentStoreURL {
            self.persistentStoreURL = persistentStoreURL
        } else if tokenFileURLs == nil {
            self.persistentStoreURL = Self.defaultPersistentStoreURL
        } else {
            // 테스트 등에서 tokenFileURLs 를 명시적으로 주입한 경우 실제 앱 상태 디렉토리를 오염시키지 않음
            self.persistentStoreURL = nil
        }
        self.tokenRefresher = tokenRefresher ?? {
            await Self.refreshGoogleToken(refreshToken: $0, clientSecret: $1)
        }
    }

    /// client_secret 후보를 하나씩 대보며 refresh 를 시도한다.
    ///
    /// 후보를 *시도해서* 고르는 이유: 바이너리에는 secret 이 둘 이상 들어 있고(관측: 2개) 어느 쪽이
    /// 우리 client_id 의 짝인지 바이너리만 봐서는 알 수 없다 — 인접 문자열로 추정하는 건 다음 릴리스에
    /// 배치가 바뀌면 조용히 깨진다. Google 이 틀린 짝에 `invalid_client` 로 답하므로 그걸 신호로 쓴다.
    /// 확정된 secret 은 프로세스 수명 동안 재사용하고, 나중에 회전돼 거절되면 다시 훑는다.
    private func refreshCredential(refreshToken: String) async -> AntigravityRefreshOutcome {
        if let secret = resolvedClientSecret {
            let outcome = await tokenRefresher(refreshToken, secret)
            if outcome != .clientRejected { return outcome }
            // secret 회전 — 후보를 다시 훑는다.
            resolvedClientSecret = nil
            discoveredCandidates = nil
        }

        let candidates: [String]
        if let discoveredCandidates {
            candidates = discoveredCandidates
        } else {
            candidates = clientSecretSource()
            discoveredCandidates = candidates
        }
        if candidates.isEmpty {
            AppLog.writeIfChanged(
                "antigravity-client-secret",
                "antigravity client secret not found — is Antigravity installed?")
            return .clientRejected
        }

        var sawTransient = false
        for secret in candidates {
            switch await tokenRefresher(refreshToken, secret) {
            case .success(let credential):
                resolvedClientSecret = secret
                return .success(credential)
            case .credentialRejected:
                // secret 은 맞았고 자격증명이 죽었다 — 남은 후보를 대볼 이유가 없다.
                return .credentialRejected
            case .clientRejected:
                continue
            case .transient:
                sawTransient = true
            }
        }
        return sawTransient ? .transient : .clientRejected
    }

    /// refresh 결과를 캐시·영속저장소에 반영하고 액세스 토큰을 돌려준다.
    private func applyRefresh(_ outcome: AntigravityRefreshOutcome) -> String? {
        guard case .success(let credential) = outcome else { return nil }
        return adopt(credential).accessToken
    }

    /// 자격증명을 캐시·영속저장소에 들인다 — **저장은 전부 여기를 지난다.**
    ///
    /// `obtainedAt` 승계가 여기 있는 이유: 액세스 토큰 갱신은 새 grant 가 아니라 같은 refresh token 의
    /// 연장이다. 갱신마다 도장을 새로 찍으면 설정 화면의 "보관 기간" 이 매시간 0 으로 리셋돼,
    /// 정확히 그 숫자를 보고 판단하려던 사용자에게 거짓말을 한다. refresh token 이 **바뀔 때만**
    /// 새로 찍는다(재로그인·계정 전환).
    @discardableResult
    private func adopt(_ credential: AntigravityOAuthCredential) -> AntigravityOAuthCredential {
        let previous = cachedCredential ?? loadPersistedCredential()
        let carriedOver: Date?
        if let previous, previous.refreshToken != nil,
           previous.refreshToken == credential.refreshToken {
            // nil 은 nil 로 둔다 — 이 필드가 생기기 전부터 있던 자격증명의 진짜 나이는 **모른다.**
            // 여기서 오늘 날짜를 찍으면 몇 달 된 토큰이 "0일째" 로 보여, 폐기를 미루게 만드는
            // 방향으로 틀린다. 모르는 건 모른다고 표시하고, 첫 재로그인 때 정확해진다.
            carriedOver = previous.obtainedAt
        } else {
            carriedOver = Date()
        }
        let stamped = credential.stamped(obtainedAt: carriedOver)
        cachedCredential = stamped
        persistCredential(stamped)
        return stamped
    }

    /// 설정 화면용 요약 — 토큰 값은 절대 내보내지 않는다.
    func storedCredentialSummary() -> AntigravityCredentialSummary {
        let credential = cachedCredential ?? loadPersistedCredential()
        guard let credential else { return AntigravityCredentialSummary(exists: false, obtainedAt: nil) }
        return AntigravityCredentialSummary(
            exists: credential.refreshToken != nil, obtainedAt: credential.obtainedAt)
    }

    /// Google 에서 refresh token 을 폐기하고 로컬 보관본을 지운다.
    ///
    /// 이 토큰은 **우리 것이 아니다** — Antigravity 가 Keychain 에 보관한 것을 읽어 쓴다. 그래서
    /// 폐기하면 Antigravity 자신의 로그인도 함께 끊긴다. UI 는 그 사실을 반드시 먼저 알린다.
    func revokeStoredCredential() async -> AntigravityRevokeResult {
        if cachedCredential == nil { cachedCredential = loadPersistedCredential() }
        guard let refreshToken = cachedCredential?.refreshToken else {
            invalidate()
            return .nothingStored
        }
        let result = await credentialRevoker(refreshToken)
        // **성공했을 때만** 로컬을 지운다. 순서가 반대면(먼저 지우고 호출) 실패 시 사용자는
        // 재시도 수단을 잃고, 서버의 토큰은 살아 있는 채로 "정리됐다" 고 오해하게 된다.
        if result == .revoked {
            invalidate()
            AppLog.write("antigravity credential revoked and removed locally")
        }
        return result
    }

    static let googleRevokeURL = URL(string: "https://oauth2.googleapis.com/revoke")!

    /// 폐기 요청 조립 — 갱신 요청과 같은 이유로 순수 함수다(게이트 뒤 코드는 스위트가 실행하지 않는다).
    /// Google 의 revoke endpoint 는 form-encoded `token` 하나만 받는다.
    static func makeRevokeRequest(refreshToken: String) -> URLRequest {
        var request = URLRequest(url: googleRevokeURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("token=\(FormURLEncoding.value(refreshToken))".utf8)
        return request
    }

    static func revokeAtGoogle(refreshToken: String) async -> AntigravityRevokeResult {
        // 다른 나가는 호출과 같은 경계 — 스위트가 사용자 토큰을 실제로 폐기하면 되돌릴 수 없다.
        guard AppEnv.isBundledApp || AppEnv.isParityRun else {
            return .failed("live call not permitted")
        }
        guard let (_, response) = try? await URLSession.shared.data(
                for: makeRevokeRequest(refreshToken: refreshToken)),
              let http = response as? HTTPURLResponse else {
            return .failed("network")
        }
        guard http.statusCode == 200 else {
            AppLog.write("antigravity credential revoke rejected: http \(http.statusCode)")
            return .failed("http \(http.statusCode)")
        }
        return .revoked
    }

    static var defaultTokenFileURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".gemini/jetski-standalone-oauth-token"),
            home.appendingPathComponent(".gemini/antigravity/jetski-standalone-oauth-token"),
        ]
    }

    static var defaultPersistentStoreURL: URL {
        AppStatePaths.directory().appendingPathComponent("antigravity-credential.json")
    }

    func accessToken(allowKeychainPrompt: Bool, bypassCache: Bool = false) async throws -> String {
        // 1. 파일 크리덴셜(~/.gemini/jetski-standalone-oauth-token) — 키체인 무관, 프롬프트 없음.
        //    파일로 답할 수 있으면 여기서 끝낸다. 캐시 히트보다 앞: 파일 로드는 expiresAt=nil 이라
        //    캐시가 만료로 풀리지 않고, 계정 전환으로 파일이 바뀌어도 옛 토큰을 계속 쓰는 결함을 방지(#227).
        if let fileCred = Self.readTokenFile(urls: tokenFileURLs) {
            if cachedCredential?.accessToken != fileCred.accessToken {
                adopt(fileCred)
            }
            if !bypassCache && !fileCred.isExpired {
                return fileCred.accessToken
            }
            if let refreshToken = fileCred.refreshToken,
               let token = applyRefresh(await refreshCredential(refreshToken: refreshToken)) {
                return token
            }
            if !fileCred.isExpired {
                return fileCred.accessToken
            }
        }

        // 2. 자동(타이머) 경로: Keychain 을 일절 읽지 않고 캐시/영속저장소/refreshToken 으로만 답한다.
        guard allowKeychainPrompt else {
            if cachedCredential == nil {
                cachedCredential = loadPersistedCredential()
            }

            if !bypassCache, let cachedCredential, !cachedCredential.isExpired {
                return cachedCredential.accessToken
            }

            // 토큰이 만료되었거나 bypassCache 요청 시: refreshToken이 있으면 네트워크(HTTPS)로 갱신.
            // Google OAuth refresh_token은 키체인을 전혀 건드리지 않고 HTTPS 호출만 수행하므로
            // 자동 폴링(allowKeychainPrompt=false)에서도 100% 안전하게 동작한다.
            // Google refresh token은 회전하지 않고 장기간 유효하므로(defect-log §자격증명),
            // 이 경로를 통해 사용자가 매시간 또는 앱 재시작마다 수동 갱신할 필요 없이 자격증명이 영속된다.
            if let cachedCredential, let refreshToken = cachedCredential.refreshToken {
                let outcome = await refreshCredential(refreshToken: refreshToken)
                if let token = applyRefresh(outcome) { return token }
                // 일시 실패는 캐시를 지우지 않는다 — 다음 폴이 같은 refresh token 으로 다시 시도한다.
                // (죽은 자격증명과 같은 취급을 하면 네트워크 블립이 Keychain 프롬프트로 승격된다.)
                AppLog.writeIfChanged(
                    "antigravity-refresh", "antigravity token refresh failed: \(outcome)")
            }

            throw LimitsError.keychainInteractionNotAllowed
        }

        // 3. 사용자 동작 경로(allowKeychainPrompt=true) — 프롬프트를 내는 읽기는 **마지막 수단**이다.
        //
        //   3a. 무프롬프트 Keychain 읽기. 성공하면 이게 가장 정확하다 — Antigravity CLI 가 계정을
        //       바꾸면 항목이 새 계정으로 덮이므로, 여기서 읽어야 계정 전환이 반영된다(#227 부류).
        //   3b. 실패하면 보관 중인 refresh token 으로 갱신. 유효한 refresh token 이 디스크에 있는데도
        //       곧장 프롬프트를 띄우면, 프롬프트를 없애려고 만든 갱신 버튼이 매 탭마다 프롬프트를 낸다.
        //   3c. 그것도 안 되면 그때 프롬프트를 동반해 읽는다.
        if let cred = Self.readKeychainSilently() {
            return try await resolveValidToken(from: cred)
        }
        if cachedCredential == nil { cachedCredential = loadPersistedCredential() }
        if let refreshToken = cachedCredential?.refreshToken,
           let token = applyRefresh(await refreshCredential(refreshToken: refreshToken)) {
            return token
        }
        let cred = try Self.readKeychain(allowKeychainPrompt: true)
        return try await resolveValidToken(from: cred)
    }

    private func resolveValidToken(from cred: AntigravityOAuthCredential) async throws -> String {
        if !cred.isExpired {
            return adopt(cred).accessToken
        }
        // 만료되었고 refresh_token이 있다면 갱신 시도
        if let refreshToken = cred.refreshToken,
           let token = applyRefresh(await refreshCredential(refreshToken: refreshToken)) {
            return token
        }
        // 갱신 실패했더라도 기존 accessToken 저장 및 반환 (API에서 401 나면 다시 처리)
        return adopt(cred).accessToken
    }

    func invalidate() {
        cachedCredential = nil
        clearPersistedCredential()
    }

    private func persistCredential(_ credential: AntigravityOAuthCredential) {
        guard let url = persistentStoreURL else { return }
        do {
            let data = try JSONEncoder().encode(credential)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: url)
            FileManager.default.createFile(
                atPath: url.path, contents: nil,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o600))])
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: url.path)
            CredentialFileProtection.excludeFromBackup(url)
        } catch {
            AppLog.write("failed to persist antigravity credential: \(error)")
        }
    }

    private func loadPersistedCredential() -> AntigravityOAuthCredential? {
        guard let url = persistentStoreURL,
              let data = try? Data(contentsOf: url),
              let credential = try? JSONDecoder().decode(AntigravityOAuthCredential.self, from: data),
              !credential.accessToken.isEmpty
        else { return nil }
        return credential
    }

    private func clearPersistedCredential() {
        guard let url = persistentStoreURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 갱신 요청 조립 — **순수 함수로 떼어 둔다.**
    ///
    /// #44 의 갱신은 단 한 번도 성공하지 못했는데도 스위트는 초록이었다. 테스트가 `tokenRefresher`
    /// 스텁을 주입해 *성공을 흉내냈고*, 프로덕션이 실제로 보내는 요청 바디는 아무도 보지 않았기
    /// 때문이다(빠져 있던 건 `client_secret` 하나였다). 바디를 검사 가능한 지점으로 꺼내 둬야
    /// "갱신이 된다"가 아니라 "우리가 보내는 요청이 Google 규격에 맞다"를 검증할 수 있다.
    static func makeRefreshRequest(refreshToken: String, clientSecret: String) -> URLRequest {
        var request = URLRequest(url: AntigravityRateLimitsProvider.googleTokenURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "client_id": AntigravityRateLimitsProvider.googleClientID,
            "client_secret": clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        let bodyString = params.map { "\($0.key)=\(FormURLEncoding.value($0.value))" }
            .joined(separator: "&")
        request.httpBody = Data(bodyString.utf8)
        return request
    }

    static func refreshGoogleToken(
        refreshToken: String,
        clientSecret: String?
    ) async -> AntigravityRefreshOutcome {
        // secret 없이 보내면 Google 이 항상 400 이다 — 네트워크를 칠 이유가 없으므로 게이트보다 앞에 둔다.
        guard let clientSecret, !clientSecret.isEmpty else { return .clientRejected }
        // fetchStatus 와 별개의 네트워크 경계다 — 여기를 빼면 스위트가 사용자 refresh_token 을 실제로
        // 소비해 새 토큰을 발급받는다(조회보다 부작용이 크다).
        guard AppEnv.isBundledApp || AppEnv.isParityRun else { return .transient }

        let request = makeRefreshRequest(refreshToken: refreshToken, clientSecret: clientSecret)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return .transient   // 네트워크 도달 실패 — 자격증명 판정 근거가 없다.
        }

        if http.statusCode == 200 {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = json["access_token"] as? String, !newAccessToken.isEmpty else {
                return .transient
            }
            let expiresIn = json["expires_in"] as? Double ?? 3600
            // Google 은 이 그랜트에 새 refresh_token 을 주지 않는다(회전 없음) — 기존 것을 그대로 잇는다.
            return .success(AntigravityOAuthCredential(
                accessToken: newAccessToken,
                refreshToken: refreshToken,
                expiresAt: Date().addingTimeInterval(expiresIn)))
        }

        // 4xx 는 본문의 `error` 코드가 처방을 가른다. **본문의 error 코드만** 남긴다 —
        // 요청 바디에는 refresh token 과 client_secret 이 둘 다 들어 있으므로 절대 로그로 내보내지 않는다.
        let errorCode = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { $0?["error"] as? String } ?? "unknown"
        if http.statusCode >= 500 { return .transient }
        AppLog.writeIfChanged(
            "antigravity-token-\(http.statusCode)",
            "antigravity token refresh rejected: http \(http.statusCode) \(errorCode)")
        switch errorCode {
        case "invalid_grant":
            return .credentialRejected
        case "invalid_client", "invalid_request", "unauthorized_client":
            return .clientRejected
        default:
            return http.statusCode == 400 || http.statusCode == 401 ? .clientRejected : .transient
        }
    }

    private nonisolated static func readTokenFile(urls: [URL]) -> AntigravityOAuthCredential? {
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let cred = parseCredential(data: data) {
                return cred
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["token"] as? String, !token.isEmpty else {
                continue
            }
            return AntigravityOAuthCredential(accessToken: token, refreshToken: nil, expiresAt: nil)
        }
        return nil
    }

    private nonisolated static func readKeychainSilently() -> AntigravityOAuthCredential? {
        do {
            return try readKeychain(allowKeychainPrompt: false)
        } catch {
            return nil
        }
    }

    private nonisolated static func readKeychain(
        allowKeychainPrompt: Bool
    ) throws -> AntigravityOAuthCredential {
        if KeychainAccessGate.isDisabled {
            throw LimitsError.keychainAccessDisabled
        }
        let services = ["gemini", "antigravity"]
        var lastStatus: OSStatus = errSecItemNotFound

        for service in services {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "antigravity",
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            if !allowKeychainPrompt {
                KeychainNoUIQuery.apply(to: &query)
            }

            var item: CFTypeRef?
            let status = KeychainReader.copyMatching(query, &item)
            if status == errSecInteractionNotAllowed {
                throw LimitsError.keychainInteractionNotAllowed
            }
            lastStatus = status
            if status == errSecSuccess, let data = item as? Data,
               let credential = parseCredential(data: data) {
                return credential
            }
        }
        throw LimitsError.keychainUnavailable(lastStatus)
    }

    private nonisolated static func parseCredential(data: Data) -> AntigravityOAuthCredential? {
        guard let rawString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        let jsonData: Data
        if rawString.hasPrefix("go-keyring-base64:") {
            let base64Part = String(rawString.dropFirst("go-keyring-base64:".count))
            guard let decoded = Data(base64Encoded: base64Part) else { return nil }
            jsonData = decoded
        } else {
            jsonData = data
        }

        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        if let tokenObj = json["token"] as? [String: Any],
           let accessToken = tokenObj["access_token"] as? String, !accessToken.isEmpty {
            let refreshToken = tokenObj["refresh_token"] as? String
            let expiresAt: Date?
            if let expiryStr = tokenObj["expiry"] as? String {
                expiresAt = ISO8601Parser.date(from: expiryStr)
            } else if let expiresAtNum = tokenObj["expires_at"] as? TimeInterval {
                expiresAt = Date(timeIntervalSince1970: expiresAtNum)
            } else if let expiresIn = tokenObj["expires_in"] as? TimeInterval {
                expiresAt = Date().addingTimeInterval(expiresIn)
            } else {
                expiresAt = nil
            }
            return AntigravityOAuthCredential(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt)
        }

        if let accessToken = json["access_token"] as? String, !accessToken.isEmpty {
            let refreshToken = json["refresh_token"] as? String
            let expiresAt: Date?
            if let expiryStr = json["expiry"] as? String {
                expiresAt = ISO8601Parser.date(from: expiryStr)
            } else if let expiresAtNum = json["expires_at"] as? TimeInterval {
                expiresAt = Date(timeIntervalSince1970: expiresAtNum)
            } else if let expiresIn = json["expires_in"] as? TimeInterval {
                expiresAt = Date().addingTimeInterval(expiresIn)
            } else {
                expiresAt = nil
            }
            return AntigravityOAuthCredential(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt)
        }

        if let directToken = json["token"] as? String, !directToken.isEmpty {
            return AntigravityOAuthCredential(
                accessToken: directToken,
                refreshToken: nil,
                expiresAt: nil)
        }

        return nil
    }
}

public struct AntigravityOAuthCredential: Sendable, Codable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    /// 이 **refresh token** 을 언제부터 보관 중인가. 액세스 토큰 갱신은 새 grant 가 아니므로
    /// 갱신을 건너뛰고 유지된다 — 설정 화면이 "얼마나 오래된 자격증명인가"를 보여주는 근거다.
    /// Optional 이라 이 필드가 없던 기존 파일도 그대로 디코드된다(마이그레이션 불필요).
    public let obtainedAt: Date?

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date().addingTimeInterval(60)
    }

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        obtainedAt: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.obtainedAt = obtainedAt
    }

    func stamped(obtainedAt: Date?) -> AntigravityOAuthCredential {
        AntigravityOAuthCredential(
            accessToken: accessToken, refreshToken: refreshToken,
            expiresAt: expiresAt, obtainedAt: obtainedAt)
    }
}


/// `application/x-www-form-urlencoded` 값 인코딩.
///
/// `.urlQueryAllowed` 를 쓰면 안 된다 — 그 집합은 `+`·`=`·`&`·`/` 를 **통과시킨다.** 쿼리 문자열
/// 안에서는 합법이지만 form 바디에서는 `+` 가 공백으로 디코드되고 `=`·`&` 는 구분자다. 즉 그런
/// 문자가 든 토큰은 조용히 다른 값으로 전달된다. 지금 Google 의 refresh token·client_secret 은
/// base64url 계열이라 실제로 깨지진 않지만, 값의 문자 집합에 기대는 인코딩은 계약이 아니라 우연이다.
/// unreserved(RFC 3986) 만 남기고 전부 이스케이프한다.
enum FormURLEncoding {
    private static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func value(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: unreserved) ?? raw
    }
}

/// 설정 화면이 보여줄 최소 정보 — 토큰 값은 담지 않는다.
public struct AntigravityCredentialSummary: Sendable, Equatable {
    public let exists: Bool
    public let obtainedAt: Date?
}
