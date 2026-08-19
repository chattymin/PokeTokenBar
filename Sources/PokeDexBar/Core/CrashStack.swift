import Foundation

/// macOS 가 남기는 크래시 리포트(`.ips`)에서 **죽은 스레드의 스택**을 뽑아 온다.
///
/// **왜 필요한가.** 우리 로그에는 `[CRASH] fatal signal SIGABRT` 한 줄뿐이라 어디서 죽었는지
/// 알 방법이 없다. macOS 는 같은 크래시에 대해 심볼·소스파일·줄번호까지 담긴 파일을 이미
/// 쓰고 있는데(실측 확인), 그걸 안 읽고 있었다.
///
/// 첫 제보(2026-08-19)가 정확히 이것 때문에 미궁이었다 — SIGABRT 라는 사실만으로는 후보를
/// 좁힐 수 없었고, 결국 코드를 눈으로 훑어 찾아야 했다.
enum CrashStack {
    /// 리포트가 쌓이는 자리. 사용자 도메인만 본다(시스템 위치는 권한이 없다).
    ///
    /// 테스트가 갈아끼운다 — `Breadcrumbs.fileURL` 과 같은 이유로, 실제 디렉터리에 묶여 있으면
    /// **고르는 규칙(이름·나이)을 검사할 방법이 없다.**
    nonisolated(unsafe) static var directory: URL =
        AppEnv.userDirectory(.libraryDirectory).appendingPathComponent("Logs/DiagnosticReports")

    /// 스택에서 남길 최대 프레임 수. 위쪽 몇 개면 원인이 드러나고, 그 아래는 런루프 잡음이다.
    static let maxFrames = 24

    /// 이 앱의 가장 최근 리포트에서 요약을 뽑는다. 없거나 너무 오래됐으면 nil.
    ///
    /// **`maxAge` 로 거른다** — 몇 달 전 리포트를 이번 크래시라고 붙이면 진단이 거짓말을 한다.
    static func latestSummary(appName: String = AppEnv.storageName, now: Date = Date(),
                              maxAge: TimeInterval = 3600) -> [String]? {
        guard let url = latestReport(appName: appName, now: now, maxAge: maxAge) else { return nil }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return summary(fromIPS: text)
    }

    /// 이름이 맞고 충분히 최근인 리포트 중 가장 새것.
    static func latestReport(appName: String, now: Date, maxAge: TimeInterval) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.pathExtension == "ips" }
            // 개발 빌드는 "PokeDexBar Dev" 라 접두로 본다. 다른 앱의 리포트를 붙이면 안 된다.
            .filter { $0.lastPathComponent.hasPrefix(appName) }
            .compactMap { url -> (URL, Date)? in
                guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate else { return nil }
                return (url, date)
            }
            .filter { now.timeIntervalSince($0.1) <= maxAge && $0.1 <= now }
            .max { $0.1 < $1.1 }?.0
    }

    /// `.ips` 본문에서 사람이 읽을 요약을 만든다.
    ///
    /// 형식은 **첫 줄이 헤더 JSON, 나머지가 본문 JSON** 이다(실측). 본문의 `faultingThread` 가
    /// 죽은 스레드의 번호이고, 그 스레드의 프레임에는 대개 `symbol` 과 `sourceFile`·`sourceLine`
    /// 이 들어 있다.
    static func summary(fromIPS text: String) -> [String]? {
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let body = try? JSONSerialization.jsonObject(with: Data(parts[1].utf8)),
              let root = body as? [String: Any] else { return nil }

        var lines: [String] = []
        if let exception = root["exception"] as? [String: Any] {
            let type = exception["type"] as? String ?? "?"
            let signal = exception["signal"] as? String ?? "?"
            lines.append("exception: \(type) / \(signal)")
        }
        if let termination = root["termination"] as? [String: Any],
           let indicator = termination["indicator"] as? String {
            lines.append("termination: \(indicator)")
        }

        guard let threads = root["threads"] as? [[String: Any]] else {
            return lines.isEmpty ? nil : lines
        }
        // `faultingThread` 가 없으면 `triggered` 표시를 찾는다 — 둘 중 하나는 늘 있다.
        let index = (root["faultingThread"] as? Int)
            ?? threads.firstIndex { ($0["triggered"] as? Bool) == true }
        guard let index, threads.indices.contains(index),
              let frames = threads[index]["frames"] as? [[String: Any]] else {
            return lines.isEmpty ? nil : lines
        }

        lines.append("crashed thread \(index):")
        for frame in frames.prefix(maxFrames) {
            let symbol = frame["symbol"] as? String ?? "?"
            if let file = frame["sourceFile"] as? String, let line = frame["sourceLine"] as? Int {
                lines.append("  \(symbol)  (\(file):\(line))")
            } else {
                lines.append("  \(symbol)")
            }
        }
        return lines
    }
}
