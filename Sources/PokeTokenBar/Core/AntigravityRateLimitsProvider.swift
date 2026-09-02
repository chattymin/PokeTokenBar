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

public typealias AntigravityTokenRefresher = @Sendable (String) async throws -> AntigravityOAuthCredential?

actor AntigravityTokenCache {
    static let shared = AntigravityTokenCache()
    private var cachedCredential: AntigravityOAuthCredential?
    private let tokenFileURLs: [URL]
    private let persistentStoreURL: URL?
    private let tokenRefresher: AntigravityTokenRefresher

    init(
        tokenFileURLs: [URL]? = nil,
        persistentStoreURL: URL? = nil,
        tokenRefresher: AntigravityTokenRefresher? = nil
    ) {
        self.tokenFileURLs = tokenFileURLs ?? Self.defaultTokenFileURLs
        if let persistentStoreURL {
            self.persistentStoreURL = persistentStoreURL
        } else if tokenFileURLs == nil {
            self.persistentStoreURL = Self.defaultPersistentStoreURL
        } else {
            // 테스트 등에서 tokenFileURLs 를 명시적으로 주입한 경우 실제 앱 상태 디렉토리를 오염시키지 않음
            self.persistentStoreURL = nil
        }
        self.tokenRefresher = tokenRefresher ?? { try await Self.refreshGoogleToken(refreshToken: $0) }
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
                cachedCredential = fileCred
                persistCredential(fileCred)
            }
            if !bypassCache && !fileCred.isExpired {
                return fileCred.accessToken
            }
            if let refreshToken = fileCred.refreshToken {
                if let refreshed = try? await tokenRefresher(refreshToken) {
                    cachedCredential = refreshed
                    persistCredential(refreshed)
                    return refreshed.accessToken
                }
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
                if let refreshed = try? await tokenRefresher(refreshToken) {
                    self.cachedCredential = refreshed
                    persistCredential(refreshed)
                    return refreshed.accessToken
                }
            }

            throw LimitsError.keychainInteractionNotAllowed
        }

        // 3. 사용자 동작 경로(allowKeychainPrompt=true):
        // 사용자가 명시적으로 갱신을 요청했으므로 캐시를 우회하여 Keychain 에서 최신 자격증명을 읽는다.
        // 무프롬프트로 먼저 시도(과거 '항상 허용'했다면 조용히 성공), 안 되면 프롬프트를 동반해 읽는다.
        if let cred = Self.readKeychainSilently() {
            return try await resolveValidToken(from: cred)
        }
        let cred = try Self.readKeychain(allowKeychainPrompt: true)
        return try await resolveValidToken(from: cred)
    }

    private func resolveValidToken(from cred: AntigravityOAuthCredential) async throws -> String {
        if !cred.isExpired {
            cachedCredential = cred
            persistCredential(cred)
            return cred.accessToken
        }
        // 만료되었고 refresh_token이 있다면 갱신 시도
        if let refreshToken = cred.refreshToken {
            if let refreshed = try? await tokenRefresher(refreshToken) {
                cachedCredential = refreshed
                persistCredential(refreshed)
                return refreshed.accessToken
            }
        }
        // 갱신 실패했더라도 기존 accessToken 저장 및 반환 (API에서 401 나면 다시 처리)
        cachedCredential = cred
        persistCredential(cred)
        return cred.accessToken
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

    static func refreshGoogleToken(refreshToken: String) async throws -> AntigravityOAuthCredential? {
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
