---
summary: "Create Linear issues from menubar, floating pet, and Today via one composer window; timer reset, add time, and Unfocus-forfeit with a warning and red feedback."
read_when:
  - Adding Linear issueCreate
  - Changing focus session settle, pin, or overlay timer controls
---

# Linear issue create and timer controls

Approved 2026-09-12. Implementation follows this spec; do not reopen the XP-on-unfocus payout designs.

This file lives under `docs/reference/` because the repo publishes only that docs tree (`docs/*` is gitignored).

## Goal

Create a Linear issue from three app surfaces without duplicating forms. While a focus session is running, the user can reset the clock, add remaining time, or Unfocus — Unfocus **forfeits** remaining session XP so abandoning a task is visibly worse than finishing it.

## Non-goals

- Creating projects or initiatives
- Linear templates, cycles, estimates, due dates, parent/sub-issues, or attachments
- Posting create as a Linear comment
- Clawing back XP already granted (Continue overtime already paid planned ×1)
- Changing Mark Done completion XP (still first-complete 2.0M Linear Done XP + session settle)

## Surfaces

One shared **New issue** `NSWindow` (not inline on the island or stuffed into the popover). Identifier must not be treated as a Settings placeholder (`LaunchWindowPolicy` / Today desk pattern: dedicated `NSWindow` identifier, e.g. `PokeTokenBar.NewLinearIssue`).

| Trigger | Control |
|---|---|
| Menubar popover, Linear tab | `+` in the Issues header (beside refresh / Today) |
| Floating pet | Right-click **New issue**. If a session is running, also `+` on the island title row |
| Today desk | `+` in the header |

Disabled when Linear integration is off or no API key, with the existing setup hint. Closing the composer does not affect a running session.

## Composer fields

Linear `issueCreate`. Team is required by Linear.

| Field | Required | Default |
|---|---|---|
| Title | yes | empty |
| Description | no | empty markdown |
| Team | yes | last-used team id (`UserDefaults`); else first team from the catalog |
| Project | no | none; list filtered to the selected team |
| Assignee | no | viewer (“me”); can clear to unassigned |
| Labels | no | none; team labels, multi-select |
| Status | no | team default workflow state if present, else first `unstarted` / `backlog` type |

Footer: **Create** and **Create & Focus**. Create is disabled while title/team are empty or a submit is in flight.

### Create

1. `issueCreate`
2. Persist last team id
3. Close composer
4. Refresh Linear dashboard
5. Issue appears in the matching list (In Progress if that is the chosen status)

Does **not** pin, warn, or change a running session.

### Create & Focus

If **no** session is running: create as above, then `pin` the new issue and start the timer (open Today).

If a session **is** running: show the **Unfocus forfeit warning first**. Cancel → no create, no pin. Confirm → forfeit the current session, then create and pin the new issue.

Focusing an **existing** issue from a card while a session is running uses the same warning (today’s silent `finishLeavingInProgress` on switch is removed).

## Timer controls (island + Today)

Not on the composer.

### Reset

Elapsed back to 0:00, **planned length unchanged**, still focused, phase `running`, not overtime. No XP clawback. If elapsed is already 0, no-op (no dialog). If elapsed > 0, confirm before reset.

### Add time

Presets **+5 / +10 / +15 / +30** minutes. Clamp planned length to 5–180 minutes.

Adds **N minutes onto remaining countdown** as exact seconds (`+5` → `+300s`). Does **not** replace remaining with N.

While counting down (remaining > 0):

`newPlannedSeconds = min(maxMinutes * 60, currentPlannedSeconds + N * 60)`

which is the same as:

`newPlannedSeconds = min(maxMinutes * 60, elapsedSeconds + remainingSeconds + N * 60)`

Overtime / `awaitingChoice` (remaining ≤ 0): remaining becomes N minutes from now:

`newPlannedSeconds = min(maxMinutes * 60, elapsedSeconds + N * 60)`

Exit `awaitingChoice` and `overtime` into `running`. `fiveXOpen` stays false if the on-time window already ended. No XP clawback.

If planned is already 180 and still counting (elapsed + remaining at cap), Add time is a no-op. If elapsed is already at/past the 180-minute cap, Add time is a no-op. Overtime before the cap can still extend remaining from now: `planned = min(180*60, elapsed + N*60)`.

### Unfocus (forfeit)

Unpin, stop the clock, Linear status **unchanged**, **0 XP** from this settle. History kind `forfeited`.

**Warning first** (island and Today). Cancel is a no-op.

Warning must show both amounts they are giving up (computed, not paid):

1. **Leave-in-progress XP** — what `FocusTick.settleLeaveInProgress` would pay now
2. **On-time Done package** — session ×5 on planned intervals **plus** the 2.0M Linear completion grant they would get from Mark Done (even if the session is already in overtime; this is the “you walked away from finishing” number)

Confirm → forfeit. Already-granted Continue XP is **not** clawed back.

**Finish timer, leave in progress** still pays session XP. **Mark Done** still pays session settle + first-complete Linear 2.0M.

### Red feedback after forfeit

Must read as a mistake, not a success toast:

- Pet speech bubble in **red** / destructive styling (same 6s chassis as other bubbles)
- Today log line `Forfeit · {id} · −{leaveInProgressXP}` (red)
- `FocusIssueHistory` finish kind `forfeited` so a later completed card can show the forfeit, not a leave-in-progress payout

## Architecture

| Unit | Responsibility |
|---|---|
| `LinearClient` | Catalog fetch (teams + states, projects, members, labels) in **split** queries under Linear’s 10k complexity cap. `issueCreate`. |
| `UsageStore.createLinearIssue` | Gate on integration/key, call client, last-team defaults, refresh dashboard, surface errors. |
| `LinearIssueComposer` | One window, form UI, Create / Create & Focus. |
| `FocusTick.resetClock` / `addRemaining` / `unfocusForfeit` | Pure clock/settle math; forfeit returns 0 XP and the two warning amounts. |
| `FocusSessionStore` | Pin/switch goes through forfeit warning; persist `forfeited` history. |

Do not add `== "claude_code"`-style provider branches. Localization: en / ko / ja.

## Errors

Composer failures: orange caption, same style as session notes. Network/GraphQL failure does not close the window or pin. Unfocus cancel: no-op. Missing completed-state on Mark Done: unchanged existing behavior.

## Tests (trigger branches)

- `issueCreate` sends teamId + title; optional fields omitted when empty
- Catalog queries stay under complexity expectations (no nested `team.states` under every project issue)
- Create does not pin; Create & Focus pins when idle
- Create & Focus with a live session: cancel warning → no create; confirm → forfeit then pin
- Pinning a different existing issue with a live session uses forfeit, **not** `settleLeaveInProgress`
- Forfeit grants 0 XP; history kind `forfeited`; warning amounts match leave-in-progress and Done package
- Later Mark Done on a forfeited issue still awards first-complete Linear XP
- Reset with elapsed 0 is no-op; reset with elapsed > 0 needs confirm and returns to full planned countdown
- Add time from running adds N onto remaining (25 planned / 10 elapsed / +5 → remaining 20, not 5)
- Add time from awaitingChoice / overtime restores a remaining countdown of N minutes from now
- Add time uses exact seconds (not floored minutes)
- Planned clamp 180; no-op when already at cap while counting; overtime can still extend from now up to cap
- Missing Linear key: composer trigger disabled
