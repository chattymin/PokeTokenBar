import Foundation

/// Day-by-day token totals kept across months, so a recap survives the 1st of the month.
///
/// Providers only report the current month (`monthDaily`), so on the 3rd a seven-day window would
/// lose four days and a year would be out of reach. This ledger is a local cache of numbers the app
/// already derived — no new user state, nothing to transfer between devices, and it rebuilds itself
/// from the next refresh.
struct UsageLedger: Equatable, Sendable {
    static let defaultsKey = "dailyTokenLedger"
    static let coverageKey = "dailyTokenLedgerSince"

    private(set) var tokensByDay: [String: Int] = [:]
    /// The first day the ledger vouches for. From there on a missing row means "no usage"; before it
    /// the app was not recording, which a recap must not present as a quiet stretch.
    private(set) var coveredSince: String?

    func tokens(on day: String) -> Int { tokensByDay[day] ?? 0 }

    func covers(_ day: String) -> Bool { coveredSince.map { day >= $0 } ?? false }

    /// Records a refresh. A day never goes down: a rotated or pruned log makes the provider report
    /// less than it did yesterday, and the recap would lose days that really happened. Today keeps
    /// climbing all day, so taking the larger of the two is also what the live total does.
    mutating func merge(_ series: [DailyUsage]) {
        for day in series where day.totalTokens > 0 {
            tokensByDay[day.date] = max(tokensByDay[day.date] ?? 0, day.totalTokens)
        }
        // The series lists every day since the 1st, empty ones included, so the whole stretch was
        // scanned: that is what makes a zero a real zero.
        if let first = series.map(\.date).min(), coveredSince.map({ first < $0 }) ?? true {
            coveredSince = first
        }
    }

    /// Drops what no recap can reach any more. Day keys are `yyyy-MM-dd`, which sorts
    /// lexicographically the same way it sorts chronologically.
    mutating func prune(before cutoff: String) {
        tokensByDay = tokensByDay.filter { $0.key >= cutoff }
        // The dropped days are unknown again, not empty.
        if let since = coveredSince, since < cutoff { coveredSince = cutoff }
    }

    static func load(from defaults: UserDefaults) -> UsageLedger {
        var ledger = UsageLedger()
        // Hand-edited defaults are data, not truth: keep what parses as a day and drop the rest.
        // A junk key that sorted below every real day would otherwise backdate the coverage.
        let formatter = LocalUsageReader.localDayFormatter()
        if let stored = defaults.dictionary(forKey: defaultsKey) as? [String: Int] {
            ledger.tokensByDay = stored.filter { formatter.date(from: $0.key) != nil && $0.value > 0 }
        }
        if let since = defaults.string(forKey: coverageKey), formatter.date(from: since) != nil {
            ledger.coveredSince = since
        }
        return ledger
    }

    func save(to defaults: UserDefaults) {
        defaults.set(tokensByDay, forKey: Self.defaultsKey)
        defaults.set(coveredSince, forKey: Self.coverageKey)
    }
}

enum RecapScope: String, CaseIterable, Sendable {
    case week, month, year

    fileprivate var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }
}

/// One calendar week, month or year. Calendar periods rather than rolling windows, so stepping
/// back lands on "the week of the 7th", not on an arbitrary seven days.
struct RecapPeriod: Equatable, Sendable {
    let scope: RecapScope
    /// First instant of the period.
    let start: Date
    /// First instant after the period.
    let end: Date

    init(scope: RecapScope, containing date: Date, calendar: Calendar) {
        self.scope = scope
        // API-forced unwrap: every Gregorian date sits in a week, a month and a year.
        let interval = calendar.dateInterval(of: scope.component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
        start = interval.start
        end = interval.end
    }

    func shifted(by offset: Int, calendar: Calendar) -> RecapPeriod {
        let moved = calendar.date(byAdding: scope.component, value: offset, to: start) ?? start
        return RecapPeriod(scope: scope, containing: moved, calendar: calendar)
    }

    /// Gregorian whatever the system calendar, so a year runs January to December and the day keys
    /// match `LocalUsageReader.localDayFormatter`. The week still starts on the user's first weekday.
    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }
}

/// A recap of one period — read-only, computed on demand. Nothing here is a reward or a goal: it
/// reports what already happened, so the app still asks nothing of the user.
// Not Equatable: `DexEntry` is not, and the graduated rows carry it whole.
struct UsageRecap: Sendable {
    /// One meter: a day in the week and month views, a month in the year view.
    struct Bucket: Equatable, Sendable {
        /// `yyyy-MM-dd` of the bucket's first day.
        let key: String
        let tokens: Int
        /// Holds today.
        let isCurrent: Bool
        /// False for the future and for days before the ledger started: unknown, not zero.
        let hasData: Bool
    }

