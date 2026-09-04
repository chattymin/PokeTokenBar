import Foundation

/// Application Support state directory for PokeTokenBar files.
/// `PTB_STATE_DIR` overrides the default for development/QA isolation.
enum AppStatePaths {
    static func directory() -> URL {
        let dir = overrideDirectory("PTB_STATE_DIR") ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// iCloud Drive 안의 세이브 백업 폴더. `PTB_ICLOUD_DIR` 은 두 번째 기기 없이 동기화를 확인하기
    /// 위한 개발/QA override 다(`PTB_STATE_DIR` 과 같은 규약).
    ///
    /// 여기 두는 이유는 위치가 아니라 **테스트 게이트**다 — `UsageEnvironmentTests`
    /// `.testNoProviderReadsUsageLocationEnvDirectly` 가 `Sources/` 를 스캔해 프로세스 환경 직독을
    /// 실패시키고, 그 허용 목록에 이 파일이 이미 들어 있다. 새 파일에서 읽으면 그 스캔에 걸린다.
    ///
    /// `directory()` 와 달리 **폴더를 만들지 않는다.** 동기화를 켜지 않은 사용자의 iCloud Drive 에
    /// 빈 폴더를 남기지 않기 위해서다 — 생성은 실제로 쓰는 시점(`ICloudSaveMirror`)에서 한다.
    /// 반환 nil = iCloud Drive 가 꺼져 있음(그 경로 자체가 없다).
    static func iCloudDirectory() -> URL? {
        if let override = overrideDirectory("PTB_ICLOUD_DIR") {
            return override.appendingPathComponent("PokeTokenBar")
        }
        // 엔타이틀먼트가 없으므로 `FileManager.url(forUbiquityContainerIdentifier:)` 는 쓸 수 없다
        // (프로비저닝 프로파일이 필요해 자체서명 빌드에서는 nil 을 돌려준다). 샌드박스가 아니라서
        // iCloud Drive 실경로에 그냥 쓰면 되고, 그 폴더의 존재가 곧 "iCloud Drive 켜짐"이다.
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return root.appendingPathComponent("PokeTokenBar")
    }

    private static func overrideDirectory(_ name: String) -> URL? {
        let value = (ProcessInfo.processInfo.environment[name] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : URL(fileURLWithPath: value, isDirectory: true)
    }
}
