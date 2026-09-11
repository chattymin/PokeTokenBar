import Foundation

/// Application Support state directory for PokeTokenBar files.
/// `PTB_STATE_DIR` overrides the default for development/QA isolation.
enum AppStatePaths {
    /// Finder/menu-bar name and on-disk folder. Bundled apps use `CFBundleName` so a side-by-side
    /// build (e.g. `PokeTokenBar v2.0` / `PokeTokenBar v3`) does not share saves with the installed
    /// copy. Tests and `swift run` stay on `PokeTokenBar`.
    static var productFolderName: String {
        if AppEnv.isBundledApp,
           let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "PokeTokenBar"
    }

    static func directory() -> URL {
        let override = (ProcessInfo.processInfo.environment["PTB_STATE_DIR"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dir: URL
        if !override.isEmpty {
            dir = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(productFolderName)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
