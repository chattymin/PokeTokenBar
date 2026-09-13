import Foundation

/// Provenance of the amount, independent of whether a subscription or API key was used.
/// A source-reported amount is not necessarily an invoice or a charge.
struct CostCoverage: Codable, Sendable, Equatable {
    var reported = false
    var estimated = false
    var unknown = false

    static let empty = CostCoverage()
    static let source = CostCoverage(reported: true)
    static let estimate = CostCoverage(estimated: true)
    static let unavailable = CostCoverage(unknown: true)
    var hasKnown: Bool { reported || estimated }

    mutating func merge(_ other: CostCoverage) {
        reported = reported || other.reported
        estimated = estimated || other.estimated
        unknown = unknown || other.unknown
    }
}

struct UsageCost: Sendable, Equatable {
    var amount: Double = 0
    var coverage: CostCoverage = .empty

    mutating func add(_ other: UsageCost) {
        amount += other.amount
        coverage.merge(other.coverage)
    }

    func text(_ l: L, compact: Bool = false) -> String {
        if coverage.unknown && !coverage.hasKnown { return compact ? "$—" : l.costUnavailable }
        return compact ? TokenFormatter.costCompact(amount) : TokenFormatter.cost(amount)
    }

    func explanation(_ l: L) -> String {
        if coverage.unknown { return coverage.hasKnown ? l.costPartialHint : l.costUnavailableHint }
        return coverage.estimated ? l.costEstimateHint : l.costReportedHint
    }
}