    struct Day: Equatable, Sendable {
        let key: String
        let tokens: Int
    }

    let period: RecapPeriod
    let buckets: [Bucket]
    let total: Int
    /// Today falls inside the period.
    let isInProgress: Bool
    /// The previous period over the same number of days while this one is running, the whole of it
    /// otherwise. nil when the ledger does not reach its first day: days the app never saw would
    /// count as zero and invent a jump.
    let previousTotal: Int?
    let bestDay: Day?
    let activeDays: Int
    /// Days of the period, up to today, that the ledger covers: the denominator of `activeDays`.
    let countedDays: Int
    /// Longest run of consecutive active days inside the period.
    let bestStreak: Int
    /// Individuals graduated during the period, newest first.
    let graduated: [DexEntry]
    /// The previous period holds at least one day the ledger covers.
    let canGoBack: Bool

    var delta: Double? {
        guard let previousTotal, previousTotal > 0 else { return nil }
        return Double(total - previousTotal) / Double(previousTotal)
    }

    static func make(ledger: UsageLedger, dex: [DexEntry], period: RecapPeriod, now: Date,
                     calendar: Calendar) -> UsageRecap {
        let formatter = LocalUsageReader.localDayFormatter(timeZone: calendar.timeZone)
        let today = calendar.startOfDay(for: now)

        // `date(byAdding:)` rather than +86400: a DST day is 23 or 25 hours long.
        func days(_ start: Date, _ end: Date) -> [Date] {
            var result: [Date] = []
            var cursor = calendar.startOfDay(for: start)
            while cursor < end {
                result.append(cursor)
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            return result
        }
        func known(_ key: String) -> Bool { ledger.tokens(on: key) > 0 || ledger.covers(key) }

        let periodDays = days(period.start, period.end)
        let elapsed = periodDays.filter { $0 <= today }.map { date in
            let key = formatter.string(from: date)
            return Day(key: key, tokens: ledger.tokens(on: key))
        }
        var bestStreak = 0
        var run = 0
        for day in elapsed {
            run = day.tokens > 0 ? run + 1 : 0
            bestStreak = max(bestStreak, run)
        }

        let buckets: [Bucket]
        switch period.scope {
        case .week, .month:
            buckets = periodDays.map { date in
                let key = formatter.string(from: date)
                return Bucket(key: key, tokens: ledger.tokens(on: key), isCurrent: date == today,
                              hasData: date <= today && known(key))
            }
        case .year:
            buckets = (0..<12).map { index in
                let start = calendar.date(byAdding: .month, value: index, to: period.start) ?? period.start
                let end = calendar.date(byAdding: .month, value: 1, to: start) ?? period.end
                let keys = days(start, end).filter { $0 <= today }.map { formatter.string(from: $0) }
                return Bucket(key: formatter.string(from: start),
                              tokens: keys.reduce(0) { $0 + ledger.tokens(on: $1) },
                              isCurrent: start <= today && today < end,
                              hasData: keys.contains(where: known))
            }
        }

        let isInProgress = period.start <= today && today < period.end
        let previous = period.shifted(by: -1, calendar: calendar)
        let previousDays = days(previous.start, previous.end).map { formatter.string(from: $0) }
        // A running period is compared over the same number of days, or the 18th of the month
        // would read as a 40% drop against a whole month.
        let compared = isInProgress ? Array(previousDays.prefix(elapsed.count)) : previousDays
        let previousTotal = compared.first.map(ledger.covers) == true
            ? compared.reduce(0) { $0 + ledger.tokens(on: $1) }
            : nil

        let graduated = dex
            .filter { entry in
                !entry.isReleased && entry.caughtAt.map { $0 >= period.start && $0 < period.end } == true
            }
            .sorted { ($0.caughtAt ?? .distantPast) > ($1.caughtAt ?? .distantPast) }

        return UsageRecap(
            period: period,
            buckets: buckets,
            total: elapsed.reduce(0) { $0 + $1.tokens },
            isInProgress: isInProgress,
            previousTotal: previousTotal,
            bestDay: elapsed.filter { $0.tokens > 0 }.max { $0.tokens < $1.tokens },
            activeDays: elapsed.filter { $0.tokens > 0 }.count,
            countedDays: elapsed.filter { known($0.key) }.count,
            bestStreak: bestStreak,
            graduated: graduated,
            canGoBack: previousDays.last.map(ledger.covers) ?? false)
    }
}
