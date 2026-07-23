#if os(Windows)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession/URLRequest live here on Windows
#endif
import WinSDK

/// Windows update check — the counterpart to the macOS `UpdateChecker`.
///
/// macOS installs via Homebrew, so its checker can run `brew upgrade`. Windows has no brew:
/// this only *detects* a newer release (GitHub Releases API on the user's fork) and, on "apply",
/// opens the release page in the default browser for a manual download of the portable zip.
///
/// Release tags are `win-<semver>` (e.g. `win-2.4.5`) so they don't collide with the upstream
/// macOS `vX.Y.Z` tags that the fork inherited.
///
/// Private-repo note: `releases/latest` returns 404 without auth on a private repo. A token is sent
/// as a Bearer header when one can be found locally (see `authToken` — env override, then the user's
/// own `gh` / git-credential login), so collaborators get update checks with no shared token shipped
/// in the app; a public releases channel would need none at all.
enum WindowsUpdate {
    /// Baked build version (Windows has no Info.plist bundle to read `CFBundleShortVersionString`).
    ///
    /// **Windows versioning scheme: `MAJOR.MINOR.PATCH.WINFIX`** — the first three segments track the
    /// upstream macOS base version (e.g. 2.4.4); the 4th is a Windows-only build counter, bumped for
    /// each Windows fix/release between upstream bumps (the port needs far more frequent patches than
    /// the shared core). On merging a newer upstream base, roll the first three and reset the 4th to 0
    /// (e.g. base 2.4.5 → `2.4.5.0`, `2.4.5.1`, …). `isNewer`/`normalize` already handle N segments
    /// (shorter side zero-padded), so `2.4.4.1` > `2.4.4` (the initial 3-segment `win-2.4.4` release).
    /// Bump this together with each `win-<version>` release tag.
    static let currentVersion = "2.4.5.15"
    static let repo = "jhpark3975/PokeTokenBar"

    struct Available: Sendable, Equatable { let version: String; let url: String }

    /// Query the latest release; return it only when strictly newer than `currentVersion`.
    /// Returns nil when up to date, on any network/parse failure, or on a private-repo 404 (no token).
    static func check() async -> Available? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("PokeTokenBar-Windows", forHTTPHeaderField: "User-Agent")   // GitHub API requires a UA
        if let token = authToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let html = json["html_url"] as? String,
              // The URL is handed to ShellExecuteW → only allow https github.com (no scheme hijack).
              let htmlURL = URL(string: html), htmlURL.scheme == "https", htmlURL.host == "github.com"
        else { return nil }
        let latest = normalize(tag)
        // Respect a "Later" (skip) choice — don't resurface a version the user dismissed.
        let skipped = UserDefaults.standard.string(forKey: "skippedUpdateVersion")
        guard isNewer(latest, than: currentVersion), latest != skipped else { return nil }
        return Available(version: latest, url: html)
    }

    /// Open the release page in the default browser (manual download — no brew on Windows).
    static func openReleasePage(_ urlString: String) {
        _ = urlString.withCString(encodedAs: UTF16.self) { p in
            ShellExecuteW(nil, nil, p, nil, nil, 1)   // SW_SHOWNORMAL
        }
    }

    /// `win-2.4.5` / `v2.4.5` / `2.4.5` → `2.4.5`.
    static func normalize(_ tag: String) -> String {
        var s = Substring(tag)
        if s.hasPrefix("win-") { s = s.dropFirst(4) }
        if s.hasPrefix("v") { s = s.dropFirst() }
        return String(s)
    }

    /// Numeric semver compare — is `a` strictly newer than `b`? ("2.4.10" > "2.4.9").
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// A GitHub token to authenticate the (private-repo) release check, tried in order:
    /// 1. an explicit env override (`PTB_UPDATE_TOKEN` / `GH_TOKEN` / `GITHUB_TOKEN`);
    /// 2. the GitHub CLI's stored token (`gh auth token`);
    /// 3. the git credential helper (Git Credential Manager → Windows Credential Manager).
    ///
    /// This lets colleagues who are collaborators on the private repo get update checks using the
    /// GitHub login they already have locally — no shared token is ever shipped in the app. Steps 2–3
    /// run **non-interactively**: a missing credential fails silently (returns nil) rather than popping
    /// a login window (same rule as the macOS keychain path — never prompt on an automatic poll).
    private static func authToken() -> String? {
        for key in ["PTB_UPDATE_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"] {
            if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty { return v }
        }
        if let t = runForToken("gh auth token")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        // Force non-interactive so Git Credential Manager can't pop a login dialog on a background poll.
        setEnv("GIT_TERMINAL_PROMPT", "0"); setEnv("GCM_INTERACTIVE", "never")
        if let out = runForToken("git -c credential.interactive=false credential fill",
                                 stdin: "protocol=https\nhost=github.com\n\n"),
           let pw = out.split(whereSeparator: \.isNewline)
            .first(where: { $0.hasPrefix("password=") })?.dropFirst("password=".count),
           !pw.isEmpty { return String(pw) }
        return nil
    }

    /// Run a command (CREATE_NO_WINDOW), optionally feed stdin, and return its stdout — or nil on
    /// launch failure / timeout / non-zero exit. Short 5s cap; both credential tools return instantly.
    private static func runForToken(_ commandLine: String, stdin: String? = nil) -> String? {
        let tmp = FileManager.default.temporaryDirectory
        let outURL = tmp.appendingPathComponent("ptb-cred-\(UUID().uuidString).out")
        let errURL = tmp.appendingPathComponent("ptb-cred-\(UUID().uuidString).err")
        defer { try? FileManager.default.removeItem(at: outURL); try? FileManager.default.removeItem(at: errURL) }
        guard let proc = WindowsProcess(commandLine: commandLine, stdoutPath: outURL.path, stderrPath: errURL.path),
              proc.launched else { return nil }
        defer { proc.cleanup() }
        if let stdin { proc.writeStdin(Data(stdin.utf8)) }
        proc.closeStdin()
        guard proc.waitFor(5) else { proc.terminate(); return nil }
        guard proc.exitCode == 0 else { return nil }
        return try? String(contentsOf: outURL, encoding: .utf8)
    }

    private static func setEnv(_ name: String, _ value: String) {
        _ = name.withCString(encodedAs: UTF16.self) { n in
            value.withCString(encodedAs: UTF16.self) { v in SetEnvironmentVariableW(n, v) }
        }
    }
}
#endif
