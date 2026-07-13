import Foundation

/// 프로바이더 상태 페이지(statuspage.io)의 인시던트 지표.
/// 목적: Claude/OpenAI API 장애 시 stale·0·에러 표시를 "앱 고장"으로 오인하지 않도록 **표시 전용** 신호.
/// (알림으로 만들지 않는다 — 한도/버burn 알림과 충돌·스팸 방지.)
enum ProviderStatusIndicator: String, Sendable {
    // 케이스명을 `operational` 로 둔다(rawValue 는 statuspage 문자열 "none"). `none` 으로 두면
    // 옵셔널 비교 시 `Optional.none`(nil)과 충돌하는 Swift footgun 이 생긴다.
    case operational = "none"
    case minor, major, critical, maintenance, unknown

    /// 인시던트가 있는가(정상=operational 만 false). 아이콘/행 노출 게이트.
    var hasIssue: Bool { self != .operational }

    /// statuspage.io `status.indicator` 문자열 → 지표(미지 값은 unknown).
    init(statuspage raw: String) {
        self = ProviderStatusIndicator(rawValue: raw) ?? .unknown
    }
}

/// 한 프로바이더의 상태 스냅샷. `description` 은 statuspage 원문(영문, 예: "Partially Degraded Service").
struct ProviderStatus: Sendable, Equatable {
    var indicator: ProviderStatusIndicator
    var description: String
}

/// providerID → 상태. 조회 실패한 프로바이더는 결과에서 **생략**한다(호출부가 이전 상태를 유지).
protocol ProviderStatusProviding: Sendable {
    func fetch() async -> [String: ProviderStatus]
}

/// statuspage.io summary(`.../api/v2/status.json`)를 조회하는 기본 구현.
/// PokeTokenBar 가 추적하는 provider 중 statuspage.io 를 쓰는 Claude·OpenAI(Codex) 만.
/// Gemini(Google Workspace 피드)는 파서가 무거워 제외(추후).
struct StatuspageStatusProvider: ProviderStatusProviding {
    /// providerID ↔ statuspage summary URL. Codex 는 OpenAI 상태 페이지를 공유한다.
    static let endpoints: [(id: String, url: URL)] = [
        ("claude_code", URL(string: "https://status.anthropic.com/api/v2/status.json")!),
        ("codex", URL(string: "https://status.openai.com/api/v2/status.json")!),
    ]

    func fetch() async -> [String: ProviderStatus] {
        var out: [String: ProviderStatus] = [:]
        await withTaskGroup(of: (String, ProviderStatus?).self) { group in
            for (id, url) in Self.endpoints {
                group.addTask { (id, await Self.fetchOne(url)) }
            }
            for await (id, status) in group where status != nil {
                out[id] = status
            }
        }
        return out
    }

    private static func fetchOne(_ url: URL) async -> ProviderStatus? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("PokeTokenBar", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data)
    }

    /// statuspage.io status.json 파싱(순수 — 테스트 가능). `{ "status": { "indicator", "description" } }`.
    static func parse(_ data: Data) -> ProviderStatus? {
        guard let decoded = try? JSONDecoder().decode(StatuspageResponse.self, from: data) else { return nil }
        return ProviderStatus(indicator: ProviderStatusIndicator(statuspage: decoded.status.indicator),
                              description: decoded.status.description ?? "")
    }

    private struct StatuspageResponse: Decodable {
        struct Status: Decodable { let indicator: String; let description: String? }
        let status: Status
    }
}
