import Foundation

/// 부화 중인 알. 종과 이로치 여부는 **뽑는 순간** 정해 두고(스프라이트를 미리 받으려고)
/// 부화 때 공개한다.
struct Egg: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    var grade: Grade
    var speciesID: Int
    var shiny: Bool
    var startedAt: Date
    var hatchesAt: Date
    /// 부화 시각이 지났다고 이미 알렸나. 알림은 한 번만 — 익은 알은 사용자가 확인을 누를 때까지
    /// 슬롯에 남으므로, 이 표시가 없으면 매 틱마다 같은 알을 다시 알리게 된다.
    var announced = false
    /// 이 알에서 나올 개체의 경험치 곡선. 부화 시점에는 `BaseSpecies` 가 없으므로
    /// 뽑을 때 적어 둔다 — `shiny`·`grade` 를 알이 들고 있는 것과 같은 이유다.
    var growthRate: GrowthRate = .mediumFast
    /// 이 알에서 나올 개체의 **성비**(PokéAPI `gender_rate`). 성장 곡선과 같은 이유로 뽑을 때
    /// 적어 둔다 — 부화 자리에는 `BaseSpecies` 가 없다. **성별 자체는 여기 안 적는다**: 적으면
    /// 확인을 누르기 전에 세이브에 결과가 드러난다(성격·지방과 같은 규칙).
    var genderRate: Int = GenderBalance.defaultRate

    /// **필드를 더할 때 알이 통째로 사라지지 않게 하는 장치.** Swift 합성 디코더는 기본값이 있어도
    /// 키가 없으면 던지고, `LossyEgg` 는 그 예외를 "이 알을 버린다"로 바꾼다 — `Individual` 에서
    /// 실제로 박스가 비었던 그 부류다. 정체에 해당하는 필드만 필수로 둔다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decode(T.self, forKey: key)) ?? fallback
        }
        grade = try c.decode(Grade.self, forKey: .grade)
        speciesID = try c.decode(Int.self, forKey: .speciesID)
        hatchesAt = try c.decode(Date.self, forKey: .hatchesAt)
        id = value(.id, UUID())
        shiny = value(.shiny, false)
        startedAt = value(.startedAt, hatchesAt)
        announced = value(.announced, false)
        growthRate = value(.growthRate, .mediumFast)
        genderRate = value(.genderRate, GenderBalance.defaultRate)
    }

    init(id: UUID = UUID(), grade: Grade, speciesID: Int, shiny: Bool,
         startedAt: Date, hatchesAt: Date, announced: Bool = false,
         growthRate: GrowthRate = .mediumFast,
         genderRate: Int = GenderBalance.defaultRate) {
        self.id = id
        self.grade = grade
        self.speciesID = speciesID
        self.shiny = shiny
        self.startedAt = startedAt
        self.hatchesAt = hatchesAt
        self.announced = announced
        self.growthRate = growthRate
        self.genderRate = genderRate
    }

    func isReady(at now: Date) -> Bool { now >= hatchesAt }

    /// 남은 시간. 이미 지났으면 0 — 음수가 화면에 새지 않게.
    func remaining(at now: Date) -> TimeInterval {
        max(0, hatchesAt.timeIntervalSince(now))
    }

    /// 신뢰경계(디코드)의 값 범위 검증 — 관대 디코딩과 반드시 짝으로 온다(CLAUDE.md 결함 대응 프로토콜).
    /// 관대 디코딩은 한 필드가 깨져도 나머지를 지키는 대신 **말이 안 되는 값도 통과시킨다**:
    /// `hatchesAt: 1e300` 은 디코드에 *성공*하므로 `load()` 의 손상 복구가 발동하지 않고, 그 뒤
    /// 카운트다운의 `Int(remaining.rounded(.up))` 이 변환 트랩으로 프로세스를 죽인다 — 재기동해도
    /// 같은 파일을 다시 읽어 또 죽어서, 파일을 손으로 지우기 전엔 앱을 쓸 수 없다.
    /// 방어는 다운스트림 산술 지점마다가 아니라 값이 들어오는 이 한 곳에서 한다.
    /// 알 자체는 버리지 않는다(데이터 손실) — 산술에 쓰이는 시각만 자른다.
    func sanitized() -> Egg {
        var egg = self
        egg.startedAt = Self.clampDate(startedAt)
        // 부화는 시작보다 이를 수 없고, 아무리 늦어도 시작 + 최장 등급 시간이다.
        let longest = Grade.allCases.map(EggBalance.duration).max() ?? 0
        egg.hatchesAt = min(max(Self.clampDate(hatchesAt), egg.startedAt),
                            egg.startedAt.addingTimeInterval(longest))
        // 성비도 굴림에 들어가는 수치라 같은 자리에서 자른다 — 범위 밖이면 기본값으로.
        egg.genderRate = GenderBalance.sanitizedRate(genderRate)
        return egg
    }

    /// 저장분에서 받아들일 시각 범위의 상한(2200-01-01). 하한은 유닉스 원년.
    /// 실사용 값은 늘 이 안이고 밖은 손상·조작이다.
    private static let latestValidSeconds: TimeInterval = 7_258_118_400

    private static func clampDate(_ date: Date) -> Date {
        let seconds = date.timeIntervalSince1970
        // NaN·무한대는 비교가 전부 false 라 min/max 로는 못 거른다 — 먼저 걸러낸다.
        guard seconds.isFinite else { return Date(timeIntervalSince1970: 0) }
        return Date(timeIntervalSince1970: min(max(seconds, 0), latestValidSeconds))
    }
}
