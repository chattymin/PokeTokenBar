import Foundation
import Security

enum LimitsError: Error {
    case keychainAccessDisabled
    /// 번들 앱도 파리티 런도 아닌 프로세스(= `swift test`·로우 바이너리)에서의 라이브 조회 차단.
    /// 자격증명이 파일(`~/.claude/.credentials.json`)로 존재하면 무프롬프트 경로가 그대로 성공하므로,
    /// 스텁을 주입하지 않은 테스트가 사용자 실계정 토큰으로 endpoint 를 친다 — `OpenCodeGoLimitsProvider`
    /// 가 이미 막아둔 것과 같은 부류다.
    case liveFetchNotPermitted
    case keychainUnavailable(OSStatus)
    case keychainInteractionNotAllowed
    case credentialFormat
    /// 자격증명은 읽혔지만 Claude 계정 OAuth(`claudeAiOauth`)가 없다 — MCP 서버 OAuth 상태만 들어있는 경우.
    /// Claude Code 2.1.x 에서 관측된다. 형식 오류가 아니라 재로그인이 필요한 상태라 따로 구분한다.
    case credentialMissingAccountOAuth
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
        var activeToken = token
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
            activeToken = refreshed
        }
        // 플랜은 usage 응답이 아니라 방금 읽은 자격증명(캐시)에 담겨 있다 — 추가 Keychain 접근 없음.
        let plan = await accessTokenCache.planInfo()
        status.subscriptionType = plan.subscriptionType
        status.rateLimitTier = plan.rateLimitTier
        // 계정 식별(이메일·조직) — 같은 기기에서 두 계정이 하나의 Keychain 항목을 번갈아 덮어쓰면
        // 한도 바가 어느 계정 것인지 소리 없이 뒤바뀐다. 토큰의 실제 주인을 profile endpoint 로
        // 조회해 라벨링한다. best-effort: 실패해도 한도 표시는 그대로 (라벨만 생략).
        if let identity = await OAuthProfileCache.shared.identity(accessToken: activeToken) {
            status.accountEmail = identity.email
            status.accountOrganizationName = identity.organizationName
        }
        return status
    }

    private func fetchStatus(accessToken: String) async throws -> LimitStatus {
        // 게이트는 *네트워크 경계*에 둔다 — 토큰 취득 앞에 두면 `KeychainAutoPathTests` 의
        // 사용자 경로 단언(키체인을 읽어야 한다)이 0 이 되어, 짝인 자동경로 단언이 "아무도 안 읽는다"로도
        // 만족되는 공허한 가드가 된다(#210 이 막으려던 바로 그 상태). 자격증명 읽기는 그대로 두고
        // 나가는 호출만 막는다. profile 조회는 이 함수가 성공해야 도달하므로 여기서 함께 차단된다.
        guard AppEnv.isBundledApp || AppEnv.isParityRun else { throw LimitsError.liveFetchNotPermitted }
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

/// OAuth 토큰의 실제 주인(계정 이메일·조직명). usage 응답에는 계정 정보가 없어 profile endpoint 로 조회한다.
struct AccountIdentity: Equatable, Sendable {
    let email: String
    let organizationName: String?
}

/// profile 조회 캐시 — 토큰이 바뀌지 않는 한 계정 주인도 바뀌지 않으므로 토큰당 1회만 네트워크를 탄다
/// (한도 폴링마다 HTTP 요청이 2배가 되는 것을 방지). 실패는 캐시하지 않는다 — 토큰이 바뀐 직후 조회가
/// 실패했을 때 이전 계정 라벨을 계속 보여주면 라벨링이 없느니만 못하다(잘못된 계정 표시).
actor OAuthProfileCache {
    static let shared = OAuthProfileCache()
    private var cachedToken: String?
    private var cachedIdentity: AccountIdentity?

    func identity(accessToken: String) async -> AccountIdentity? {
        if cachedToken == accessToken { return cachedIdentity }
        guard let identity = await Self.fetchIdentity(accessToken: accessToken) else { return nil }
        cachedToken = accessToken
        cachedIdentity = identity
        return identity
    }

    private static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    private static func fetchIdentity(accessToken: String) async -> AccountIdentity? {
        var request = URLRequest(url: profileURL, timeoutInterval: 15)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return OAuthProfileData.identity(from: data)
    }
}

/// profile 응답 파싱 — 순수 함수로 분리해 픽스처로 테스트한다.
enum OAuthProfileData {
    /// `{"account":{"email":...},"organization":{"name":...}}` → AccountIdentity.
    /// email 이 없거나 비면 응답 전체를 버린다(부분 라벨은 오인 소지) — organization 은 선택.
    static func identity(from data: Data) -> AccountIdentity? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let account = json["account"] as? [String: Any],
            let email = account["email"] as? String, !email.isEmpty
        else {
            return nil
        }
        let organization = json["organization"] as? [String: Any]
        let orgName = (organization?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return AccountIdentity(email: email, organizationName: orgName)
    }
}

private actor OAuthAccessTokenCache {
    static let shared = OAuthAccessTokenCache()
    private var cachedCredential: OAuthCredentialData.Credential?

    func accessToken(allowKeychainPrompt: Bool, bypassCache: Bool = false) throws -> String {
        if !bypassCache, let cachedCredential, !cachedCredential.isExpired {
            return cachedCredential.accessToken
        }

        // 파일 크리덴셜(~/.claude/.credentials.json) — 키체인 무관, 프롬프트 없음.
        if let credential = try Self.readClaudeCredentialsFile() {
            cachedCredential = credential
            return credential.accessToken
        }

        // 자동(타이머) 경로는 Claude Keychain 을 일절 읽지 않는다. no-UI 쿼리(kSecUseAuthenticationUIFail
        // /LAContext)로도 잠긴·미승인 login 키체인의 '암호 입력' 다이얼로그는 억제되지 않는다 —
        // 실측: 캐시 만료 폴 도중 SecItemCopyMatching 이 13초간 블록하며 팝업을 띄웠다(하루 몇 회).
        // → Keychain 읽기는 명시적 사용자 동작(설정/팝오버의 갱신 버튼, allowKeychainPrompt=true)에서만
        // 수행한다. 캐시된 토큰이 살아있는 동안은 자동 폴링이 그 토큰으로 계속 한도를 갱신하고, 만료되면
        // 한도는 마지막 값으로 stale 표시된 뒤 사용자가 갱신을 누를 때 재취득된다.
        // 자동 경로는 여기서 끝난다(키체인 미열람). 파일이 있는데 계정 OAuth 만 없으면 재로그인이
        // 답이므로 그때만 안내를 바꾼다 — 판정은 이 분기 안에서 해야 사용자 경로가 파일을 두 번 읽지 않는다.
        guard allowKeychainPrompt else {
            throw Self.credentialsFileIsAccountOAuthMissing()
                ? LimitsError.credentialMissingAccountOAuth
                : LimitsError.keychainInteractionNotAllowed
        }

        // 사용자 동작 경로: 무프롬프트로 먼저 시도(과거 '항상 허용'했다면 조용히 성공), 안 되면 프롬프트를
        // 동반해 읽어 최초 1회 '항상 허용'을 유도한다.
        if let credential = Self.readClaudeKeychainSilently() {
            cachedCredential = credential
            return credential.accessToken
        }
        let credential = try Self.readClaudeKeychain(allowKeychainPrompt: true)
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

    /// 자격증명 파일이 존재하지만 계정 OAuth 가 없는 상태인지(만료는 여기 해당 없음 — 그건 재취득 대상).
    ///
    /// 설정 위치를 옮긴 사용자(`CLAUDE_CONFIG_DIR`)는 판정에서 제외한다. 이 경로는 기본 위치를 하드코딩하는데,
    /// 옮긴 뒤 남은 옛 파일이 `mcpOAuth` 만 담고 있으면 실제로는 로그인된 사용자에게 매 폴링마다 재로그인
    /// 배너를 띄우게 된다. 옮긴 자격증명이 어디 있는지는 확인된 바 없으므로 추측하지 않고 판정을 접는다
    /// (한도는 키체인 경로로 계속 동작한다).
    private nonisolated static func credentialsFileIsAccountOAuthMissing() -> Bool {
        // 프로세스 환경만 본다 — 셸 조회(`shellAwareClaudeConfigDir`)를 부르면 이 자동 폴링 경로가
        // 안내 문구 하나를 고르려고 로그인 셸 spawn(수백 ms~수 초)을 유발하고, 그 동안 토큰 캐시 actor 가
        // 막힌다. 값이 필요한 쪽(사용량 스캔)이 이미 셸 조회를 하므로 여기서 감당할 이유가 없다.
        guard ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]?.isEmpty ?? true else { return false }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url) else { return false }
        return OAuthCredentialData.isAccountOAuthMissing(data)
    }

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
        let status = KeychainReader.copyMatching(query, &item)
        if status == errSecInteractionNotAllowed {
            throw LimitsError.keychainInteractionNotAllowed
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw LimitsError.keychainUnavailable(status)
        }
        guard let credential = OAuthCredentialData.credential(from: data) else {
            // 항목은 있는데 계정 OAuth 만 없는 상태(MCP OAuth 전용)는 재로그인 안내 대상이라 구분한다.
            throw OAuthCredentialData.isAccountOAuthMissing(data)
                ? LimitsError.credentialMissingAccountOAuth
                : LimitsError.credentialFormat
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

    /// JSON 은 멀쩡한데 `claudeAiOauth` 만 없는 상태인지. Claude Code 2.1.x 의 자격증명 항목이
    /// MCP 서버 OAuth(`mcpOAuth`) 상태만 담고 계정 토큰은 안 담는 경우가 있어, 이때는 파싱 실패를
    /// "형식 오류"가 아니라 "재로그인 필요"로 안내해야 한다.
    /// (JSON 자체가 깨진 경우는 여기 해당하지 않는다 — 그건 형식 오류다.)
    ///
    /// `json["claudeAiOauth"] == nil` 로 검사하면 안 된다. 명시적 JSON `null` 은 `NSNull` 로 디코드돼
    /// `!= nil` 이 참이 되므로, 로그아웃 상태(`"claudeAiOauth": null`)를 "값 있음"으로 오판해 재로그인
    /// 안내 대신 "자격증명 없음"을 띄운다. 딕셔너리로 캐스팅되는지로 판단한다.
    static func isAccountOAuthMissing(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (json["claudeAiOauth"] as? [String: Any]) == nil
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
