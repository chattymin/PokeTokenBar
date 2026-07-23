#if os(Windows)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession/URLRequest live here on Windows
#endif
import WinSDK

/// Windows update check — the counterpart to the macOS `UpdateChecker`.
///
/// macOS installs via Homebrew, so its checker can run `brew upgrade`. Windows has no brew:
/// this detects a newer public GitHub release and, on "apply", downloads and runs the installer,
/// falling back to opening the release page in the browser if the download can't complete.
///
/// `normalize` accepts `v<semver>` / `win-<semver>` / bare `<semver>` tags interchangeably.
enum WindowsUpdate {
    /// Baked build version (Windows has no Info.plist bundle to read `CFBundleShortVersionString`).
    /// Compared against the latest release tag; bump it alongside each Windows release.
    static let currentVersion = "2.4.5"
    static let repo = "chattymin/PokeTokenBar"

    struct Available: Sendable, Equatable { let version: String; let url: String }

    /// Query the latest release; return it only when strictly newer than `currentVersion`.
    /// Returns nil when up to date, or on any network/parse failure.
    static func check() async -> Available? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("PokeTokenBar-Windows", forHTTPHeaderField: "User-Agent")   // GitHub API requires a UA
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
}
#endif
