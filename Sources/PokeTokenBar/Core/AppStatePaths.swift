import Foundation

/// Application Support state directory for PokeTokenBar files.
/// `PTB_STATE_DIR` overrides the default for development/QA isolation.
enum AppStatePaths {
    static func directory() -> URL {
        let override = (ProcessInfo.processInfo.environment["PTB_STATE_DIR"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dir: URL
        if !override.isEmpty {
            dir = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PokeTokenBar")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 평문 자격증명(session-key.json·antigravity-credential.json)이 여기 산다 — 기본 0755 면
        // 같은 기기의 다른 로컬 사용자가 나열할 수 있다. 생성 직후 매번 좁힌다(이미 만들어진 것도 포함).
        CredentialFileProtection.restrictDirectory(dir)
        return dir
    }
}
