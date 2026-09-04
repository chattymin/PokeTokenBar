import Foundation
import Observation

/// iCloud Drive 세이브 백업 — 이 Mac 의 진행을 iCloud Drive 폴더에 자동으로 복사해 두고,
/// 다른 Mac 이 **사용자가 명시적으로 누를 때** 그걸 복원한다.
///
/// ## 왜 CloudKit 이 아닌 그냥 파일인가
/// CloudKit·`NSUbiquitousKeyValueStore`·`FileManager.url(forUbiquityContainerIdentifier:)` 는 모두
/// 엔타이틀먼트를 요구하고, macOS 는 그걸 **유료 개발자 팀의 프로비저닝 프로파일**로 검증한다.
/// 이 앱의 서명 신원은 `scripts/create-signing-cert.sh` 가 만드는 자체서명 인증서라(팀 ID 없음)
/// 그 엔타이틀먼트를 실을 수 없고, 실어도 조용히 no-op 가 된다. 대신 이 앱은 **샌드박스가 아니라서**
/// `~/Library/Mobile Documents/com~apple~CloudDocs/` 에 그냥 쓸 수 있고 iCloud Drive 데몬이 그걸
/// 동기화한다. 엔타이틀먼트 0개로 되는 유일한 경로다.
///
/// ## 왜 자동 병합이 아닌가
/// `CompanionState` 에는 병합할 수 없는 필드가 있다 — `active`(포켓몬은 하나), `eggTier`,
/// `pendingHatchID` 는 단일값이고 `inventory`·`spentTokens` 는 개수라 델타 추적 없이 합치면
/// 이중지출이 된다. 원격 세이브를 자동 적용하면 `defect-log.md`(프로세스·인스턴스)가 이미 기록한
/// "저장이 last-writer-wins 가 되고 진화·사용량이 조용히 덮인다"를 **기기 사이에서**, 그것도
/// `SingleInstance` 같은 방어 없이 재생산한다. 그래서 복원은 항상 사용자 동작이고 기존 불러오기
/// 확인창·백업 경로를 그대로 지난다.
///
/// ## 왜 기기마다 파일이 따로인가
/// 두 Mac 이 같은 파일명을 쓰면 iCloud 가 충돌 사본(`save 2.json`)을 만든다. 기기별 파일이면 충돌이
/// **구조적으로** 불가능하고, 복원 목록이 "어느 Mac 의 세이브인지"를 말해 줄 수 있다.
@MainActor
@Observable
final class ICloudSaveMirror {
    /// 동기화 켜짐 여부(기본 꺼짐 — 게임 상태가 나가는 새 경로라 옵트인이어야 한다).
    static let enabledKey = "iCloudSyncEnabled"
    /// 이 Mac 의 파일명을 정하는 안정 식별자. 사용자가 Mac 이름을 바꿔도 파일이 갈라지지 않게
    /// 표시용 이름(`SaveEnvelope.sourceDevice`)과 분리한다.
    static let deviceIDKey = "iCloudDeviceID"

    nonisolated static let fileNamePrefix = "save-"
    nonisolated static let fileNameSuffix = ".json"

    /// 쓰기 최소 간격. `CompanionStore.save()` 는 120초 새로고침마다 무조건 호출되므로 그대로 따라
    /// 쓰면 사용량이 도는 동안 하루 최대 720회, 수백 KB 씩 올라간다.
    ///
    /// 별도의 트레일링 타이머는 두지 않는다 — 그 120초 하트비트 자체가 트레일링 역할을 해서, 창 안에
    /// 생긴 변경은 창이 끝난 뒤 다음 틱에 올라간다.
    ///
    /// ponytail: 변경 후 5분 안에 앱을 끄면 그 변경은 다음 실행의 첫 `save()` 까지 안 올라간다.
    /// 로컬 파일이 원본이고 백업이 한 창 + 한 번의 실행만큼 늦는 것뿐이라 감수한다. 이 앱에는
    /// `applicationWillTerminate` 자체가 없고(`PokeTokenBarApp.swift`), 이것 때문에 만들 값은 없다.
    /// 더 촘촘해야 하면 종료 훅이 아니라 이 상수를 내린다.
    static let minimumWriteInterval: TimeInterval = 300

    /// 복원 목록의 한 줄 — 다른 Mac 이 남긴 세이브 하나.
    ///
    /// 봉투를 **그대로 들고 있는다.** 목록을 만들 때 이미 읽고 검증했으므로, 복원 시점에 파일을 다시
    /// 읽으면 코드만 늘고 위험이 붙는다 — 그 재읽기는 메인 액터에서 일어나고, 그 사이 파일이 evict
    /// 되면 다운로드만큼 UI 가 멈춘다. 목록 만들기는 이미 액터 밖이다.
    struct RemoteSave: Identifiable, Sendable {
        var id: String { url.path }
        var url: URL
        var envelope: SaveEnvelope

        var deviceName: String { envelope.sourceDevice }
        var exportedAt: Date { envelope.exportedAt }
        var summary: SaveSummary { SaveSummary(state: envelope.state) }
    }

    private let directory: URL?
    private let defaults: UserDefaults
    /// 마지막으로 올린 상태의 정규 인코딩. 변경 없는 틱을 걸러내는 게이트.
    private var lastMirroredState: Data?
    private var lastMirroredAt: Date?

