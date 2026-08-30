import Foundation

/// 실행 환경 판별 — 한 곳에서만 정의해 중복 게이트의 drift(일부만 조건이 어긋나는 것)를 막는다.
enum AppEnv {
    /// 정식 `.app` 번들로 실행 중인가. 알림 전송·키체인 읽기·스프라이트 프리패치·프로덕션 로그 기록 등
    /// "실앱 전용" 부수효과의 단일 게이트 — `swift test`/로우 바이너리(dev 실행)에선 false.
    /// bundleIdentifier(Info.plist)와 경로 접미사를 함께 확인(둘 다 실앱에서만 참).
    static var isBundledApp: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// `PTB_PARITY=1` 로 지정된 QA/파리티 실행 — 라이브 엔드포인트 검증(LocalUsageParityTests)처럼
    /// 실 IO 가 *허용*되는 모드. isBundledApp 게이트를 여는 방향으로만 쓴다(닫는 방향 아님).
    /// CompanionStore 의 PTB_STATE_DIR 과 같은 개발/QA 전용 플래그 부류라 여기서 직독한다.
    static var isParityRun: Bool {
        ProcessInfo.processInfo.environment["PTB_PARITY"] == "1"
    }

    /// 사용자 상태 파일(Application Support 등)을 실제로 읽고 쓸 것인가.
    ///
    /// 경로를 주입받았으면 항상 참 — 테스트가 격리된 임시 파일로 지속성을 검증하는 통로다.
    /// 주입이 없어 *기본(사용자) 경로*로 떨어졌다면 실앱에서만 참이다. `swift test` 는 번들이
    /// 아니므로 거짓이 되고, 그래서 스위트가 사용자의 실제 파일을 읽거나 덮어쓰지 않는다.
    ///
    /// 이 판정을 스토어마다 복사하지 않는다 — 한 곳이 고쳐지고 다른 곳이 남는 게 이 부류의
    /// 전형적인 재발 경로다(defect-log "Application Support 기본 경로" 항목).
    static func persistsToUserLocation(injectedFileURL: URL?,
                                       isBundledApp: Bool = AppEnv.isBundledApp) -> Bool {
        injectedFileURL != nil || isBundledApp
    }
}
