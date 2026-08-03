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

/// 덮어쓰기 확인에 쓰는 요약 — "무엇이 대체되는지"를 수치로 보여주기 위한 값.
/// (경고문에 대상을 구체적으로 적는 것이 일반적인 "정말 진행할까요?" 보다 사용자에게 유용하다.)
struct SaveSummary: Equatable, Sendable {
    var dexCount: Int
    var lifetimeTokens: Int

    init(dexCount: Int, lifetimeTokens: Int) {
        self.dexCount = dexCount
        self.lifetimeTokens = lifetimeTokens
    }

    init(state: CompanionState) {
        self.init(dexCount: state.dex.count, lifetimeTokens: state.usedSinceInstall)
    }
}

enum SaveTransferError: Error, Equatable {
    /// 봉투가 아니거나 다른 앱의 JSON.
    case notASaveFile
    /// 이 빌드보다 새 스키마 — 상위 버전에서 만든 세이브.
    case newerSchema(found: Int, supported: Int)
}

enum SaveTransfer {
    /// 내보내기 파일명 — 날짜가 들어가야 여러 번 내보내도 덮어쓰지 않는다.
    static func suggestedFileName(date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "PokeTokenBar-Save-\(f.string(from: date)).json"
    }

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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var envelope = try? decoder.decode(SaveEnvelope.self, from: data),
              envelope.format == SaveEnvelope.formatID else {
            throw SaveTransferError.notASaveFile
        }
        guard envelope.schema <= SaveEnvelope.schemaVersion else {
            throw SaveTransferError.newerSchema(found: envelope.schema, supported: SaveEnvelope.schemaVersion)
        }
        envelope.state = sanitized(envelope.state)
        return envelope
    }

    /// 세이브에 들어올 수 있는 수치의 상한 — 실사용(수십억)의 10만 배라 정상 진행을 자르지 않으면서,
    /// 이 값끼리 더하고 빼도 Int64 범위 안에 머문다.
    static let maxTokenValue = 1_000_000_000_000_000

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
        s.claimedTodayTokens = clampToken(s.claimedTodayTokens)
        if var active = s.active {
            active.usedAtStage = clampToken(active.usedAtStage)
            // totalForms 는 `kk * (kk + 1)` 형태로 쓰여(PokemonBalance.phaseThreshold) 큰 값이 그 자체로 트랩이다.
            active.totalForms = min(max(1, active.totalForms), 12)
            active.stageIndex = min(max(0, active.stageIndex), max(0, active.pathIDs.count - 1))
            s.active = active
        }
        return s
    }

    /// 다른 기기에서 온 상태를 **이 기기 기준으로 재정렬**한다.
    ///
    /// `claimedTodayTokens` 는 진행이 아니라 "이 기기가 오늘 어디까지 적립했나"라는 기기 로컬 장부다.
    /// 그대로 들여오면 옛 기기의 오늘 총량이 문턱이 되어, `CompanionStore.update` 의
    /// `todayTokens > claimedTodayTokens` 게이트가 이전 당일 내내 거짓이 된다 — 새 기기에서 쓴
    /// 토큰이 성장·잔액에 조용히 안 잡힌다(다음 날 00시에 저절로 낫기 때문에 버그로 안 보인다).
    ///
    /// 진행(도감·누적·인벤토리·현재 개체·사탕 지급 원장)은 전부 보존하고 이 장부만 다시 잡는다.
    static func rebasedForThisDevice(_ imported: CompanionState,
                                     todayTokens: Int,
                                     todayDate: String,
                                     hasUsageData: Bool) -> CompanionState {
        var state = imported
        if hasUsageData {
            // 신규 설치와 같은 규칙: 불러온 시점 이전의 이 기기 사용량은 소급 적립하지 않는다.
            state.installBaselineSet = true
            state.claimedTodayTokens = todayTokens
            state.lastDate = todayDate
        } else {
            // 아직 이 기기의 오늘 사용량을 모른다(파싱 전·프로바이더 없음). 여기서 0 으로 잡으면
            // 첫 파싱 때 하루치가 통째로 델타가 된다 → baseline 판정을 신규 설치 경로에 넘긴다.
            state.installBaselineSet = false
            state.claimedTodayTokens = 0
            state.lastDate = ""
        }
        return state
    }
}
