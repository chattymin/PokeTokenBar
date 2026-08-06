import Foundation

/// 실행 환경 판별 — 한 곳에서만 정의해 중복 게이트의 drift(일부만 조건이 어긋나는 것)를 막는다.
enum AppEnv {
    /// 정식 `.app` 번들로 실행 중인가. 알림 전송·키체인 읽기·스프라이트 프리패치·프로덕션 로그 기록 등
    /// "실앱 전용" 부수효과의 단일 게이트 — `swift test`/로우 바이너리(dev 실행)에선 false.
    /// bundleIdentifier(Info.plist)와 경로 접미사를 함께 확인(둘 다 실앱에서만 참).
    static var isBundledApp: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    #if DEBUG
    /// 테스트 전용 버전 덮어쓰기. `swift test` 의 `Bundle.main` 은 xctest 러너라 앱과 무관한 값을
    /// 돌려준다 — 설정 화면을 그대로 찍는 스크린샷 생성기가 릴리스 버전을 넣을 수 있게 하는 seam.
    /// 릴리스 빌드에는 존재하지 않는다.
    nonisolated(unsafe) static var appVersionOverride: String?
    #endif

    /// 저장 공간 이름 — Application Support 디렉터리와 로그 파일 이름의 단일 소스.
    ///
    /// 개발 빌드(`PokeDexBar Dev`)를 정식 설치본과 **나란히 깔고 쓰기 위해서** 있다. 둘이 같은
    /// 이름을 쓰면 세이브·사용량 캐시·로그를 서로 덮어써서, 한쪽에서 시험 삼아 한 일이 다른 쪽
    /// 진행에 그대로 섞인다. `CFBundleName` 에서 뽑으므로 정식 빌드는 예전과 같은 "PokeDexBar" 를
    /// 그대로 쓰고(기존 세이브 경로 유지), 개발 빌드만 "PokeDexBarDev" 로 갈라진다.
    static var storageName: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        guard isBundledApp, let name else { return "PokeDexBar" }
        return name.replacingOccurrences(of: " ", with: "")
    }

    /// 이 빌드의 Application Support 디렉터리. 없으면 만든다.
    static func supportDirectory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(storageName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 개발 빌드인가 — 메뉴바에 표식을 붙여 정식 설치본과 눈으로 구분하기 위해서만 쓴다.
    static var isDevBuild: Bool { storageName != "PokeDexBar" }

    /// 표시·전송용 앱 버전(`CFBundleShortVersionString`). 이 키를 읽는 곳이 여럿이라 여기 하나로 모은다.
    /// 번들이 아닌 실행(테스트·로우 바이너리)에서는 의미 있는 값이 없으므로 호출부가 폴백을 정한다.
    static var appVersion: String? {
        #if DEBUG
        if let appVersionOverride { return appVersionOverride }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}
