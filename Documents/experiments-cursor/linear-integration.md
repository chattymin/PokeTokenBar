---
summary: "v3 Linear popover: Issues / Projects / Initiatives, lighter container queries, status dropdown, fold+hover, two-way issueUpdate, XP only on first completed transition."
read_when:
  - Changing Linear GraphQL, tabs, or completion XP
---

# Linear integration (shipped in v3)

Popover **Linear** tab. Status: **shipped in v3** in this worktree / `/Applications/PokeTokenBar v3.app`.

## Surfaces

Root segmented tabs, with SF Symbols closest to Linear’s chrome:

| Tab | Symbol | Sub-tabs |
|---|---|---|
| Issues | `circle` | In progress · Own completions today |
| Projects | `hexagon` | In progress · Production |
| Initiatives | `flag` | Active · Planned |

Issue cards show identifier, priority, title, description snippet, assignee, team, project, estimate, labels, dates, a **status dropdown** (every team workflow state — not a Done-only button), **Focus**, and open-in-Linear.

Projects and initiatives are foldable rows. The whole header row toggles fold; the open-in-Linear control does not. The header highlights on hover. Nested issues reuse the same card (status + Focus).

The Linear header also has a calendar button (**Open Today**) that opens the Today desk. That path is documented in [session-timer-today-desk.md](./session-timer-today-desk.md).

## GraphQL complexity cap

Linear rejects a single request over **10,000 complexity points**. Nesting `team.states` (default page 50) under `projects { issues }` and `initiatives { projects { issues } }` blew that cap (HTTP 400). The old **issues-only fallback** then looked like empty Projects / Initiatives while Issues still worked.

Shipped fetch (`LinearClient.fetchIssueDashboard`):

1. **Issues-only query** — completed-since + in-progress issues, with full `team.states`.
2. **Separate lighter container queries**, tried in order and merged:
   - filtered projects (`status.type` in `started`) + initiatives (`Active` / `Planned`) with light issue nodes (no nested `team.states`)
   - salvage: unfiltered containers, no nested issues
   - bare: status objects only (schema-drift fallback)
3. Copy workflow states onto nested issues from the issues query; look up remaining teams once (`teams(filter: { id: { in } })`).
4. Issues-only is the last resort after those attempts, not a silent success that blanks containers.

Captured in `docs/reference/defect-log.md` under **외부 GraphQL**. Tests: `testFetchIssueDashboardSalvagesContainersWhenFilteredQueryRejected`, field-error null projects, bare query still loads containers.

## Project / initiative filters

Live workspace: project status **type `started`** covers both **In Progress** and a custom **Production** name. UI splits them:

- Production tab: name/type token is `production` or `in production`
- In progress tab: started/active/in progress, excluding Production

Initiatives use the `InitiativeStatus` scalar: **Active** / **Planned**.

## Two-way status (`issueUpdate`)

`LinearClient.updateIssueState` mutates `issueUpdate(id:, input: { stateId })`. The popover, overlay island, and Today desk share `LinearIssueStatusPicker`.

XP is **not** paid on every Done click:

- `UsageStore.updateLinearIssueState` returns a completion payload only when the issue **enters** a completed state (`LinearClient.creditedCompletion`: was not completed, new `stateType == completed`).
- `LinearRewards.evaluate` then grants **+2M growth XP per newly credited issue ID**. First successful poll **seeds IDs with 0 XP** so already-done work is not backfilled. Later transitions of the same ID do not pay again (`linearCreditedIssueIDs`).

Done +2M stays flat. Session-timer multipliers do not apply to this grant (see [session-timer-today-desk.md](./session-timer-today-desk.md)).

## Comments

`commentCreate` exists for Focus check-in notes (optional body). No-note Yes/No stays on the local Today log so the issue is not spammed every interval.

## Key files

- `Sources/PokeTokenBar/Core/LinearClient.swift`
- `Sources/PokeTokenBar/Core/UsageStore.swift` (`updateLinearIssueState`, `createLinearComment`)
- `Sources/PokeTokenBar/UI/LinearIntegrationView.swift`
- `Sources/PokeTokenBar/UI/LinearIssueControls.swift`
- `Tests/PokeTokenBarTests/LinearRewardsTests.swift`
