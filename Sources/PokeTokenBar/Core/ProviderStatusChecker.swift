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

    /// statuspage.io 구성요소 상태 → 앱 표시 지표.
    init(componentStatus raw: String) {
        switch raw {
        case "operational":         self = .operational
        case "degraded_performance": self = .minor
        case "partial_outage":      self = .major
        case "major_outage":        self = .critical
        case "under_maintenance":    self = .maintenance
        default:                     self = .unknown
        }
    }
}

/// 한 프로바이더의 상태 스냅샷. `description` 은 표시 대상 구성요소 이름 또는 statuspage 원문.
struct ProviderStatus: Sendable, Equatable {
    var indicator: ProviderStatusIndicator
    var description: String
}

/// providerID → 상태. 조회 실패한 프로바이더는 결과에서 **생략**한다(호출부가 이전 상태를 유지).
protocol ProviderStatusProviding: Sendable {
    func fetch() async -> [String: ProviderStatus]
}

/// statuspage.io summary(`.../api/v2/summary.json`)를 조회하는 기본 구현.
/// 전체 회사 상태는 무관한 제품 장애까지 포함하므로, PokeTokenBar 가 실제 사용하는 구성요소만 읽는다.
/// 현재는 statuspage.io 를 쓰는 Claude Code·OpenAI Codex 만.
/// Gemini(Google Workspace 피드)는 파서가 무거워 제외(추후).
struct StatuspageStatusProvider: ProviderStatusProviding {
    struct Endpoint: Sendable {
        let id: String
        let url: URL
        let componentName: String
    }

    /// providerID ↔ statuspage 구성요소. 로컬 Codex CLI 는 `Codex API` 상태를 사용한다.
    static let endpoints: [Endpoint] = [
        Endpoint(id: "claude_code",
                 url: URL(string: "https://status.claude.com/api/v2/summary.json")!,
                 componentName: "Claude Code"),
        Endpoint(id: "codex",
                 url: URL(string: "https://status.openai.com/api/v2/summary.json")!,
                 componentName: "Codex API"),
    ]

    func fetch() async -> [String: ProviderStatus] {
        var out: [String: ProviderStatus] = [:]
        await withTaskGroup(of: (String, ProviderStatus?).self) { group in
            for endpoint in Self.endpoints {
                group.addTask {
                    (endpoint.id, await Self.fetchOne(endpoint.url,
                                                      componentName: endpoint.componentName))
                }
            }
            for await (id, status) in group where status != nil {
                out[id] = status
            }
        }
        return out
    }

    private static func fetchOne(_ url: URL, componentName: String) async -> ProviderStatus? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("PokeTokenBar", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parseComponent(data, named: componentName)
    }

    /// statuspage.io status.json 파싱(순수 — 테스트 가능). `{ "status": { "indicator", "description" } }`.
    static func parse(_ data: Data) -> ProviderStatus? {
        guard let decoded = try? JSONDecoder().decode(StatuspageResponse.self, from: data) else { return nil }
        return ProviderStatus(indicator: ProviderStatusIndicator(statuspage: decoded.status.indicator),
                              description: decoded.status.description ?? "")
    }

    /// summary.json 에서 지정한 제품 구성요소만 파싱한다. 전역 indicator 가 장애여도 해당 구성요소가
    /// operational 이면 정상으로 반환해, 이미지 생성 같은 무관한 장애가 Codex 경고로 새지 않게 한다.
    static func parseComponent(_ data: Data, named componentName: String) -> ProviderStatus? {
        guard let decoded = try? JSONDecoder().decode(StatuspageSummaryResponse.self, from: data),
              let component = decoded.components.first(where: {
                  $0.name.caseInsensitiveCompare(componentName) == .orderedSame
              }) else { return nil }
        return ProviderStatus(indicator: ProviderStatusIndicator(componentStatus: component.status),
                              description: component.name)
    }

    private struct StatuspageResponse: Decodable {
        struct Status: Decodable { let indicator: String; let description: String? }
        let status: Status
    }

    private struct StatuspageSummaryResponse: Decodable {
        struct Component: Decodable { let name: String; let status: String }
        let components: [Component]
    }
}
