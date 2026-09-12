---
summary: "v3 session timer + Today breakout window — overlay island, Focus pin, titled NSWindow, zero-time popup, check-ins, XP multipliers. Shipped."
read_when:
  - Changing FocusSession, Today desk, overlay island, or session XP
---

# Session timer + Today desk (shipped in v3)

Always-visible Linear focus timer, pet overlay island, and a dedicated **Today** window. Status: **shipped in v3** (`/Applications/PokeTokenBar v3.app`). Uncommitted in this worktree.

This is not a stretched popover and not a Settings scene. Closing Today does **not** stop the session — the overlay keeps it.

## Three surfaces

| Surface | Job | Not this surface |
|---|---|---|
| Menu-bar popover (360px) | Remote: usage, companion, Linear browser. **Focus** on an issue card. Calendar in the **footer** opens Today. | Not the timer workspace |
| Pet + island overlay | Always-visible identity + clock while a session runs. Pause / status. Check-in and zero-time prompts sit above the island. | Not Projects / Initiatives |
| Today `NSWindow` | Titled, closable, miniaturizable, resizable (~440×680). Hero timer, in-progress pin list, today’s session + check-in log. | No calendar rail, no bag/dex/shop |

## How to open Today

English tooltip / menu title: **Open Today** (`todayDeskMenuOpen`). Window title: **Today**.

1. **Menu-bar popover footer** — calendar SF Symbol (`PopoverView.footer`), every tab.
2. **Linear tab header** — calendar next to refresh (`LinearIntegrationView`).
3. **Right-click floating pet** — context menu item **Open Today**.
4. **Focus** on a Linear issue — `FocusSessionStore.pin` starts or switches the session and brings Today forward (`openDesk: true` by default). Pinning the same issue again only opens the desk. Pinning a *different* issue ends the previous session **without** completing Linear.

`TodayDeskController` is a real `NSWindow` (`styleMask: titled + closable + miniaturizable + resizable`), identifier `PokeTokenBar.TodayDesk`. On close, `contentView` is released; the session stays on the overlay.

## Focus pin

Shared `LinearFocusButton` on Linear cards, project/initiative nested issues, and the Today pin list.

- Idle: **Focus**
- Current pin: **Focusing**
- One pinned issue at a time

## Overlay island (while a session is running)

Idle pet stays sprite-only. With a session, a 228pt island sits beside the pet:

- Linear ID pill (opens the issue) + truncated title
- Clock — countdown of remaining planned time; after Continue, **count-up** of total session time with an **OT** mark
- Pause / resume (disabled during the zero-time hold)
- Status dropdown (same two-way `issueUpdate` as the Linear tab)

Pet click still opens the popover. Limit-alert bubbles (6s, display-only) stay; they yield to a check-in or overtime prompt.

## Today window layout

**Header:** title **Today** + weekday/date; **Planned** and **Check-in** pickers (presets + stepper 5–180 min).

**Hero** (active session):

- Linear ID (opens issue) + title
- Pause / resume
- Large clock (+ OT capsule in overtime)
- Status dropdown
- **Mark done**
- Zero-time / check-in prompt card when due

**Empty hero:** “Select a Linear issue to focus on.”

**Pin list:** in-progress issues from the existing Linear dashboard — ID, title, status, **Focus**. Projects / Initiatives stay in the popover.

**Today’s log:** sessions (issue, duration, overtime) and check-ins (Yes / No / Skip, note posted?). Drift count = today’s **No** check-ins.

## When planned time hits 0:00

Clock **holds at 0:00** for up to 30 seconds. Pet speech bubble: “Time’s up · ENG-142” / “Choose continue, finish, or done.” Popup title: “Time is up on ENG-142.” Actions, in order:

1. **Continue** — overtime on the same issue (primary). 30s with no press = same as Continue. The hold does **not** accrue overtime XP.
2. **Finish timer, leave in progress** — stop the clock; Linear stays started.
3. **Mark issue as done and finish timer** — existing completed-state `issueUpdate` + Done +2M if this is the first transition into completed.

Zero-time wins over a check-in. The deferred check-in fires after Continue.

## Check-ins

Cadence independent of the planned block. Default **30 min** (presets 30 / 60, custom 5–180). First fire is one interval after session start. Pauses with the session and on Mac sleep.

Prompt on the pet / desk: “Still on ENG-142?” Optional note field.

| Action | Local log | Linear |
|---|---|---|
| Yes | On-task | Comment only if a note is added |
| No | Drift | Comment only if a note is added |
| Skip | Nothing | No comment |

Comment body: `Check-in · Yes · ENG-142 · 32m` then the note. A posted note is the overtime **×2** flag for this session. Yes/No alone is not.

## Session XP

Same growth meter as time-open: **+1M per 10 minutes** via `applyCappedProgressXP` (not the shop wallet). Time-open is **suspended** while a session runs so the same wall clock is not paid twice. Linear Done stays **+2M flat**. Session XP is off if Time-open XP is toggled off. Daily cap is the existing 144M.

| Outcome | When | Session XP | Done +2M |
|---|---|---|---|
| On-time Done ×5 | Mark done during countdown, or on the 0:00 popup before Continue / auto-Continue | Planned intervals × 1M × 5 (default 50 min = 25M) | Yes, if first completed transition |
| Finish, leave in progress | Stop without completing Linear, without overtime | Planned intervals × 1M × 1 | No |
| Overtime + note ×2 | Continue / auto-Continue, and at least one check-in note posted this session | Planned 1× + OT intervals × 1M × 2 | Yes if later Mark done |
| Overtime, no note ×1 | Entered OT; Yes/No only, skip, or no note | Planned 1× + OT intervals × 1M × 1 | Yes if later Mark done |

Continue / auto-Continue closes the ×5 window forever for this pin. A note mid-OT upgrades remaining ticks and tops up already-paid OT to ×2. Sub-10-minute sessions grant 0 session XP (same quantization as time-open). Pause and sleep do not accrue clock or XP. On session end, time-open resumes from now (no sleep-gap catch-up). Restored sessions load **paused**.

## Defaults

| Setting | Default | Also |
|---|---|---|
| Planned block | **50 min** | 25 / 50 / 90 + custom 5–180 |
| Check-in | **30 min** | 30 / 60 + custom 5–180 |
| Auto-Continue | **30s** | Same as tapping Continue |

Overtime after Continue is unbounded and counts up from the planned length. Session time is **not** written back as a Linear estimate.

## Persistence

`Application Support/PokeTokenBar/focus-session.json` — planned/check-in minutes, optional paused session, last 200 log entries, log day.

## Key files

- `Sources/PokeTokenBar/Core/FocusSession.swift` / `FocusSessionStore.swift`
- `Sources/PokeTokenBar/UI/TodayDeskView.swift` (`TodayDeskController`, `SessionPromptCard`)
- `Sources/PokeTokenBar/UI/SessionOverlayView.swift`
- `Sources/PokeTokenBar/UI/LinearIssueControls.swift`
- `Sources/PokeTokenBar/UI/FloatingPetPanel.swift` / `PokeTokenBarApp.swift` / `PopoverView.swift`
- `Tests/PokeTokenBarTests/FocusSessionTests.swift`
