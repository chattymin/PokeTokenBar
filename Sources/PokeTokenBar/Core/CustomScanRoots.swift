import Darwin
import Foundation

/// Per-provider extra scan folders from Settings (#177).
///
/// One list per provider, stored under `customScanRoots.<id>`. A flat list shared
/// across readers is unsafe — `jsonlFiles(allowJSON:)` exists specifically so Gemini
/// does not ingest Claude `.meta.json`. Custom roots only *add* to curated defaults;
/// an ancestor extra is dropped so `normalizedRoots` cannot fold a hidden default
/// away (#162-B: scanning `~` with `skipsHiddenFiles` silently zeros usage).
enum CustomScanRoots {

    static func defaultsKey(for providerID: String) -> String {
        "customScanRoots.\(providerID)"
    }

    static func storedValue(for providerID: String, defaults: UserDefaults = .standard) -> String? {
        guard let raw = defaults.string(forKey: defaultsKey(for: providerID)) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : raw
    }

    /// Comma/newline split, tilde expansion, per-segment `*`/`?`/`[]` via `fnmatch`.
    /// Entries point at log roots themselves (no `/projects` suffix). Missing paths
    /// are not errors — a pattern can be registered before the instance exists.
    static func expand(_ raw: String) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for part in raw.split(whereSeparator: { $0 == "," || $0.isNewline }) {
            let pattern = part.trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty else { continue }
            let absolute = NSString(string: pattern).expandingTildeInPath
            guard absolute.hasPrefix("/") else { continue }

            var paths = [""]
            for segment in absolute.split(separator: "/").map(String.init) {
                if segment.contains("*") || segment.contains("?") || segment.contains("[") {
                    var next: [String] = []
                    for base in paths {
                        guard let names = try? fm.contentsOfDirectory(atPath: base.isEmpty ? "/" : base)
                        else { continue }
                        next.append(contentsOf: names.sorted()
                            .filter { fnmatch(segment, $0, 0) == 0 }
                            .map { base + "/" + $0 })
                    }
                    paths = next
                } else {
                    paths = paths.map { $0 + "/" + segment }
                }
            }
            if paths == [""] { paths = ["/"] }
            var isDir: ObjCBool = false
            out.append(contentsOf: paths
                .filter { fm.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue }
                .map { URL(fileURLWithPath: $0) })
        }
        return out
    }

    /// Curated defaults first; extras that would evict a default are dropped; then fold.
    static func union(defaults: [URL], extraRaw: String?) -> [URL] {
        let protected = LocalUsageReader.normalizedRoots(defaults)
        guard let extraRaw else { return protected }
        let added = expand(extraRaw).filter { extra in
            !wouldEvict(extra, protected: protected)
        }
        return LocalUsageReader.normalizedRoots(protected + added)
    }

    /// Folded extras that are not one of the curated defaults — the number Settings shows.
    static func survivingExtraCount(defaults: [URL], extraRaw: String) -> Int {
        let protected = Set(LocalUsageReader.normalizedRoots(defaults).map(normalizedPath))
        let united = union(defaults: defaults, extraRaw: extraRaw)
        return united.filter { !protected.contains(normalizedPath($0)) }.count
    }

    /// Production curated roots for the Settings match count. Uses the same
    /// env/home resolution as the readers so the number matches what will be scanned.
    static func curatedRoots(for providerID: String) -> [URL] {
        switch providerID {
        case "claude_code":
            return LocalUsageReader.computeClaudeProjectRoots(customRootsValue: nil)
        case "codex":
            return LocalUsageReader.codexSessionRoots(customRootsValue: nil)
        case "gemini":
            return LocalUsageReader.geminiScanRoots(customRootsValue: nil)
        case "grok":
            return LocalUsageReader.grokSessionRoots(customRootsValue: nil)
        case "antigravity":
            return LocalAntigravityUsageReader.resolvedRoots(customRootsValue: nil)
        case "opencode":
            return LocalAdditionalUsageReader.openCodeRoots(customRootsValue: nil)
        case "hermes":
            return LocalAdditionalUsageReader.hermesRoots(customRootsValue: nil)
        case "cursor":
            return LocalAdditionalUsageReader.cursorRoots(customRootsValue: nil)
        case "copilot":
            return LocalAdditionalUsageReader.copilotRoots(customRootsValue: nil)
        case "kiro":
            return LocalAdditionalUsageReader.kiroRoots(customRootsValue: nil)
        case "pi":
            return CustomScanRoots.union(
                defaults: LocalUsageReader.computePiSessionRoots(), extraRaw: nil)
        default:
            return []
        }
    }

    private static func wouldEvict(_ extra: URL, protected: [URL]) -> Bool {
        let extraPath = normalizedPath(extra)
        return protected.contains { def in
            let d = normalizedPath(def)
            if extraPath == "/" { return d != extraPath }
            return d != extraPath && d.hasPrefix(extraPath + "/")
        }
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
    }
}
