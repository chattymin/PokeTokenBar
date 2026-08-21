import Foundation

/// OpenCode Go 한도 조회 추상화 — 실 구현(OpenCodeGoLimitsProvider) 또는 테스트 스텁 주입.
protocol OpenCodeGoLimitsProviding: Sendable {
    func fetch() async throws -> OpenCodeGoLimitStatus?
}

/// OpenCode Go 구독 한도 조회 — 공식 usage endpoint(`GET /zen/go/v1/usage`, anomalyco/opencode#16513).
/// API 키는 opencode CLI 가 저장하는 데이터 루트의 `auth.json` 에서 `opencode-go` 항목을 읽는다
/// (브라우저 세션 쿠키·workspace ID 불필요). 키가 없으면 nil — Claude 한도의 "조용히 숨김"과 동일하게
/// 토큰 표시에는 영향을 주지 않는다.
struct OpenCodeGoLimitsProvider: OpenCodeGoLimitsProviding, Sendable {
    private static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!
    /// auth.json 후보 경로 — `LocalAdditionalUsageReader.defaultOpenCodeRoots`(OPENCODE_DATA_DIR 지원)
    /// 의 단일 소스를 공유한다(확장 규약: 루트 목록은 프로바이더별 한 곳에서만).
    private let authFileCandidates: [URL]

    init(authFileCandidates: [URL]? = nil) {
        self.authFileCandidates = authFileCandidates ?? Self.defaultAuthFileCandidates()
    }

    private static func defaultAuthFileCandidates() -> [URL] {
        LocalAdditionalUsageReader.defaultOpenCodeRoots.map { $0.appendingPathComponent("auth.json") }
    }

    func fetch() async throws -> OpenCodeGoLimitStatus? {
        // swift test / 로우 바이너리 실행이 실사용자 키로 네트워크를 치지 않게 한다(AppEnv 단일 게이트 —
        // 알림·키체인·프로덕션 로그와 동일 규약. UsageStore 에 새 한도 프로바이더가 붙을 때마다 모든
        // 테스트 구성이 스텁을 챙겨야 하는 구조적 허점의 기계적 봉쇄). 라이브 검증은 PTB_PARITY=1
        // 파리티 테스트(testLiveOpenCodeGoUsageEndpoint)가 이 프로바이더를 직접 호출한다.
        guard AppEnv.isBundledApp || AppEnv.isParityRun else { return nil }
        guard let key = Self.readAPIKey(candidates: authFileCandidates) else { return nil }
        let (data, response) = try await URLSession.shared.data(for: Self.makeRequest(key: key))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // 401 = 키 불명, 403 = 유효 키지만 Go 구독 없음 — 어느 쪽이든 섹션 숨김 대상.
            throw LimitsError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(OpenCodeGoLimitStatus.self, from: data)
    }

    /// 명시적 User-Agent 필수 — 서버(=Cloudflare)가 도구 기본 UA(Python-urllib 등)를 403 으로
    /// 차단하는 것을 실측했다(2026-08-21). URLSession 기본 UA 도 예외가 아님이 밝혀지면 그대로 막힌다.
    static func makeRequest(key: String) -> URLRequest {
        var request = URLRequest(url: usageURL, timeoutInterval: 15)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        request.setValue("PokeTokenBar/\(version)", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// `auth.json` 에서 `opencode-go` API 키를 추출한다 — 파일 읽기/JSON 파싱과 분리된 순수 함수.
    /// zen 페이즈유고 키(`opencode` 항목)는 Go 구독과 별개 계약이라 폴백하지 않는다.
    static func readAPIKey(candidates: [URL]) -> String? {
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entry = json["opencode-go"] as? [String: Any],
                  let key = entry["key"] as? String, !key.isEmpty else { continue }
            return key
        }
        return nil
    }
}
