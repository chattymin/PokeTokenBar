import Foundation

/// 크래시 한 건의 스냅샷. **하나만 들고 있는다** — 이력을 쌓는 것이 목적이 아니다.
struct LastCrashRecord: Codable, Sendable, Equatable {
    let at: Date
    let version: String
    /// 시그널 핸들러가 crash.log 에 남긴 줄들.
    let crashLines: [String]
    /// 죽기 직전 세션의 빵부스러기.
    let breadcrumbs: [String]
    /// macOS 가 남긴 `.ips` 에서 뽑은 스택 요약. 없으면 빈 배열 — 리포트가 아직 안 써졌거나
    /// 지워졌을 수 있다.
    var stack: [String] = []
    /// 사용자가 제보했거나 배너를 닫았나. 새 크래시가 오면 다시 false 가 된다.
    var acknowledged: Bool
}

/// 마지막 크래시를 **다음 크래시가 덮을 때까지** 보존한다.
///
/// **왜 빵부스러기 링을 그냥 읽으면 안 되나.** 링은 기동과 함께 비워지고 **지금 세션**의 행동으로
/// 다시 찬다. 제보 버튼은 며칠 뒤에 눌릴 수 있고, 그때 `Breadcrumbs.read()` 를 읽으면 이슈에
/// `tab: settings` 만 담기고 정작 필요한 `detail open: species=133` 은 안 담긴다. 메인 로그를
/// 훑어 되찾는 것도 안 된다 — 2MB 회전으로 이미 밀려나 있을 수 있다.
///
/// 이 실수가 위험한 이유는 이슈가 *비어 보이지 않고* **그럴듯하게 잘못 채워지기** 때문이다.
/// 눈으로는 안 걸린다.
enum LastCrash {
    /// 테스트가 갈아끼운다 — `Breadcrumbs.fileURL` 과 같은 이유.
    nonisolated(unsafe) static var fileURL: URL = defaultURL()

    static func load() -> LastCrashRecord? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        // 손댄 파일이나 중간에 끊긴 write 로 깨져 있어도 앱이 죽지 않는다 — 없는 것으로 본다.
        return try? JSONDecoder().decode(LastCrashRecord.self, from: data)
    }

    static func save(_ record: LastCrashRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 사용자가 제보했거나 배너를 닫았다 — 같은 크래시로 다시 조르지 않는다.
    static func acknowledge() {
        guard var record = load() else { return }
        record.acknowledged = true
        save(record)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func defaultURL() -> URL {
        guard AppEnv.isBundledApp,
              let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("PokeDexBar.last-crash.json")
        }
        let dir = logs.appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(AppEnv.storageName).last-crash.json")
    }
}
