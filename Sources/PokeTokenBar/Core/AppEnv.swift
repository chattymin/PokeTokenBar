import Foundation

/// 실행 환경 판별 — 한 곳에서만 정의해 중복 게이트의 drift(일부만 조건이 어긋나는 것)를 막는다.
enum AppEnv {
    /// 정식 `.app` 번들로 실행 중인가. 알림 전송·키체인 읽기·스프라이트 프리패치·프로덕션 로그 기록 등
    /// "실앱 전용" 부수효과의 단일 게이트 — `swift test`/로우 바이너리(dev 실행)에선 false.
    /// bundleIdentifier(Info.plist)와 경로 접미사를 함께 확인(둘 다 실앱에서만 참).
    static var isBundledApp: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// `PTB_PARITY=1` — a QA/parity run where live endpoints are allowed (the same flag the parity
    /// smoke tests already use). Only ever opens a gate that `isBundledApp` keeps closed.
    static var isParityRun: Bool {
        ProcessInfo.processInfo.environment["PTB_PARITY"] == "1"
    }

    /// Lets a test drive a provider's real network code against a stubbed transport (URLProtocol, an
    /// injected URLSession). Set it in the test and reset it in `defer`.
    nonisolated(unsafe) static var allowLiveFetchForTesting = false

    /// Whether a limits provider may send the user's credentials to a live endpoint. Closed under
    /// `swift test` and for a raw `swift build` binary: a test that does not inject a stub would
    /// otherwise call Anthropic, Google or Cursor with the real login found on the machine
    /// (`~/.claude/.credentials.json`, the Antigravity token file, Cursor's `state.vscdb`).
    /// Put the check at the network boundary, not before the credential read, so the Keychain path
    /// tests keep observing real reads. `LiveCredentialCallGateTests` requires it in every provider.
    static var allowsLiveLimitsFetch: Bool {
        isBundledApp || isParityRun || allowLiveFetchForTesting
    }

    /// Whether a store may read and write its file. Always true for an injected path, which is how
    /// tests check persistence against a temporary file. A store that fell back to its default
    /// (user) path persists only in the app bundle, so `swift test` never reads or rewrites the
    /// user's real files there. Keep this rule here instead of copying it into each store.
    static func persistsToUserLocation(injectedFileURL: URL?,
                                       isBundledApp: Bool = AppEnv.isBundledApp) -> Bool {
        injectedFileURL != nil || isBundledApp
    }
}
