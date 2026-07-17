import Foundation

/// 실행 환경 판별 — 한 곳에서만 정의해 중복 게이트의 drift(일부만 조건이 어긋나는 것)를 막는다.
enum AppEnv {
    /// 정식 `.app` 번들로 실행 중인가. 알림 전송·키체인 읽기·스프라이트 프리패치·프로덕션 로그 기록 등
    /// "실앱 전용" 부수효과의 단일 게이트 — `swift test`/로우 바이너리(dev 실행)에선 false.
    /// bundleIdentifier(Info.plist)와 경로 접미사를 함께 확인(둘 다 실앱에서만 참).
    static var isBundledApp: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }
}
