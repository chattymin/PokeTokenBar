import Foundation

/// Service-reported account history, kept separate from local usage and game progress.
/// Source dates and optional metrics are preserved: a missing metric is not zero.
struct CodexAccountUsage: Codable, Sendable, Equatable {
    struct Summary: Codable, Sendable, Equatable {
        var lifetimeTokens: Int?
        var peakDailyTokens: Int?
        var longestRunningTurnSec: Int?
        var currentStreakDays: Int?
        var longestStreakDays: Int?
    }

    struct DailyBucket: Codable, Sendable, Equatable {
        var startDate: String
        var tokens: Int
    }

    var summary: Summary?
    var dailyUsageBuckets: [DailyBucket]?

    var latestReportedDay: String? { dailyUsageBuckets?.map(\.startDate).max() }
    var hasReportedTokens: Bool {
        summary?.lifetimeTokens != nil || dailyUsageBuckets?.isEmpty == false
    }
}

struct CodexAccountUsageSnapshot: Codable, Sendable, Equatable {
    var usage: CodexAccountUsage
    var fetchedAt: Date

    static func load(from fileURL: URL?) -> Self? {
        guard AppEnv.persistsToUserLocation(injectedFileURL: fileURL),
              let data = try? Data(contentsOf: resolvedFileURL(fileURL)) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save(to fileURL: URL?) {
        guard AppEnv.persistsToUserLocation(injectedFileURL: fileURL) else { return }
        let url = Self.resolvedFileURL(fileURL)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: url)
        } catch {
            AppLog.writeIfChanged("codex-account-usage-save", "account usage snapshot could not be saved")
        }
    }

    private static func resolvedFileURL(_ injected: URL?) -> URL {
        injected ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar/codex-account-usage.json")
    }
}

protocol CodexAccountUsageProviding: Sendable {
    func fetch() async throws -> CodexAccountUsage?
}

/// Uses the CLI's existing authenticated, documented account/usage/read request.
/// It starts no model turn and never extracts credentials from the ChatGPT application.
struct CodexAccountUsageProvider: CodexAccountUsageProviding {
    typealias Transport = @Sendable (String, [String]) async throws -> Data
    private let resolveBinary: @Sendable () -> String?
    private let allowsFetch: @Sendable () -> Bool
    private let transport: Transport

    init(resolveBinary: @escaping @Sendable () -> String? = { CodexRateLimitsProvider().resolvedBinary },
         allowsFetch: @escaping @Sendable () -> Bool = { AppEnv.allowsLiveLimitsFetch },
         transport: @escaping Transport = { binary, lines in
             try await ProcessRunner.runJSONRPC(binary: binary, arguments: ["app-server", "--stdio"],
                                               inputLines: lines, responseID: 1, timeout: 20)
         }) {
        self.resolveBinary = resolveBinary
        self.allowsFetch = allowsFetch
        self.transport = transport
    }

    func fetch() async throws -> CodexAccountUsage? {
        // The subprocess performs authenticated network reads internally. Gate it before discovery.
        guard allowsFetch(), let binary = resolveBinary() else { return nil }
        let lines = try CodexAppServerRequest.lines(method: "account/usage/read")
        let data = try await transport(binary, lines)
        return try JSONDecoder().decode(CodexAccountUsage.self, from: data)
    }
}
