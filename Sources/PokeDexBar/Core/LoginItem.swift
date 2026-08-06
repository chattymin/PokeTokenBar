import ServiceManagement

/// 로그인 시 실행 + **크래시/비정상 종료 시 자동 재실행**(launchd KeepAlive).
///
/// 배경: `SMAppService.mainApp`(로그인아이템)은 **크래시 시 시스템이 재실행하지 않는다**(Apple 명시).
/// 그래서 KeepAlive 를 가진 LaunchAgent 로 대체한다 — launchd 가 워치독으로 동작해 앱이 비정상
/// 종료(크래시·OOM SIGKILL 등 exit≠0)되면 자동 재실행하고, **정상 종료(exit 0: 사용자 종료·업데이트)
/// 시엔 재실행하지 않는다**(`KeepAlive.SuccessfulExit=false`). ThrottleInterval 10s 로 폭주 방지.
///
/// plist 는 앱 번들 `Contents/Library/LaunchAgents/<plistName>` 에 있어야 한다(build-app.sh 가 생성).
/// 크래시-재실행은 launchd 가 프로세스를 소유해야 가능하므로, 로그인 실행도 이 에이전트가 담당한다
/// (= 로그인 실행과 크래시-재실행이 한 토글로 묶임 — 메뉴바 앱엔 자연스러운 결합).
@MainActor
enum LoginItem {
    static let plistName = "io.github.donky-ey.pokedexbar.login.plist"
    static let label = "io.github.donky-ey.pokedexbar.login"
    private static var agent: SMAppService { SMAppService.agent(plistName: plistName) }

    /// 현재 "로그인 시 실행(+크래시 자동 재실행)" 활성 여부.
    static var isEnabled: Bool { agent.status == .enabled }

    /// 토글 — 켜면 에이전트 등록(로그인 실행+KeepAlive), 끄면 해제. 실패 시 throw(호출부가 표면화).
    static func setEnabled(_ on: Bool) throws {
        if on { try agent.register() } else { try agent.unregister() }
    }
}
