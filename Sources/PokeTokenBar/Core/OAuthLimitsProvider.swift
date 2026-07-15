import Foundation
import Security

enum LimitsError: Error {
    case keychainAccessDisabled
    case keychainUnavailable(OSStatus)
    case keychainInteractionNotAllowed
    case credentialFormat
    case httpStatus(Int)
    /// 429 — 서버가 지정한 Retry-After(초, 없으면 nil). 폴링 백오프 판단에 사용.
    case rateLimited(retryAfter: TimeInterval?)
}

/// Claude 한도 조회 추상화 — 실 구현(OAuthLimitsProvider) 또는 테스트 스텁 주입.
protocol ClaudeLimitsProviding: Sendable {
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus
}

/// 공식 한도 % 조회 — Claude Code 자격증명(Keychain)의 OAuth 토큰으로 usage endpoint 호출.
/// 비공식 endpoint 이므로 실패해도 토큰 표시에는 영향 없음 (한도 섹션만 숨김).
struct OAuthLimitsProvider: ClaudeLimitsProviding, Sendable {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let accessTokenCache = OAuthAccessTokenCache.shared

    func fetch(allowKeychainPrompt: Bool = false) async throws -> LimitStatus {
        let token = try await accessTokenCache.accessToken(allowKeychainPrompt: allowKeychainPrompt)
        var status: LimitStatus
        do {
            status = try await fetchStatus(accessToken: token)
        } catch let error as LimitsError {
            guard case .httpStatus(let httpStatus) = error, httpStatus == 401 || httpStatus == 403 else {
                throw error
            }
            await accessTokenCache.invalidate(removePersistentCache: true)
            let refreshed = try await accessTokenCache.accessToken(
                allowKeychainPrompt: allowKeychainPrompt, bypassCache: true)
            guard refreshed != token else { throw error }
            status = try await fetchStatus(accessToken: refreshed)
        }
        // 플랜은 usage 응답이 아니라 방금 읽은 자격증명(캐시)에 담겨 있다 — 추가 Keychain 접근 없음.
        let plan = await accessTokenCache.planInfo()
        status.subscriptionType = plan.subscriptionType
        status.rateLimitTier = plan.rateLimitTier
        return status
    }

    private func fetchStatus(accessToken: String) async throws -> LimitStatus {
        var request = URLRequest(url: Self.usageURL, timeoutInterval: 15)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if http.statusCode == 429 {
                throw LimitsError.rateLimited(retryAfter: Self.retryAfterSeconds(http))
            }
            throw LimitsError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(LimitStatus.self, from: data)
    }

    /// Retry-After 헤더(초 형식만) 파싱 — HTTP-date 형식·비정상 값은 nil(백오프 기본값 사용).
    /// 서버가 과도한 값을 줘도 1시간으로 캡.
    static func retryAfterSeconds(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)),
              seconds > 0 else { return nil }
        return min(seconds, 3600)
    }
}

