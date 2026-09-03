import Foundation

/// claude.ai 세션 쿠키(`sessionKey`)로 공식 한도를 조회하는 경로.
///
/// **왜 두 번째 경로가 필요한가.** 기존 `OAuthLimitsProvider` 는 Claude Code 자격증명을 Keychain 에서
/// 직접 읽는다(`SecItemCopyMatching`). 앱이 그 항목의 ACL 에 없어서 macOS 암호 다이얼로그를 유발하고,
/// self-signed 서명이라 '항상 허용'도 재빌드마다 깨진다(`docs/reference/defect-log.md` 자격증명·Keychain).
/// 그래서 자동 폴링은 Keychain 을 아예 안 읽고, 토큰이 만료되면 사용자가 갱신 버튼을 눌러야 했다.
/// 이 경로는 Keychain 을 건드리지 않으므로 **프롬프트 없이 자동 폴링으로 계속 갱신된다.**
///
/// 응답 스키마는 `api.anthropic.com/api/oauth/usage` 와 동일하다(`five_hour`/`seven_day`/`limits[]`,
/// `utilization`+`resets_at`) — 그래서 `LimitStatus` 를 그대로 재사용한다.
///
/// **검증 함정:** 이 엔드포인트는 curl 로 확인할 수 없다. Cloudflare 가 curl 을 챌린지로 403 시키고
/// (`cf-mitigated: challenge`) URLSession 만 통과한다. 실 검증은 `scripts/probe-session-key.swift` 로 한다.

// MARK: HTTP 시임

struct SessionKeyHTTPResponse: Sendable {
    let status: Int
    let data: Data
    /// 429 응답의 Retry-After(초). 백오프 판단에 쓴다.
    let retryAfter: TimeInterval?
}

/// claude.ai GET 하나. 테스트는 이 계층을 픅스처로 갈아끼운다(실 호출은 CI 에서 불가 — 위 함정 참조).
protocol SessionKeyHTTPClient: Sendable {
    func get(_ url: URL, sessionKey: String) async throws -> SessionKeyHTTPResponse
}

struct URLSessionSessionKeyClient: SessionKeyHTTPClient {
    /// claude.ai 는 브라우저에서 오는 요청만 기대한다 — Origin/Referer/UA 가 없으면 거절될 수 있다.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    func get(_ url: URL, sessionKey: String) async throws -> SessionKeyHTTPResponse {
        // 다른 한도 프로바이더와 같은 게이트 — `swift test`·로우 바이너리가 사용자 실계정 자격증명으로
        // 네트워크를 치지 않게 한다. 세션 키는 Keychain 프롬프트가 없어 *더* 조용히 새기 쉽다:
        // 스텁을 주입하지 않은 테스트 구성이 그대로 claude.ai 를 호출한다.
        // 게이트는 자격증명 로드가 아니라 **네트워크 경계**에 둔다(defect-log 동일 항목).
        // 주입된 테스트용 `SessionKeyHTTPClient` 는 이 타입을 거치지 않으므로 영향받지 않는다.
        guard AppEnv.isBundledApp || AppEnv.isParityRun else { throw LimitsError.liveFetchNotPermitted }
        var request = URLRequest(url: url, timeoutInterval: 15)
        // 쿠키를 헤더로 직접 넣는다. 공유 저장소가 개입하면 이 헤더를 덮어써 인증이 뒤바뀔 수 있다.
        request.httpShouldHandleCookies = false
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        return SessionKeyHTTPResponse(
            status: http?.statusCode ?? -1,
            data: data,
            retryAfter: http.flatMap(OAuthLimitsProvider.retryAfterSeconds))
    }
}

// MARK: 자격증명 저장

struct SessionKeyCredential: Codable, Sendable, Equatable {
    var key: String
    /// 마지막으로 고른 조직. 있으면 목록 조회를 건너뛴다.
    var organizationID: String?
}

