import Foundation

/// Codex 한도 조회 추상화 — 실 구현(CodexRateLimitsProvider) 또는 테스트 스텁 주입.
protocol CodexLimitsProviding: Sendable {
    func fetch() async throws -> CodexRateLimitStatus?
}

/// Codex CLI app-server의 account/rateLimits/read 응답으로 Codex 한도 %를 읽는다.
/// 모델 turn을 시작하지 않고 account snapshot만 요청한다.
struct CodexRateLimitsProvider: CodexLimitsProviding {
    let binaryCandidates: [String]

    init(binaryCandidates: [String] = Self.defaultBinaryCandidates) {
        self.binaryCandidates = binaryCandidates
    }

    private static var defaultBinaryCandidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/.codex/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            // ChatGPT.app bundles the codex CLI; users on the desktop app often have
            // no standalone install, so this is the only resolvable path for them.
            // Listed last so dedicated installs win over the bundled copy.
            "/Applications/ChatGPT.app/Contents/Resources/codex",
        ]
    }

    var resolvedBinary: String? {
        // 앱 번들/홈 경로 우선, 이후 버전매니저 공통 경로 + 로그인 셸 PATH 해석(mise 등).
        BinaryLocator.resolve("codex", staticPaths: binaryCandidates + BinaryLocator.commonNodeToolPaths("codex"))
    }

    func fetch() async throws -> CodexRateLimitStatus? {
        guard let bin = resolvedBinary else { return nil }
        let lines = try Self.requestLines()
        let data = try await ProcessRunner.runJSONRPC(
            binary: bin,
            arguments: ["app-server", "--stdio"],
            inputLines: lines,
            responseID: 1,
            timeout: 20)
        return try JSONDecoder().decode(CodexRateLimitStatus.self, from: data)
    }

    private static func requestLines() throws -> [String] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let messages: [[String: Any]] = [
            [
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "token_mac",
                        "title": "PokeTokenBar",
                        "version": version,
                    ],
                    "capabilities": [
                        "experimentalApi": true,
                    ],
                ],
            ],
            [
                "method": "initialized",
                "params": [:],
            ],
            [
                "method": "account/rateLimits/read",
                "id": 1,
                "params": [:],
            ],
        ]
        return try messages.map { message in
            let data = try JSONSerialization.data(withJSONObject: message, options: [])
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }
}