private actor OAuthAccessTokenCache {
    static let shared = OAuthAccessTokenCache()
    private var cachedCredential: OAuthCredentialData.Credential?

    func accessToken(allowKeychainPrompt: Bool, bypassCache: Bool = false) throws -> String {
        if !bypassCache, let cachedCredential, !cachedCredential.isExpired {
            return cachedCredential.accessToken
        }

        // 자동(무프롬프트) 경로에서 login 키체인이 잠겨 있으면 키체인 접근을 일절 하지 않는다.
        // no-UI 플래그(kSecUseAuthenticationUIFail/LAContext)는 '인증' 프롬프트만 억제할 뿐
        // 잠긴 키체인의 '암호 입력' 다이얼로그는 못 막는다 → 잠긴 아침마다 사용자에게 팝업이 뜨는
        // 결함의 원인. 잠겨 있으면 파일 크리덴셜만 시도하고(키체인 무관), 없으면 조용히 실패한다.
        if !allowKeychainPrompt, Self.isDefaultKeychainLocked() {
            if let credential = try Self.readClaudeCredentialsFile() {
                cachedCredential = credential   // 잠긴 키체인에는 캐시 write 안 함(그 write 도 프롬프트 유발)
                return credential.accessToken
            }
            throw LimitsError.keychainInteractionNotAllowed
        }

        if let credential = try Self.readClaudeCredentialsFile() {
            cachedCredential = credential
            return credential.accessToken
        }
        // 무프롬프트(no-UI) Claude Keychain 읽기. 사용자가 과거 한 번 '항상 허용'했다면
        // 앱 cdhash 가 항목 ACL 에 등록돼 *프롬프트 없이* 성공한다. 아직 허용 전이거나 접근
        // 불가면 errSecInteractionNotAllowed 로 조용히 실패 — 다이얼로그가 뜨지 않는다.
        // 이 경로 덕분에 자동 새로고침이 만료된 토큰을 스스로 재취득해 한도(주간 리셋 포함)를
        // 갱신한다. 수동 버튼 없이 자동 동작하게 하는 핵심.
        if let credential = Self.readClaudeKeychainSilently() {
            cachedCredential = credential
            return credential.accessToken
        }
        // 무프롬프트로 토큰을 못 구함 → 명시적 사용자 동작(설정의 갱신 버튼)일 때만 프롬프트를
        // 동반해 읽는다(최초 1회 '항상 허용' 유도). 이후엔 위 무프롬프트 경로로 자동 동작한다.
        // `security` CLI 보조 경로는 별도 신원이라 두 번째 ACL 프롬프트를 띄워 제거함.
        guard allowKeychainPrompt else {
            throw LimitsError.keychainInteractionNotAllowed
        }

        let credential = try Self.readClaudeKeychain(allowKeychainPrompt: allowKeychainPrompt)
        cachedCredential = credential
        return credential.accessToken
    }

    /// 무프롬프트 Keychain 읽기 — no-UI 쿼리라 권한이 없으면 프롬프트 대신 errSecInteractionNotAllowed.
    /// '아직 항상 허용 전'(interactionNotAllowed)은 정상 흐름이라 조용히 nil. 그 외(형식 오류·접근 불가)는
    /// 진단을 위해 로그를 남기고 nil — 자동 경로가 왜 토큰을 못 구했는지 추적 가능하게.
    private nonisolated static func readClaudeKeychainSilently() -> OAuthCredentialData.Credential? {
        do {
            return try readClaudeKeychain(allowKeychainPrompt: false)
        } catch LimitsError.keychainInteractionNotAllowed {
            return nil
        } catch {
            AppLog.write("silent claude keychain read failed: \(error)")
            return nil
        }
    }

    /// login(기본) 키체인 잠금 여부. GetStatus 는 프롬프트 없이 상태만 읽는다(안전).
    /// SecKeychain* 는 deprecated 지만 파일 기반 login 키체인의 잠금 상태를 무프롬프트로 조회하는
    /// 유일한 API — 대체재 없음. 조회 실패 시 '잠기지 않음'으로 간주(기존 경로 유지, 보수적).
    private nonisolated static func isDefaultKeychainLocked() -> Bool {
        var keychain: SecKeychain?
        guard SecKeychainCopyDefault(&keychain) == errSecSuccess, let keychain else { return false }
        var status = SecKeychainStatus()
        guard SecKeychainGetStatus(keychain, &status) == errSecSuccess else { return false }
        return (status & SecKeychainStatus(kSecUnlockStateStatus)) == 0   // unlock 비트 꺼짐 = 잠김
    }

    /// 마지막으로 사용한 자격증명의 플랜 정보. accessToken() 이 모든 경로에서 cachedCredential 을
    /// 반환 토큰과 일치시키므로, fetch 가 토큰 취득 직후 호출하면 동일 자격증명 기준이다.
    func planInfo() -> (subscriptionType: String?, rateLimitTier: String?) {
        (cachedCredential?.subscriptionType, cachedCredential?.rateLimitTier)
    }

    func invalidate(removePersistentCache: Bool = false) {
        // 앱 자체 키체인 캐시는 코드서명이 바뀔 때마다(재빌드·실사용자 매 업그레이드) 항목 ACL 이
        // 안 맞아 write/삭제 시 접근 허용 프롬프트를 유발했다(no-UI 로도 억제 안 됨) → 제거.
        // 토큰은 Claude 키체인 무UI 읽기/.credentials.json 로 조용히 재취득한다. 인메모리만 비운다.
        cachedCredential = nil
    }

    // (구) 앱 자체 키체인 OAuth 캐시(read/write/delete)는 제거됨 — 코드서명 변경마다 항목 ACL
    // 불일치로 접근 허용 프롬프트를 유발했다. 토큰은 인메모리 + Claude 키체인 무UI 읽기 +
    // .credentials.json 로 충분히 조용히 취득된다.

    private nonisolated static func readClaudeCredentialsFile() throws -> OAuthCredentialData.Credential? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let credential = OAuthCredentialData.credential(from: data), !credential.isExpired else {
            return nil
        }
        return credential
    }

    private nonisolated static func readClaudeKeychain(
        allowKeychainPrompt: Bool) throws -> OAuthCredentialData.Credential
    {
        if KeychainAccessGate.isDisabled {
            throw LimitsError.keychainAccessDisabled
        }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: OAuthCredentialData.claudeKeychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if !allowKeychainPrompt {
            KeychainNoUIQuery.apply(to: &query)
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecInteractionNotAllowed {
            throw LimitsError.keychainInteractionNotAllowed
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw LimitsError.keychainUnavailable(status)
        }
        guard let credential = OAuthCredentialData.credential(from: data) else {
            throw LimitsError.credentialFormat
        }
        return credential
    }
}

enum OAuthCredentialData {
    static let claudeKeychainService = "Claude Code-credentials"

    struct Credential {
        let accessToken: String
        let expiresAt: Date?
        let data: Data
        /// 구독 등급(max/pro/free)과 rate limit 티어(default_claude_max_20x 등) — 플랜 표시용.
        let subscriptionType: String?
        let rateLimitTier: String?

        var isExpired: Bool {
            guard let expiresAt else { return false }
            return expiresAt <= Date().addingTimeInterval(60)
        }
    }

    static func credential(from data: Data) -> Credential? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String, !token.isEmpty
        else {
            return nil
        }
        return Credential(
            accessToken: token,
            expiresAt: expiresAt(from: oauth["expiresAt"]),
            data: data,
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String)
    }

    private static func expiresAt(from raw: Any?) -> Date? {
        let value: Double?
        switch raw {
        case let raw as Double:
            value = raw
        case let raw as Int:
            value = Double(raw)
        case let raw as Int64:
            value = Double(raw)
        case let raw as String:
            value = Double(raw)
        default:
            value = nil
        }
        guard let value, value > 0 else { return nil }
        let seconds = value > 10_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}