/// 세션 키 영속 — Application Support 평문 JSON(0600).
///
/// **앱 소유 Keychain 항목에 넣지 않는다.** 그건 `defect-log` 가 금지한 부류다 — 앱이 만든 항목은
/// 코드서명(cdhash)이 바뀔 때마다 ACL 이 안 맞아 접근 허용 프롬프트를 유발하고, no-UI 쿼리로도
/// 억제되지 않는다(#58). Keychain 프롬프트를 없애려고 넣은 기능이 프롬프트를 다시 들이면 의미가 없다.
/// 대가는 평문 보관이며, 설정 UI 가 그 사실과 무효화 방법(브라우저 로그아웃)을 함께 안내한다.
struct SessionKeyStore: Sendable {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL()
    }

    /// 기본 위치 — companion 상태와 같은 격리 규약(`PTB_STATE_DIR`)을 따른다. QA·데모 실행이
    /// 실제 자격증명을 건드리지 않게. 환경변수 해석은 `AppStatePaths` 가 전담한다.
    private static func defaultURL() -> URL {
        AppStatePaths.directory().appendingPathComponent("session-key.json")
    }

    func load() -> SessionKeyCredential? {
        guard let data = try? Data(contentsOf: fileURL),
              let credential = try? JSONDecoder().decode(SessionKeyCredential.self, from: data),
              !credential.key.isEmpty
        else { return nil }
        return credential
    }

    func save(_ credential: SessionKeyCredential) throws {
        let data = try JSONEncoder().encode(credential)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 소유자 전용으로 만든 뒤 쓴다 — 먼저 쓰고 나중에 chmod 하면 그 사이 기본 권한으로 노출된다.
        try? FileManager.default.removeItem(at: fileURL)
        FileManager.default.createFile(
            atPath: fileURL.path, contents: nil,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o600))])
        try data.write(to: fileURL, options: .atomic)
        // 실측으로 .atomic 교체는 기존 파일의 권한을 물려받았지만(APFS), 문서화된 보장이 아니라
        // 자격증명 파일을 걸 만한 근거가 못 된다 → 쓴 뒤 한 번 더 못박는다.
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: fileURL.path)
        CredentialFileProtection.excludeFromBackup(fileURL)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 붙여넣은 값 정리·검증. 브라우저에서 복사할 때 공백·줄바꿈이 섞이는 게 흔하다.
    /// prefix 는 `sk-ant-` 까지만 본다 — 실측으로 `sid01`/`sid02` 두 형식이 존재한다.
    static func normalize(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("sk-ant-"), trimmed.count >= 40, trimmed.count <= 2_048,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw LimitsError.sessionKeyMalformed }
        return trimmed
    }
}

// MARK: 조직

/// 후보 조직. 자동 선택과 설정 드롭다운이 같은 데이터를 쓴다.
struct SessionKeyOrganization: Sendable, Identifiable {
    let id: String
    let name: String
    /// 값이 들어있는 조직인지 — 로그인만 해두고 안 쓰는 조직은 0%/resets_at null 로 온다.
    let hasUsageData: Bool
    let limits: LimitStatus
}

/// 세션 키 관리 — 설정 화면이 쓰는 부분만 노출한다(테스트는 이 프로토콜로 대체).
protocol SessionKeyManaging: Sendable {
    func credential() -> SessionKeyCredential?
    func organizations(sessionKey: String) async throws -> [SessionKeyOrganization]
    func save(key: String, organizationID: String?) throws
    func clear()
}

// MARK: 프로바이더

struct SessionKeyLimitsProvider: ClaudeLimitsProviding, SessionKeyManaging {
    /// 기본 인스턴스 — 한도 조회 체인과 설정 화면이 같은 파일·같은 조직 캐시를 봐야 한다.
    static let shared = SessionKeyLimitsProvider()

    private static let base = URL(string: "https://claude.ai/api")!

    private let store: SessionKeyStore
    private let http: any SessionKeyHTTPClient

    init(store: SessionKeyStore = SessionKeyStore(),
         http: any SessionKeyHTTPClient = URLSessionSessionKeyClient()) {
        self.store = store
        self.http = http
    }

    /// `allowKeychainPrompt` 는 쓰지 않는다 — 이 경로는 Keychain 을 건드리지 않으므로 자동 폴링에서도
    /// 그대로 돌아간다. (프로토콜 요구사항이라 시그니처만 맞춘다.)
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        guard let credential = store.load() else { throw LimitsError.sessionKeyMissing }

