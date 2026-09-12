---
summary: "Readable export of the floating-timer-feature-map canvas — locked v1 decisions that shipped in PokeTokenBar v3."
read_when:
  - Comparing the Today / overlay implementation to the locked spec
---

# Session overlay + Locu desk — canvas export

Export of `floating-timer-feature-map.canvas.tsx` (12 September 2026). Structure and locked decisions only — not raw TSX.

**Implementation status:** these v1 decisions **shipped in v3**. See [session-timer-today-desk.md](./session-timer-today-desk.md) for the running UI (calendar buttons, pet menu, Focus).

## Intent

Always-visible timer pinned to one Linear issue, a Locu-style Today desk, and pet check-ins that can comment on that issue. Menu bar stays the remote — not a stretched popover.

Grounded in then-current PokeTokenBar: floating pet `NSPanel`, Linear Issues / Projects / Initiatives, Done mutation, time-open XP + 2M completion XP. Locu / Focusmo research 12 Sep 2026.

Stats on the canvas: **A + B** island timer + Linear session · **Locu desk** dedicated Today window · **Check-ins** 30m / 1h / custom.

## What already existed (do not rebuild)

- Pet already always-on-top (drag vs click, Spaces, sleep hide, 6s speech bubbles).
- Linear already listed in-progress issues and two-way completed them.
- Time-open XP already paid +1M / 10 min while the app is open.
- v1 adds **session XP on that same meter**, with ×5 / ×2 / ×1 — not a second overlay system, not a new currency.

## Three surfaces

Locu and Focusmo both split glance / island / window. v1 does the same, desk as Locu (option A) — not companion HQ, not a shadcn sidebar.

| Surface | Job in v1 | Not this surface |
|---|---|---|
| Menu bar popover (360px) | Remote: usage, companion, Linear browser. Pin / Focus on an issue card. | Not the timer workspace. No Today hero. |
| Pet + island overlay | Always-visible identity + clock. Check-in window anchors here. Pause / Done. | Not Projects / Initiatives. Not a notes editor. |
| Locu desk window | Today hero timer, pinned issue, in-progress pin list, today’s session + drift log. | No calendar rail, no bag/dex/shop, no notes app. |

### Overlay anatomy

Grow the existing pet panel into a pet + island composite while a session is running. Idle pet stays sprite-only. One pinned Linear issue at a time.

| Element | Shows | Interaction |
|---|---|---|
| Pet sprite | Current representative, same size setting | Click opens popover. Right-click gains **Open Today**. |
| Issue identity | Linear ID pill + truncated title | Click ID opens the issue in Linear. |
| Clock | Planned: countdown. At 0:00: holds until a choice. Overtime: count-up session total with an OT mark. | Pause / resume while running. At zero the popup holds 30s, then auto-Continues. |
| Done | Same two-way complete as the Linear tab | Existing complete path; credits 2M XP; existing Done bubble. |

Limit-alert bubbles stay 6s / display-only. They yield to a check-in or overtime prompt; they do not host Yes/No.

### Shipped mapping (vs canvas)

- Overlay ships a **status dropdown** (any workflow state) rather than a dedicated Done-only control; Today’s hero also has **Mark done**.
- Open Today: popover **footer** calendar, Linear **header** calendar, pet menu, and **Focus** (starts/switches session and brings Today forward).
- Today is a titled `NSWindow`, not Settings and not the popover.

## When planned time hits 0:00

Hitting zero is felt, then 30 seconds to choose. Clock holds at 0:00. No button → auto-Continue into overtime on the same issue. Completing the planned block always pays session XP, including when the 30s timer auto-Continues.

| Moment | Clock | What you see / XP |
|---|---|---|
| Focus ENG-142 | Countdown from planned length (default 50:00) | Overlay + desk hero show ID, title, pause. Time-open XP paused. |
| Planned hits 0:00 | Holds at 0:00 up to 30s. No overtime yet. | Completion bubble + three-action popup. Planned XP pending — multiplier depends on the next action. |
| Continue (tap or 30s auto) | Count-up of total session time from the planned length with OT | 5× window closes. Planned XP settles at 1×. OT minutes then accrue at 1× or 2× (note?). |
| Finish timer, leave in progress | Session clock stops. Idle pet; last session saved locally | Issue stays in progress. Planned XP at 1×. No OT XP. Time-open resumes. |
| Mark done during countdown or 0:00 popup | Session ends. Never entered overtime. | Planned XP ×5 + flat Done +2M. Time-open resumes. |

**Zero-time popup (the decision):** small panel on the pet, not Notification Center. Title: Time is up on ENG-142. Three actions: Continue (primary) · Finish timer but leave in progress · Mark issue as done and finish timer. No choice for 30s → Continue. The 30s wait does not accrue overtime XP.

**Extra cue:** reuse the 6s speech-bubble chassis. Copy: Time’s up · ENG-142. The bubble can dismiss while the popup stays. No new animation system.

Session time: one running interval per pin. Pause and Mac sleep do not accrue clock or XP. After Continue, overtime is unbounded. Total = planned used + overtime. Shown on overlay, desk hero, and today’s log — **not** written back as a Linear estimate. Pinning another issue ends the previous session without completing it.

## Pet check-ins

Focusmo-style accountability, wired to the pinned Linear issue. Interval independent of the planned timer. Check-ins fire only while a session is running.

