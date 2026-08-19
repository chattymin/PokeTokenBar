import AppKit

/// 제보 동작 — 진단을 조립해 GitHub 이슈를 열거나 클립보드에 담는다.
///
/// 설정 화면과 크래시 배너가 **같은 텍스트**를 써야 하므로 여기 하나로 모은다. 두 자리가 각자
/// 조립하면 배너로 온 제보와 설정으로 온 제보가 서로 다른 내용을 담게 된다.
///
/// **앱이 자동으로 아무것도 보내지 않는다.** 이슈 작성 페이지를 열 뿐이고, 제출은 사용자가
/// 내용을 보고 누른다.
@MainActor
enum ProblemReport {
    /// 테스트가 사용자의 실제 클립보드를 안 덮도록 주입 가능하게 둔다.
    static var pasteboard: NSPasteboard = .general
    /// 테스트가 실제 브라우저를 안 열도록 주입 가능하게 둔다.
    static var openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    /// 붙여넣을 전문. **자르지 않는다** — 이슈 URL 만 길이 제한이 있다.
    static func text(version: String, player: PlayerStore) -> String {
        Diagnostics.report(version: version,
                           os: ProcessInfo.processInfo.operatingSystemVersionString,
                           lastCrash: LastCrash.load(),
                           boxCount: player.state.box.count,
                           dexCount: player.state.dex.count)
    }

    /// 전문을 클립보드에. 이슈가 잘렸거나 다른 데 붙이고 싶을 때의 탈출구다.
    static func copy(version: String, player: PlayerStore) {
        pasteboard.clearContents()
        pasteboard.setString(text(version: version, player: player), forType: .string)
        LastCrash.acknowledge()
    }

    /// GitHub 새 이슈 작성 페이지를 연다. 실패하면 안내 문구를 돌려준다(화면이 그대로 띄운다).
    static func openIssue(version: String, player: PlayerStore, l: L) -> String? {
        let body = text(version: version, player: player)
        guard let made = Diagnostics.issueURL(title: l.reportIssueTitle(version), body: body) else {
            return l.reportBrowserFallback("https://github.com/\(Diagnostics.repo)/issues/new")
        }
        LastCrash.acknowledge()
        guard openURL(made.url) else { return l.reportBrowserFallback(made.url.absoluteString) }
        return nil
    }
}