        if let orgID = credential.organizationID {
            do {
                return try await usage(organizationID: orgID, sessionKey: credential.key)
            } catch LimitsError.httpStatus(403) {
                // 403 은 "이 조직에 권한 없음"(탈퇴·권한 회수). 키 자체는 살아있을 수 있으니 다시 고른다.
                // 401(키 무효)은 여기서 잡지 않는다 — 재탐색해도 같은 401 이라 낭비다.
                AppLog.write("session key: cached org \(orgID) forbidden, rediscovering")
            }
        }

        let candidates: [SessionKeyOrganization]
        do {
            candidates = try await organizations(sessionKey: credential.key)
        } catch LimitsError.httpStatus(403) {
            // `/api/organizations` 는 조직 스코프가 아니다 — 여기서의 403 은 "그 조직에 권한 없음"이
            // 아니라 **이 키로는 아무것도 못 본다**, 즉 키가 죽었다는 뜻이다(만료·브라우저 로그아웃).
            // 조직 권한 문제라면 그 조직의 usage 만 403 이고 목록 조회는 통과한다 — 그 경우는 위의
            // 재탐색 분기가 처리하므로 여기까지 오지 않는다.
            //
            // 실측(2026-08-30): 실제 앱에서 저장된 세션 키의 한 글자를 바꾸자 usage 와 organizations 가
            // 함께 403 을 냈다(`session key limits failed: httpStatus(403)`). 죽은 키는 401 이 아니라
            // 403 이다 — mapFailure 가 401 만 sessionKeyInvalid 로 접는 탓에, 세션 키 만료가 UsageStore
            // 에서 OAuth 만료로 분류돼 "Claude Code 를 실행하세요"라는 엉뚱한 안내가 나갔다.
            // (curl 로는 확인 못 한다 — 파일 상단 '검증 함정' 주석 참조.)
            throw LimitsError.sessionKeyInvalid
        }
        // 값이 있는 조직 우선. 참조 구현이 쓰는 "첫 번째"는 로그인만 해둔 조직을 골라 영구히 0% 를 낸다.
        guard let picked = candidates.first(where: \.hasUsageData) ?? candidates.first else {
            throw LimitsError.sessionKeyNoOrganization
        }
        if picked.id != credential.organizationID {
            try? store.save(SessionKeyCredential(key: credential.key, organizationID: picked.id))
            AppLog.write("session key: selected org \(picked.id) (hasUsage=\(picked.hasUsageData))")
        }
        return picked.limits
    }

    func credential() -> SessionKeyCredential? { store.load() }

    func save(key: String, organizationID: String?) throws {
        try store.save(SessionKeyCredential(key: try SessionKeyStore.normalize(key),
                                            organizationID: organizationID))
    }

    func clear() { store.clear() }

    /// 접근 가능한 조직 목록(순서 유지). 403 인 조직은 제외한다 — API 전용 조직이 그렇게 온다.
    func organizations(sessionKey: String) async throws -> [SessionKeyOrganization] {
        let response = try await http.get(Self.base.appendingPathComponent("organizations"),
                                          sessionKey: sessionKey)
        try Self.mapFailure(response)
        let rows = try Self.decodeRows(response.data)

        // `chat` 없는 조직(API 전용)은 usage 를 403 으로 거절하므로 아예 조회하지 않는다.
        // capabilities 가 안 오면(스키마 변동) 걸러내지 않는다 — 후보를 0개로 만드는 게 더 나쁘다.
        var candidates = rows.filter { $0.capabilities?.contains("chat") ?? true }
        if candidates.isEmpty { candidates = rows }

        let usable = try await withThrowingTaskGroup(
            of: (Int, SessionKeyOrganization?).self
        ) { group -> [(Int, SessionKeyOrganization?)] in
            for (index, row) in candidates.enumerated() {
                group.addTask {
                    do {
                        let limits = try await usage(organizationID: row.uuid, sessionKey: sessionKey)
                        return (index, SessionKeyOrganization(
                            id: row.uuid, name: row.name ?? row.uuid,
                            hasUsageData: Self.hasUsageData(limits), limits: limits))
                    } catch LimitsError.httpStatus {
                        return (index, nil)   // 이 조직만 못 보는 것 — 나머지로 계속 간다.
                    }
                }
            }
            var collected: [(Int, SessionKeyOrganization?)] = []
            for try await result in group { collected.append(result) }
            return collected
        }

        // 병렬 조회라 완료 순서가 뒤섞인다 — 목록 순서(사용자가 설정에서 보는 순서)로 되돌린다.
        return usable.sorted { $0.0 < $1.0 }.compactMap(\.1)
    }

    private func usage(organizationID: String, sessionKey: String) async throws -> LimitStatus {
        let url = Self.base.appendingPathComponent("organizations")
            .appendingPathComponent(organizationID).appendingPathComponent("usage")
        let response = try await http.get(url, sessionKey: sessionKey)
        try Self.mapFailure(response)
        return try JSONDecoder().decode(LimitStatus.self, from: response.data)
    }

    /// 200 이 아니면 던진다. 401 은 키 무효(재입력 안내), 403 은 호출부가 판단(조직 권한일 수 있다).
    private static func mapFailure(_ response: SessionKeyHTTPResponse) throws {
        switch response.status {
        case 200: return
        case 401: throw LimitsError.sessionKeyInvalid
        case 429: throw LimitsError.rateLimited(retryAfter: response.retryAfter)
        default: throw LimitsError.httpStatus(response.status)
        }
    }

    /// 실제로 쓰는 조직인지 — 사용률이 있거나 리셋 시각이 잡혀 있으면 활성으로 본다.
    private static func hasUsageData(_ limits: LimitStatus) -> Bool {
        let windows = [limits.fiveHour, limits.sevenDay, limits.sevenDayOpus, limits.sevenDaySonnet]
        if windows.contains(where: { ($0?.utilization ?? 0) > 0 || $0?.resetsAt != nil }) { return true }
        return (limits.limits ?? []).contains { ($0.percent ?? 0) > 0 || $0.resetsAt != nil }
    }

    private struct OrganizationRow: Decodable {
        let uuid: String
        let name: String?
        let capabilities: [String]?
    }

    private static func decodeRows(_ data: Data) throws -> [OrganizationRow] {
        do {
            return try JSONDecoder().decode([OrganizationRow].self, from: data)
        } catch {
            throw LimitsError.credentialFormat
        }
    }
}

