---
summary: "v3 launch no longer shows a blank Settings window; SwiftUI Scene is a hidden MenuBarExtra plus LaunchWindowPolicy."
read_when:
  - Touching PokeTokenBarApp Scene, Settings placeholders, or Today desk window identity
---

# Launch window (shipped in v3)

Blank Settings window on launch. Status: **shipped in v3**.

## Cause

SwiftUI requires at least one `Scene`. The menu bar is an `NSStatusItem` in `AppDelegate` (not `MenuBarExtra` labels — those re-render too often). The previous dummy scene was:

```swift
Settings { EmptyView() }
```

That still created a **SwiftUI Settings placeholder window** (`com_apple_SwiftUI_Settings…`) at every launch.

## Fix

1. Replace `Settings { EmptyView() }` with a **hidden** `MenuBarExtra(isInserted: .constant(false))` whose label and content are empty. It satisfies the Scene requirement without inserting a status item or opening a window.
2. `LaunchWindowPolicy.isSwiftUISettingsPlaceholder(identifier:autosaveName:)` — pure predicate: identifier or autosave name has prefix `com_apple_SwiftUI_Settings`.
3. `AppDelegate.closeSwiftUISettingsPlaceholders()` orders out and closes matching windows. Called from `applicationWillFinishLaunching`, `applicationDidFinishLaunching`, and `NSWindow.didBecomeKeyNotification` (late placeholders).

The Today desk uses the same policy type for its **own** identifiers (`PokeTokenBar.TodayDesk` / `PokeTokenBarTodayDesk`) so it is never treated as a Settings placeholder. Tests cover both.

## Key files

- `Sources/PokeTokenBar/PokeTokenBarApp.swift` (`LaunchWindowPolicy`, hidden `MenuBarExtra`)
- `Sources/PokeTokenBar/Core/FocusSessionStore.swift` (Today desk identifier extension)
- `Tests/PokeTokenBarTests/LaunchWindowPolicyTests.swift`
