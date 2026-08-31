import Foundation

public struct ProviderMetadata: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    public static let allKnown: [ProviderMetadata] = [
        ProviderMetadata(id: "claude_code", displayName: "Claude Code"),
        ProviderMetadata(id: "codex", displayName: "Codex"),
        ProviderMetadata(id: "gemini", displayName: "Gemini CLI"),
        ProviderMetadata(id: "antigravity", displayName: "Antigravity"),
        ProviderMetadata(id: "opencode", displayName: "OpenCode"),
        ProviderMetadata(id: "cursor", displayName: "Cursor"),
        ProviderMetadata(id: "copilot", displayName: "GitHub Copilot"),
        ProviderMetadata(id: "grok", displayName: "Grok CLI"),
        ProviderMetadata(id: "hermes", displayName: "Hermes Agent"),
        ProviderMetadata(id: "kiro", displayName: "Kiro"),
        ProviderMetadata(id: "pi", displayName: "Pi"),
        ProviderMetadata(id: "omp", displayName: "Oh My Prompt"),
    ]
}