// MARK: 체인

/// 세션 키 우선, 실패 시 기존 OAuth(Keychain/파일) 경로. 한쪽만 설정한 사용자도 그대로 동작한다.
struct ChainedLimitsProvider: ClaudeLimitsProviding {
    let primary: any ClaudeLimitsProviding
    let fallback: any ClaudeLimitsProviding

    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        do {
            return try await primary.fetch(allowKeychainPrompt: allowKeychainPrompt)
        } catch {
            // 키를 안 넣은 사용자는 이게 정상 흐름이라 로그를 남기지 않는다.
            let configured = (error as? LimitsError) != .sessionKeyMissing
            if configured { AppLog.write("session key limits failed: \(error)") }
            do {
                // 키를 넣어 둔 사용자에겐 폴백이 Keychain 을 열지 못하게 막는다. 이 기능의 존재
                // 이유가 그 프롬프트를 없애는 것이라, 키가 죽었다고 수동 갱신에서 다시 띄우면
                // 기능이 스스로를 무효화한다 — 죽은 키의 답은 Keychain 이 아니라 키 재입력이고,
                // 만료 배너도 갱신 버튼이 아니라 설정 화면으로 보낸다. 키가 없을 때만 기존 동작
                // (수동 갱신 = Keychain 읽기)을 그대로 통과시킨다.
                return try await fallback.fetch(
                    allowKeychainPrompt: configured ? false : allowKeychainPrompt)
            } catch let fallbackError {
                // 키를 넣어놨는데 죽은 경우엔 그 사실이 사용자에게 더 쓸모 있다 — 재입력하면 되니까.
                // 키가 없으면 기존 안내(자격증명 없음/재로그인)를 그대로 보여준다.
                throw configured ? error : fallbackError
            }
        }
    }
}
