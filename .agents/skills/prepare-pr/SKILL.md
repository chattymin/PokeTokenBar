---
name: prepare-pr
description: Prepare, create, or update a PokeTokenBar pull request with an English Conventional Commits title, the repository PR template, and mandatory images for visible UI changes. Use for requests such as "PR 올려줘", "PR 만들어줘", "PR 본문 작성", "PR 수정", "create PR", or "update PR" in this repository.
---

# Prepare a PokeTokenBar PR

Use this repository's title and template rules even when a personal PR skill is
also active. The shared instructions live here; Claude Code discovers them via
`.claude/skills/prepare-pr`, and Codex via `.agents/skills/prepare-pr`.
Run commands from the repository root. Paths below are relative to that root.

## Title and body

Read `CONTRIBUTING.md` and `.github/PULL_REQUEST_TEMPLATE.md` before preparing or
updating the PR. Resolve the actual target repository and base branch, then read
the complete `base...HEAD` diff and `base..HEAD` commit range. Do not summarize
only the last commit or use unrelated work already on the branch as new work.

Write the title and body in English. Use a Conventional Commits title such as
`fix(home): retain idle usage history` or `docs: require UI images in PRs`.
Choose a type and optional scope that describe the final change; do not copy a
ticket prefix or a personal skill's title convention over repository rules.

Start the body from the current template. Fill `Summary`, select the actual
`Type of change`, and retain the template's checklist. Check an item only when
the performed work supports it; leave tests unchecked if they were not run or
added, and explain why when relevant. Report actual validation and limitations.
Keep the body in a UTF-8 file and pass it with `gh ... --body-file`.

## Mandatory UI images

Decide whether the full diff changes visible UI. Inspect changes outside
`Sources/PokeTokenBar/UI/` too: data, localization, resources, and settings can
change what users see. A change inside that directory triggers the local image
check; an outside change with visible effects needs `--ui-changes`. For changes
inside the UI directory that have no visible effect (such as comments or an
equivalent refactor), inspect the full diff and use `--no-ui-changes '<reason>'`.
Never use this declaration to excuse missing images for a visible change.

For every affected screen or state, embed images directly in `UI changes`:

- Existing screens: before and after images of the relevant state.
- New screens: explain that no previous screen exists and embed the new screen.
- Removed screens: show the previous screen and the resulting replacement or
  parent screen after removal.

If images are not ready, create them yourself as part of preparing the PR.
Reuse accurate existing images or capture the app; when capture is impractical,
render the relevant UI locally or draw it based on the actual change. Inspect
the result and attach it. Do not stop, ask the user to provide images, or request
separate permission merely because no image already exists. An authorized PR
creation/update includes producing and attaching its required UI images; a
local title/body preparation request keeps the generated images local too.

Actual app screenshots, local renders of production UI, and images drawn to
illustrate the changed UI are all accepted. Label them `App screenshot`,
`Sample-data render`, or `Illustration / mockup` as appropriate. Reuse existing
images only if they accurately depict the relevant version and state. Show the
change, not an unrelated app overview. Keep comparable data, language, theme,
and dimensions where practical. Inspect the generated images before using them;
an illustration demonstrates the design, not proof that the app was tested.

Existing local render harnesses can help when the running app is difficult to
capture. Create a temporary output directory, then use the relevant harness:

```sh
PTB_SCREENSHOT_DIR=<existing-dir> swift test --filter ScreenshotGenTests
PTB_ZERO_USAGE_SCREENSHOT_DIR=<existing-dir> swift test --filter ZeroUsageHomeRenderingTests
PTB_COLLECTION_SCREENSHOT_DIR=<existing-dir> swift test --filter CollectionReadabilityRenderingTests
```

Read the selected harness before using its output. Some AppKit controls and
scroll views do not render faithfully in tests; capture the running app when
those details are the change being demonstrated. Capture/render the base and
head separately when no accurate before image exists; do not reset the user's
working tree to obtain a before image. Do not regenerate release screenshots
merely to prepare a PR.

Use Markdown images such as `![After — sample-data render](https://...)` in the
template's Before/After table, without code formatting or four-space indentation.
Local paths and ordinary hyperlinks do not embed
usable images on GitHub. Upload through GitHub's PR editor when available, or
use an existing accessible image URL. If committing images is appropriate,
use a GitHub raw URL at their exact pushed commit and inspect the images for
private data and this repository's asset restrictions first. Do not publish
images to an unrelated host or change global tools/settings for this task.

Text alone never satisfies the UI requirement, including draft PRs. A missing
image or failure of one capture/upload method is not a publication blocker:
try the suitable available generation and attachment alternatives above.
Keep publication pending only when a concrete failure (such as unavailable
GitHub authentication, a network failure, or no usable attachment route) still
prevents completion. Then report what was attempted, the remaining blocker,
and the specific user action needed, retaining the prepared title/body/images.
Do not remove `UI changes` to bypass missing images. Remove that section only
when no visible UI changes exist.

## Check and publish

Run the shared local checker against the chosen base ref and the body file:

```sh
python3 scripts/check-pr.py --base <base-ref> --title '<title>' --body-file <body-file>
```

Add `--ui-changes` for visible changes outside the UI directory. Use `--head`
when checking a revision other than `HEAD`. Fix all reported failures before
publishing. The checker verifies structure and image URL syntax; additionally
verify that each URL displays the intended image on GitHub, that all affected
states are covered, and that the English wording and checked claims are true.
It does not build/test the app or prove that a remote image exists.

Publish only when the user's request authorizes PR creation/update. A request
to prepare a title/body authorizes local preparation only. Use `gh pr create`
or `gh pr edit` with the checked title and body file; preserve unrelated existing
PR metadata. Never force-push to make the workflow succeed. If push succeeds
but PR publication fails, report the pushed branch and missing/unchanged PR.
After publication, read back the title and body and inspect the image rendering
on GitHub. In Codex, attach a created or updated PR using the app's PR attachment
tool when available; Claude Code returns its URL. Report actual completion and
any unresolved limitation.
