import Foundation

/// 기기 교체용 세이브 이전 — 상태를 봉투에 담아 내보내고, 다른 기기에서 들여온다.
///
/// `CompanionState` 를 그대로 파일로 쓰지 않고 봉투로 감싸는 이유: 상태 디코딩이 의도적으로
/// 관대해서(`lenient*` — 한 필드가 깨져도 도감 전체를 날리지 않으려고) **아무 JSON 이나 넣어도
/// 전 필드가 기본값으로 흡수되며 "성공"한다.** 봉투 없이는 남의 JSON 을 골라도 불러오기가
/// 성공한 뒤 도감이 빈 상태가 되어, 사용자에겐 "앱이 내 진행을 지웠다"로 보인다.
/// 봉투의 `format`/`schema` 는 관대 디코딩 대상이 아니라(기본값 없음) 이 오인을 먼저 차단한다.
struct SaveEnvelope: Codable, Sendable {
    static let formatID = "poketokenbar.save"
    static let schemaVersion = 1

    var format: String
    var schema: Int
    var appVersion: String
    var exportedAt: Date
    var sourceDevice: String
    var state: CompanionState
}

/// 봉투의 앞부분만 읽는 최소 구조 — 본문(`state`)이 상위 스키마라 못 읽히더라도 "새 버전 세이브"임을
/// 알아보고 정확한 안내를 하기 위해서다. 이게 없으면 상위 스키마 파일이 "세이브 파일이 아니에요"로
/// 뜬다(사용자는 앱을 업데이트하면 된다는 걸 모른다).
private struct SaveHeader: Decodable {
    let format: String
    let schema: Int
}

/// 덮어쓰기 확인에 쓰는 요약 — "무엇이 대체되는지"를 수치로 보여주기 위한 값.
/// (경고문에 대상을 구체적으로 적는 것이 일반적인 "정말 진행할까요?" 보다 사용자에게 유용하다.)
struct SaveSummary: Equatable, Sendable {
    var dexCount: Int
    var lifetimeTokens: Int

    init(state: CompanionState) {
        dexCount = state.dex.count
        lifetimeTokens = state.usedSinceInstall
    }
}

enum SaveTransferError: Error, Equatable {
    /// 봉투가 아니거나 다른 앱의 JSON.
    case notASaveFile
    /// 이 빌드보다 새 스키마 — 상위 버전에서 만든 세이브.
    case newerSchema(found: Int, supported: Int)
    /// 세이브로 보기엔 과하게 큰 파일 — 파싱이 메인스레드를 오래 잡는다.
    case fileTooLarge(bytes: Int, limit: Int)
    /// 덮어쓰기 전 백업을 못 남겼다 — 확인창이 약속한 복구 수단이 없으므로 불러오기를 중단한다.
    case backupFailed
}

/// 불러오기 확인창의 버튼 배치 규칙. AppKit 밖으로 빼둔 이유는 이 규칙이 **데이터 손실과 직결**되는데
/// `NSAlert` 구성은 XCTest 에서 도달할 수 없기 때문이다 — 두 줄이 뒤바뀌면 Return 한 키로 이 Mac 의
/// 진행이 대체되는데 잡을 자동 테스트가 없었다.
enum ImportConfirmPolicy {
    static let replaceButtonIndex = 0
    static let cancelButtonIndex = 1

    /// 기본 버튼(Return)은 **취소**여야 한다. 파괴적 동작을 기본으로 두지 않는다.
    static func keyEquivalent(forButtonAt index: Int) -> String {
        index == cancelButtonIndex ? "\r" : ""
    }
}

enum SaveTransfer {
    /// 세이브 파일 크기 상한. 정상 세이브는 수 KB 이고 도감이 가득 차도 수백 KB 를 넘지 않는다.
    /// 상한이 없으면 거대한 JSON 이 메인스레드 파싱을 수 초간 잡는다(실측: 39MB → 약 1.8초 정지).
    static let maxFileBytes = 8 * 1024 * 1024

    /// 세이브에 들어올 수 있는 수치의 상한 — 실사용(수십억)의 10만 배라 정상 진행을 자르지 않으면서,
    /// 이 값끼리 더하고 빼도 Int64 범위 안에 머문다.
    static let maxTokenValue = 1_000_000_000_000_000

    /// 내보내기 파일명 — 날짜가 들어가야 여러 번 내보내도 덮어쓰지 않는다.
    static func suggestedFileName(date: Date) -> String {
        "PokeTokenBar-Save-\(dayStamp(date)).json"
    }

