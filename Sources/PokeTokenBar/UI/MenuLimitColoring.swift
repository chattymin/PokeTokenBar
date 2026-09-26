import AppKit

/// Colors the menu bar's limit items in their gauge color.
enum MenuLimitColoring {
    /// Each run colors one whole "Label NN%" item. Labels are unique per provider and the token/cost
    /// line never contains one, so a plain search finds the item. Separators and the token/cost line are
    /// left alone and keep the system text color, which follows the menu bar's light/dark appearance.
    static func apply(_ runs: [UsageStore.MenuLimitColorRun], to string: NSMutableAttributedString) {
        let text = string.string as NSString
        for run in runs {
            let range = text.range(of: run.text)
            guard range.location != NSNotFound else { continue }
            string.addAttribute(.foregroundColor, value: NSColor(run.tier.color), range: range)
        }
    }
}
