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

    private let tokenCache = AntigravityTokenCache.shared

    public init() {}

    public func fetch(allowKeychainPrompt: Bool = false) async throws -> AntigravityRateLimitStatus {
        let token = try await tokenCache.accessToken(allowKeychainPrompt: allowKeychainPrompt)
        do {
            return try await fetchStatus(accessToken: token)
        } catch let error as LimitsError {
            guard case .httpStatus(let httpStatus) = error, httpStatus == 401 || httpStatus == 403 else {
                throw error
            }
            await tokenCache.invalidate()
            let refreshed = try await tokenCache.accessToken(
                allowKeychainPrompt: allowKeychainPrompt, bypassCache: true)
            guard refreshed != token else { throw error }
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

private actor AntigravityTokenCache {
    static let shared = AntigravityTokenCache()
    private var cachedCredential: AntigravityOAuthCredential?

    func accessToken(allowKeychainPrompt: Bool, bypassCache: Bool = false) async throws -> String {
        if !bypassCache, let cachedCredential, !cachedCredential.isExpired {
            return cachedCredential.accessToken
        }

        // 1. 파일 크리덴셜(~/.gemini/jetski-standalone-oauth-token) — 키체인 무관, 프롬프트 없음.
        //    파일로 답할 수 있으면 여기서 끝낸다. 이 return 이 없으면 유효한 파일 토큰이 있어도
        //    매 호출이 키체인까지 내려간다(프롬프트를 피할 수 있는 경로를 두고 쓰지 않는 셈).
        if let fileToken = Self.readTokenFile() {
            if cachedCredential?.accessToken != fileToken {
                cachedCredential = AntigravityOAuthCredential(
                    accessToken: fileToken, refreshToken: nil, expiresAt: nil)
            }
            return fileToken
        }

        // 2. 자동(타이머) 경로는 Keychain 을 일절 읽지 않는다. no-UI 쿼리(kSecUseAuthenticationUIFail
        //    /LAContext)로도 잠긴·미승인 login 키체인의 '암호 입력' 다이얼로그는 억제되지 않는다 —
        //    OAuthLimitsProvider 가 같은 이유로 자동 경로에서 키체인을 열지 않는다(실측: 캐시 만료 폴
        //    도중 SecItemCopyMatching 이 13초간 블록하며 팝업). 캐시가 살아있으면 그 토큰으로 계속
        //    갱신하고, 없으면 한도를 stale 로 두고 사용자가 갱신을 누를 때 재취득한다.
        guard allowKeychainPrompt else {
            if let cachedCredential, !cachedCredential.isExpired {
                return cachedCredential.accessToken
            }
            throw LimitsError.keychainInteractionNotAllowed
        }

        // 3. 사용자 동작 경로: 무프롬프트로 먼저 시도(과거 '항상 허용'했다면 조용히 성공), 안 되면
        //    프롬프트를 동반해 읽어 최초 1회 '항상 허용'을 유도한다.
        if let cred = Self.readKeychainSilently() {
            return try await resolveValidToken(from: cred)
        }
        let cred = try Self.readKeychain(allowKeychainPrompt: true)
        return try await resolveValidToken(from: cred)
    }

    private func resolveValidToken(from cred: AntigravityOAuthCredential) async throws -> String {
        if !cred.isExpired {
            cachedCredential = cred
            return cred.accessToken
        }
        // 만료되었고 refresh_token이 있다면 갱신 시도
        if let refreshToken = cred.refreshToken {
            if let refreshed = try? await Self.refreshGoogleToken(refreshToken: refreshToken) {
                cachedCredential = refreshed
                return refreshed.accessToken
            }
        }
        // 갱신 실패했더라도 기존 accessToken 반환 (API에서 401 나면 다시 처리)
        cachedCredential = cred
        return cred.accessToken
    }

    func invalidate() {
        cachedCredential = nil
    }

    private static func refreshGoogleToken(refreshToken: String) async throws -> AntigravityOAuthCredential? {
        // fetchStatus 와 별개의 네트워크 경계다 — 여기를 빼면 스위트가 사용자 refresh_token 을 실제로
        // 소비해 새 토큰을 발급받는다(조회보다 부작용이 크다).
        guard AppEnv.isBundledApp || AppEnv.isParityRun else { throw LimitsError.liveFetchNotPermitted }
        var request = URLRequest(url: AntigravityRateLimitsProvider.googleTokenURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "client_id": AntigravityRateLimitsProvider.googleClientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        let bodyString = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = Data(bodyString.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String else {
            return nil
        }
        let expiresIn = json["expires_in"] as? Double ?? 3600
        return AntigravityOAuthCredential(
            accessToken: newAccessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn))
    }

    private nonisolated static func readTokenFile() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = [
            home.appendingPathComponent(".gemini/jetski-standalone-oauth-token"),
            home.appendingPathComponent(".gemini/antigravity/jetski-standalone-oauth-token"),
        ]
        for url in paths {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["token"] as? String, !token.isEmpty else {
                continue
            }
            return token
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
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "gemini",
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
        guard status == errSecSuccess, let data = item as? Data else {
            throw LimitsError.keychainUnavailable(status)
        }
        guard let credential = parseCredential(data: data) else {
            throw LimitsError.credentialFormat
        }
        return credential
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

public struct AntigravityOAuthCredential: Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date().addingTimeInterval(60)
    }

    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}