    /// 백업 파일명 — 불러올 때마다 새 슬롯. 하나만 유지하면 두 번째 불러오기가 **원본**을 덮어써,
    /// "잘못 불러왔으니 되돌린다"는 바로 그 상황에서 되돌릴 대상이 사라진다.
    static func backupFileName(date: Date) -> String {
        "companion-state.pre-import-\(secondStamp(date)).json"
    }
    static let backupFilePrefix = "companion-state.pre-import-"
    /// 유지할 백업 개수 — 오래된 것부터 지운다.
    static let backupsToKeep = 5

    private static func stamp(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f.string(from: date)
    }
    private static func dayStamp(_ date: Date) -> String { stamp(date, "yyyy-MM-dd") }
    private static func secondStamp(_ date: Date) -> String { stamp(date, "yyyy-MM-dd-HHmmss") }

    static func encode(state: CompanionState, appVersion: String, deviceName: String, now: Date) throws -> Data {
        let envelope = SaveEnvelope(format: SaveEnvelope.formatID,
                                    schema: SaveEnvelope.schemaVersion,
                                    appVersion: appVersion,
                                    exportedAt: now,
                                    sourceDevice: deviceName,
                                    state: state)
        let encoder = JSONEncoder()
        // 사람이 열어봤을 때 읽히도록(무엇이 옮겨가는지 확인 가능) — 4KB 라 크기는 무의미.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    static func decode(_ data: Data) throws -> SaveEnvelope {
        guard data.count <= maxFileBytes else {
            throw SaveTransferError.fileTooLarge(bytes: data.count, limit: maxFileBytes)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 헤더를 먼저 읽는다 — 본문이 상위 스키마라 못 읽혀도 "새 버전 세이브"로 정확히 안내하기 위해.
        guard let header = try? decoder.decode(SaveHeader.self, from: data),
              header.format == SaveEnvelope.formatID else {
            throw SaveTransferError.notASaveFile
        }
        guard header.schema <= SaveEnvelope.schemaVersion else {
            throw SaveTransferError.newerSchema(found: header.schema, supported: SaveEnvelope.schemaVersion)
        }
        guard var envelope = try? decoder.decode(SaveEnvelope.self, from: data) else {
            throw SaveTransferError.notASaveFile   // 같은 스키마인데 못 읽힘 = 손상
        }
        envelope.state = sanitized(envelope.state)
        return envelope
    }

    /// 신뢰경계 값 정규화 — 세이브는 **앱 밖에서** 온다(손편집·전송 중 손상·다른 빌드).
    ///
    /// `CompanionState` 의 디코딩은 의도적으로 관대해서(한 필드가 깨져도 도감을 안 날리려고) 말이 안 되는
    /// 값도 통과시킨다. 그 값이 그대로 저장되면 이후 산술이 Swift 오버플로 트랩으로 **프로세스를 죽이고,
    /// 재기동해도 같은 파일을 읽어 다시 죽는다** — 사용자가 파일을 손으로 지우기 전까지 앱을 못 쓴다
    /// (`load()` 의 `.corrupt` 자동복구는 디코드가 *성공*하므로 발동하지 않는다).
    ///
    /// 다운스트림 산술 지점마다 막으면 새 지점이 생길 때마다 재발하므로, 값이 **들어오는 경계 한 곳**에서
    /// 정규화한다. 대상은 실제로 산술에 쓰이는 필드뿐이다 — 도감·인벤토리 항목은 잘라내지 않는다(데이터 손실).
    static func sanitized(_ state: CompanionState) -> CompanionState {
        func clampToken(_ v: Int) -> Int { min(max(0, v), maxTokenValue) }
        var s = state
        s.usedSinceInstall = clampToken(s.usedSinceInstall)
        s.spentTokens = clampToken(s.spentTokens)
        s.eggUsage = clampToken(s.eggUsage)
        s.claimedTodayTokensByProvider = s.claimedTodayTokensByProvider?.reduce(into: [:]) { result, entry in
            result[entry.key] = clampToken(entry.value)
        }
        // 알 보증은 "지금 품고 있는 알"에만 붙는 값이라 활성 포켓몬과 공존할 수 없다. 손편집·구버전
        // 조합으로 둘 다 들어오면 그 보증이 다음 알로 새어 영구 프리미엄이 되므로 여기서 떨군다.
        // 그 보증으로 미리 뽑아둔 종(pendingHatchID)도 함께 버린다 — 보증만 지우면 졸업 후 받는 **무료**
        // 알이 그 pre-roll 로 부화해, 아무도 사지 않은 프리미엄 결과가 나온다.
        if s.active != nil { s.eggTier = nil; s.pendingHatchID = nil }
        // 만족시킬 수 없는 보증은 알을 영구히 못 깨게 만든다 — 전설은 capture_rate 로 표현할 수 없어
        // (captureRateCeiling == nil) 두 롤 경로 모두 후보를 0개로 만들고, 부화가 없으니 보증도 소비되지
        // 않으며, 새 알 구매는 `hasActive` 게이트에 막혀 빠져나갈 수단이 없다. 디코드는 *성공*하므로
        // load() 의 .corrupt 복구도 안 걸려 파일을 손으로 지우기 전엔 앱을 못 쓴다.
        // 관대 디코딩은 모르는 rawValue 만 걸러낼 뿐 **아는데 만족 불가능한 값**은 그대로 통과시킨다.
        if s.eggTier?.captureRateCeiling == nil { s.eggTier = nil }
        if var active = s.active {
            active.usedAtStage = clampToken(active.usedAtStage)
            // totalForms 는 `kk * (kk + 1)` 형태로 쓰여(PokemonBalance.phaseThreshold) 큰 값이 그 자체로 트랩이다.
            active.totalForms = min(max(1, active.totalForms), 12)
            active.stageIndex = min(max(0, active.stageIndex), max(0, active.pathIDs.count - 1))
            s.active = active
        }
        s.reconcileRepresentativeSelection()
        return s
    }

    /// 다른 기기에서 온 상태를 **이 기기 기준으로 재정렬**한다.
    ///
    /// `CompanionState` 의 필드는 이전 관점에서 세 부류다.
    ///  - **진행**: 어느 기기에서든 참(`usedSinceInstall`·`dex`·`inventory`·`active`·`eggUsage`·`eggTier`·
    ///    `representativeSpeciesID`…)
    ///    → 그대로. 알 보증(`eggTier`)은 산 물건이지 이 기기의 장부가 아니라 기기를 옮겨도 따라간다.
    ///  - **로컬 장부**: *그 기기가* 어디까지 적립했나(`claimedTodayTokensByProvider`·`lastDate`·`installBaselineSet`)
    ///    → 새 기기 기준으로 다시 잡는다. 그대로 들여오면 옛 기기의 오늘 총량이 문턱이 되어
    ///    `CompanionStore.update` 의 프로바이더별 증분 게이트가 이전 당일 내내 거짓이 되고,
    ///    새 기기 사용분이 조용히 안 잡힌다(자정에 저절로 낫기 때문에 버그로 안 보인다).
    ///  - **기기 환경설정**: 진행이 아니라 이 기기에서 보는 방식(`language`) → **현재 기기 값을 지킨다**.
    ///    일본어 Mac 의 세이브가 영어 Mac 의 UI 언어를 바꾸면 안 된다.
    ///
    /// 계정 전역 원장(`candyGrantTier`)은 교체가 아니라 **key 별 max 병합**이다. 한도 창 key 는 계정
    /// 단위라 두 기기가 같은 창을 본다 — 더 오래된 세이브로 통째 교체하면 이미 지급한 창의 기록이
    /// 사라져 같은 창에서 사탕이 재지급된다(보존만으로는 이 역방향을 못 막는다).
    static func rebasedForThisDevice(_ imported: CompanionState,
                                     current: CompanionState,
                                     todayTokensByProvider: [String: Int],
                                     todayDate: String,
                                     hasUsageData: Bool) -> CompanionState {
        var state = imported
        state.language = current.language
        state.candyGrantTier = mergedGrantTier(imported.candyGrantTier, current.candyGrantTier)
        state.candyFeatureSeeded = imported.candyFeatureSeeded || current.candyFeatureSeeded
        let hasCurrentProviderData = hasUsageData && !todayTokensByProvider.isEmpty
        if hasCurrentProviderData {
            // 신규 설치와 같은 규칙: 불러온 시점 이전의 이 기기 사용량은 소급 적립하지 않는다.
            state.installBaselineSet = true
            state.claimedTodayTokensByProvider = todayTokensByProvider
            state.lastDate = todayDate
        } else {
            // 아직 이 기기의 오늘 사용량을 모른다(파싱 전·프로바이더 없음·stale snapshot만 존재).
            // `hasUsageData`는 snapshot 존재 여부일 뿐 오늘 날짜 데이터의 존재를 보장하지 않는다.
            // 여기서 빈 map을 이미 seed된 장부로 저장하면 첫 정상 snapshot이 "새 provider"로
            // 취급되어 그 시점까지의 하루치가 조용히 누락된다 → baseline 판정을 신규 설치 경로에 넘긴다.
            state.installBaselineSet = false
            state.claimedTodayTokensByProvider = nil
            state.lastDate = ""
        }
        return state
    }

    /// 창 key 별로 더 높은 tier 를 남긴다 — 어느 쪽에서든 이미 지급했으면 지급한 것으로 본다.
    static func mergedGrantTier(_ a: [String: Int], _ b: [String: Int]) -> [String: Int] {
        a.merging(b) { max($0, $1) }
    }
}