| Piece | v1 behavior |
|---|---|
| Cadence | 30 min, 1 hour, or custom minutes (5–180). Default 30 min. Pauses with the session and on sleep. |
| Window | Small interactive panel on the pet (not the 6s speech bubble). Stays until Yes, No, or Skip. Prompt: Still on ENG-142? |
| Yes | On-task. Logged locally. No Linear comment unless a note is added. |
| No | Drifted. Logged locally. Session keeps running (do not auto-pause). Comment only if a note is added. |
| Add note | Optional field. Posts `commentCreate`. That note is the only overtime ×2 context. Yes/No alone does not count. |
| Skip / dismiss | No local drift, no comment. Next interval from now. |
| Collision | Zero-time popup wins. Check-in waits until that prompt is dismissed, then fires. |

Linear comment shape (only with a note): `Check-in · Yes · ENG-142 · 32m` then the user’s text. No-note Yes/No stays on the desk log.

## Locu desk (dedicated window)

Option A: Today is the home. Open from the popover, from the pet menu (Open Today), or when focusing if the desk should come forward. Closing the desk does not stop the session.

| Region | v1 content | Stolen from / skipped |
|---|---|---|
| Titlebar | Date + app name | Locu date/workspace. Normal Mac window chrome. |
| Today hero | Large pause + clock, ID pill, title, Done. Empty: Select a Linear issue to focus on. | Locu pause + 58:59 hero. No calendar now-line. |
| Pin list | In-progress issues from the existing Linear dashboard. Focus pins one. | Locu priority list with Linear IDs. Projects/Initiatives stay in the popover. |
| Today log | Sessions (issue, start, duration, OT). Check-ins (Yes/No/Skip, note posted?). Drift count. | Focusmo accountability without an activity timeline. |
| Right rail | None in v1 | Skip Locu all-day calendar. |
| Bottom tabs | None in v1 — this window is Today only | Skip Locu Today/Tasks/Notes. Companion bag/dex/shop stay in the popover. |

### Overlay vs Linear tab vs desk

One data set (the existing Linear dashboard). Three jobs.

| Action | Popover Linear tab | Overlay | Desk |
|---|---|---|---|
| Browse Issues / Projects / Initiatives | Yes — current tabs stay | No | In-progress issues only |
| Pin / Focus one issue | Focus control on the issue card | Shows the pin; cannot browse | Hero empty state + pin list |
| Watch the clock | No | Always | Hero, while the window is open |
| Mark Done | Status dropdown | Status dropdown | Status dropdown + Mark done |
| Check-in Yes/No + note | No | The prompt lives here | Log + same prompt on the hero |
| Open issue in Linear | Existing | ID click | ID click |

## Session XP multipliers

Same growth meter as time-open: +1M per 10 minutes of running session time. Time-open paused while a session runs. Linear Done stays a flat +2M — never multiplied.

| Outcome | When | Session XP | Done +2M |
|---|---|---|---|
| On-time Done ×5 | Mark done during the planned countdown, or on the 0:00 popup before Continue / auto-Continue | Planned intervals × 1M × 5. Default 50 min = 25M. | Yes, still +2M flat |
| Finish, leave in progress | Stop the clock without completing Linear, and without entering overtime | Planned intervals × 1M × 1. No 5×. | No |
| Overtime + note ×2 | Continue or 30s auto-Continue, and at least one check-in Add note posted a Linear comment this session | Planned 1× + overtime intervals × 1M × 2 | Yes if they later Mark done |
| Overtime, no note ×1 | Entered overtime; Yes/No only, skip, or no check-in note | Planned 1× + overtime intervals × 1M × 1 | Yes if they later Mark done |

**How the pieces settle**

- Planned minutes are always a 1× base (floor of running minutes / 10). The 5× is a settlement bonus only when Done lands before overtime. Continue or auto-Continue closes that window forever for this pin.
- Overtime minutes accrue on the same 10-min tick after Continue. Rate is 1× unless a check-in note was posted during this session — then all OT minutes are 2×. A note mid-OT upgrades remaining ticks and tops up already-paid OT to 2×.
- Abort before 0:00 without Done: 1× for completed intervals only. Sub-10-min sessions grant 0 session XP plus Done +2M if they marked done.

**Caps, pause, toggle**

- Session XP counts against the existing time-open daily cap (144M). 5× of a 50-min block is 25M — large, but not a 5× on Done. Pause and sleep do not accrue clock or XP. The 30s hold at 0:00 does not accrue OT.
- If Time-open XP is toggled off, session XP is off too. Done +2M still pays. On session end, time-open resumes from now (no sleep-gap catch-up).

## Defaults

| Planned block | Check-in interval | Then auto-Continue |
|---|---|---|
| 50 min | 30 min | 30s |

Planned length also offers 25 / 50 / 90 plus custom 5–180 min. Check-in: 30 / 60 / custom 5–180. First check-in is one interval after session start, not at minute zero.

## v1 scope vs later vs skip

| Feature | Fit |
|---|---|
| Pet + island: pinned Linear issue + timer | **v1** (shipped) |
| Focus pin from Linear tab and from desk | **v1** (shipped) |
| Zero-time popup; 30s hold then auto-Continue | **v1** (shipped) |
| Session XP: on-time Done ×5, OT note ×2, else ×1; Done +2M stays flat | **v1** (shipped) |
| Check-ins 30m / 1h / custom; Yes/No + note → Linear comment | **v1** (shipped) |
| Locu desk: Today hero + pin list + session/drift log | **v1** (shipped) |
| Pomodoro work/break cycles | Later |
| Desk tabs for Tasks / companion / usage | Later |
| App & site blocker | Out of scope |
| Auto app/site activity timeline | Out of scope |
| Notes app / floating notes | Out of scope |
| Calendar / meeting alerts | Out of scope |
| Invoice export / Toggl / other task apps | Out of scope |

Canvas closer: “Zero-time, 30s auto-Continue, and session multipliers (×5 / ×2 / ×1) are locked. Done +2M stays flat.” That lock shipped.
