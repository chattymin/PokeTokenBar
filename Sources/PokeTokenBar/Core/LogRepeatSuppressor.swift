import Foundation

/// Decides whether a repeated status line is written. A pure state machine, so it is tested with
/// fixtures (`AppLog.write` is a no-op under `swift test`, so the log file cannot be checked).
///
/// Why: status lines that describe an unchanged state are written on every poll. In a real log
/// (19,751 lines over three weeks) `cursor api: no session token — state.vscdb: missing` alone
/// appeared 2,658 times. `AppLog` rotates at 2 MB, so this noise pushes out the history needed to
/// diagnose a crash or a failed sync.
///
/// It suppresses repeats but never a state change: a different message is written at once. An
/// unchanged state is still written once per `repeatAfter`, so the log can tell "since when" from
/// "still true now".
struct LogRepeatSuppressor {
    private var lastWritten: [String: (message: String, at: Date)] = [:]

    /// Returns true when the line should be written, and records it.
    /// - key: the slot that lines share (e.g. `"cursor-limits"`). Use one key per provider or state,
    ///   so one provider's change does not lift another's suppression.
    mutating func shouldWrite(key: String,
                              message: String,
                              now: Date = Date(),
                              repeatAfter: TimeInterval) -> Bool
    {
        guard let previous = lastWritten[key] else {
            lastWritten[key] = (message, now)
            return true                                  // first observation: always written
        }
        if previous.message != message {
            lastWritten[key] = (message, now)
            return true                                  // state change: written at once
        }
        if now.timeIntervalSince(previous.at) >= repeatAfter {
            lastWritten[key] = (message, now)
            return true                                  // same state, periodic reaffirmation
        }
        return false
    }
}
