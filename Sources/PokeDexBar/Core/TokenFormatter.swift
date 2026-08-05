import Foundation

enum TokenFormatter {
    /// 987 → "987", 12_345 → "12.3K", 190_612_940 → "190.6M", 1_240_000_000 → "1.24B"
    static func compact(_ value: Int) -> String {
        let v = Double(abs(value))
        let sign = value < 0 ? "-" : ""
        switch v {
        case ..<1_000:
            return "\(value)"
        case ..<1_000_000:
            return sign + trim(v / 1_000, decimals: 1) + "K"
        case ..<1_000_000_000:
            return sign + trim(v / 1_000_000, decimals: 1) + "M"
        default:
            return sign + trim(v / 1_000_000_000, decimals: 2) + "B"
        }
    }

    /// 팝오버 상세용 천 단위 구분 (190,612,940)
    static func grouped(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func cost(_ usd: Double) -> String {
        String(format: "$%.2f", usd)
    }

    /// 메뉴바용 짧은 비용 표기: $9.5 / $311 / $1.2K
    static func costCompact(_ usd: Double) -> String {
        if usd < 100 { return String(format: "$%.1f", usd) }
        if usd < 10_000 { return String(format: "$%.0f", usd) }
        return String(format: "$%.1fK", usd / 1_000)
    }

    static func percent(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f%%", value) : String(format: "%.1f%%", value)
    }

    private static func trim(_ value: Double, decimals: Int) -> String {
        var s = String(format: "%.\(decimals)f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
