import Foundation

/// 제보에 붙일 진단 텍스트와 GitHub 이슈 URL 조립. **순수 함수만 있다** — 부수효과(브라우저
/// 열기·클립보드)는 화면 쪽에 둔다.
enum Diagnostics {
    static let repo = "donky-ey/PokeDexBar"

    /// 조립된 URL 이 넘지 않아야 하는 길이.
    ///
    /// URL 은 실무상 8KB 안쪽이 안전한데, 한글은 percent-encoding 으로 세 배가 된다. 여유를 두고
    /// 6,000 자로 잡고 **인코딩한 뒤** 잰다 — 인코딩 전 길이로 판정하면 한도를 넘는다.
    static let urlLimit = 6000

    // MARK: 경로 지우기

    /// 홈 디렉터리 경로를 `~` 로 바꾼다.
    ///
    /// GitHub 이슈는 공개된 자리다. 로그 곳곳에 `/Users/<이름>/…` 이 들어가고, 그대로 붙으면
    /// 실명이 샌다. **경로만** 지운다 — 넓게 잡으면 진단이 통째로 뭉개져 이슈가 쓸모없어진다.
    static func redact(_ text: String, home: String = NSHomeDirectory()) -> String {
        guard !home.isEmpty, home != "/" else { return text }
        return text.replacingOccurrences(of: home, with: "~")
    }

    // MARK: 리포트 본문

    /// 제보 본문. **세이브 내용은 안 들어간다** — 규모(개수)만 넣는다.
    static func report(version: String, os: String, lastCrash: LastCrashRecord?,
                       boxCount: Int, dexCount: Int) -> String {
        var lines: [String] = [
            "### Environment",
            "- PokeDexBar: \(version)",
            "- macOS: \(os)",
            "- Box: \(boxCount) / Dex: \(dexCount)",
            "",
            "### Last session",
        ]

        if let crash = lastCrash {
            let when = ISO8601DateFormatter().string(from: crash.at)
            lines.append("- **Ended unexpectedly** (detected \(when), app \(crash.version))")
            if !crash.crashLines.isEmpty {
                lines.append("")
                lines.append("```")
                lines.append(contentsOf: crash.crashLines)
                lines.append("```")
            }
            // **스택이 제일 먼저다.** 잘릴 때 뒤에서부터 덜어내므로, 결론을 내는 데 가장
            // 중요한 것이 앞에 있어야 한다(빵부스러기보다 스택이 훨씬 결정적이다).
            if !crash.stack.isEmpty {
                lines.append("")
                lines.append("### Crash stack (from macOS)")
                lines.append("```")
                lines.append(contentsOf: crash.stack)
                lines.append("```")
            }
            lines.append("")
            lines.append("### What the app was doing")
            lines.append("```")
            lines.append(crash.breadcrumbs.isEmpty ? "(none recorded)"
                         : crash.breadcrumbs.joined(separator: "\n"))
            lines.append("```")
        } else {
            // 크래시가 아닌 제보(기능 문의)도 이 경로로 온다. "정상"을 조용히 생략하면
            // 읽는 사람이 이 이슈가 크래시인지 아닌지 구분할 수 없다.
            lines.append("- No unexpected shutdown on record.")
        }

        return redact(lines.joined(separator: "\n"))
    }

    // MARK: GitHub 이슈 URL

    /// 새 이슈 작성 페이지 URL. 길면 **본문 뒤에서부터** 줄여 한도에 맞춘다.
    ///
    /// 앞을 먹으면 안 된다 — 버전과 크래시 여부가 앞에 있고, 그게 없으면 이슈가 무의미하다.
    static func issueURL(repo: String = repo, title: String, body: String,
                         limit: Int = urlLimit) -> (url: URL, truncated: Bool)? {
        let base = "https://github.com/\(repo)/issues/new"

        func assemble(_ text: String) -> URL? {
            var components = URLComponents(string: base)
            components?.queryItems = [
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "body", value: text),
            ]
            return components?.url
        }

        if let url = assemble(body), url.absoluteString.count <= limit {
            return (url, false)
        }

        // **안내를 붙인 상태로** 한도를 만족할 때까지 줄인다. 붙이기 전 길이로 판정하면
        // 안내가 붙는 순간 한도를 넘는다.
        let note = "\n\n_(truncated — full log: Settings → Show log file)_"
        var lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while !lines.isEmpty {
            lines.removeLast()
            guard let url = assemble(lines.joined(separator: "\n") + note) else { return nil }
            if url.absoluteString.count <= limit { return (url, true) }
        }

        // 본문을 다 덜어내도 안 되면 제목만이라도 보낸다.
        return assemble("").map { ($0, true) }
    }
}