    /// 기본 디렉터리를 `AppEnv.isBundledApp` 뒤에 두는 건 **테스트 격리**다. 이게 없으면 xctest 가
    /// 개발자의 실제 `UserDefaults` 토글과 실제 iCloud Drive 폴더를 집어, 스위트를 도는 것만으로
    /// 본인 세이브 백업을 덮어쓴다. 주입 생성자를 쓰는 테스트는 그대로 동작한다.
    init(directory: URL? = AppEnv.isBundledApp ? AppStatePaths.iCloudDirectory() : nil,
         defaults: UserDefaults = .standard) {
        self.directory = directory
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? false
    }

    /// iCloud Drive 가 켜져 있나(그 경로가 존재하나).
    var isAvailable: Bool { directory != nil }

    /// 동기화 토글. 저장 규약은 `UsageStore` 의 다른 설정들과 같다(`didSet` 으로 기록, init 에서 읽기).
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// 이 Mac 의 식별자. 처음 필요할 때 한 번 만들어 두고 계속 쓴다.
    var deviceID: String {
        if let existing = defaults.string(forKey: Self.deviceIDKey), !existing.isEmpty { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: Self.deviceIDKey)
        return fresh
    }

    var ownFileURL: URL? {
        directory?.appendingPathComponent(Self.fileNamePrefix + deviceID + Self.fileNameSuffix)
    }

    /// 상태를 iCloud 폴더에 복사한다. 게이트를 통과하지 못하면 아무 일도 하지 않는다.
    /// 반환값은 실제로 썼는지 — 테스트가 게이트를 단언하는 지점이다.
    @discardableResult
    func mirror(state: CompanionState, appVersion: String, deviceName: String, now: Date) -> Bool {
        guard isEnabled, let target = ownFileURL else { return false }
        // 간격을 **인코딩보다 먼저** 본다. 창 안에서는 정규 인코딩 비용도 안 치른다(흔한 경로).
        if let last = lastMirroredAt, now.timeIntervalSince(last) < Self.minimumWriteInterval { return false }
        guard let canonical = Self.canonicalStateEncoding(state) else { return false }
        guard canonical != lastMirroredState else { return false }

        let directory = target.deletingLastPathComponent()
        do {
            // 폴더 생성은 여기서만 — 동기화를 안 켠 사용자의 iCloud Drive 에 빈 폴더를 남기지 않는다.
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try SaveTransfer.encode(state: state, appVersion: appVersion,
                                               deviceName: deviceName, now: now)
            // `.atomic` = 임시 파일 + rename. 파일 프로바이더가 rename 을 온전한 교체로 보므로
            // `NSFileCoordinator` 없이도 부분 업로드가 안 생긴다.
            try data.write(to: target, options: .atomic)
        } catch {
            AppLog.write("icloud mirror write failed: \(error)")
            return false
        }
        lastMirroredState = canonical
        lastMirroredAt = now
        return true
    }

    /// 변경 판정용 정규 인코딩.
    ///
    /// `CompanionStore.save()` 가 만든 바이트를 그냥 쓰면 안 된다 — 기본 `JSONEncoder` 는 키 순서를
    /// 보장하지 않아 `inventory`·`candyGrantTier`·`collectedFinals` 가 같은 내용으로도 다른 바이트를
    /// 내놓는다(변경 없는데 매번 업로드). 봉투를 비교해도 안 된다 — `exportedAt` 이 호출마다 달라
    /// 비교가 **항상** 다르다고 나온다. 그래서 상태만, 정렬된 키로.
    static func canonicalStateEncoding(_ state: CompanionState) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(state)
    }

    /// 다른 Mac 들이 남긴 세이브 목록(최신 순). 이 Mac 자신의 파일은 뺀다.
    ///
    /// **메인 액터에서 부르지 마라.** iCloud 가 파일을 내려둔 상태(evicted)면 읽는 순간 다운로드가
    /// 걸려 네트워크만큼 블록한다. 호출부는 `Task.detached` 로 감싼다.
    nonisolated static func remoteSaves(in directory: URL?, excludingDeviceID ownID: String) -> [RemoteSave] {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        let ownName = fileNamePrefix + ownID + fileNameSuffix
        var found: [RemoteSave] = []
        for name in names {
            // evicted 항목은 `.save-<id>.json.icloud` 라는 플레이스홀더 이름으로 보인다. 원래 이름으로
            // 읽으면 머티리얼라이즈가 걸리므로, 판정과 읽기 모두 복원된 이름으로 한다.
            let resolved = materializedName(name)
            guard resolved.hasPrefix(fileNamePrefix), resolved.hasSuffix(fileNameSuffix),
                  resolved != ownName else { continue }
            let url = directory.appendingPathComponent(resolved)
            guard let data = try? Data(contentsOf: url),
                  let envelope = try? SaveTransfer.decode(data) else { continue }
            found.append(RemoteSave(url: url, envelope: envelope))
        }
        return found.sorted { $0.exportedAt > $1.exportedAt }
    }

    /// `.save-x.json.icloud` 플레이스홀더 → `save-x.json`. 그 형태가 아니면 그대로.
    nonisolated static func materializedName(_ name: String) -> String {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return name }
        return String(name.dropFirst().dropLast(".icloud".count))
    }
}
