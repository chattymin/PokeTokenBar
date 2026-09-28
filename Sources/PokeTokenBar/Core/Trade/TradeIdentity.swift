import Foundation

/// My identity, shown to the trade partner — a per-device value rather than progress data, so it
/// lives outside CompanionState (the save).
enum TradeIdentity {
    private static let nicknameKey = "tradeNickname"
    private static let codeKey = "tradeCode"

    static func nickname(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: nicknameKey) ?? (Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
    }

    static func setNickname(_ nickname: String, defaults: UserDefaults = .standard) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: nicknameKey)
        } else {
            defaults.set(trimmed, forKey: nicknameKey)
        }
    }

    /// 8 uppercase letters/digits — short enough for a person to copy by hand. Easily confused
    /// characters (0/O, 1/I) are excluded from the alphabet.
    static func code(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: codeKey) { return existing }
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let generated = String((0..<8).map { _ in alphabet.randomElement()! })
        defaults.set(generated, forKey: codeKey)
        return generated
    }
}
