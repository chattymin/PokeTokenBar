# feat(save): add local auto-backup snapshots, corruption recovery, and restore UI

## Summary

This PR introduces an automated local snapshot backup and recovery mechanism for `CompanionState` without modifying the core state schema or depending on external cloud providers.

Key enhancements:
- **Periodic automatic snapshots with rotation**: Takes point-in-time snapshots of the companion state into `<stateDir>/snapshots/` at an interval of at least 12 hours during regular play and saves. Retains the newest 10 snapshots automatically and prunes older ones.
- **Automatic corruption self-healing**: If `companion-state.json` is corrupted or fails to decode at startup, the app preserves the corrupted file as `.corrupt` and automatically restores from the latest valid snapshot instead of starting from a blank state.
- **Settings UI & 1-click rollback**: Adds an "Automatic Backups (Snapshots)" section within the Settings `Backup & Transfer` group:
  - Instant "Create snapshot" button for manual restore points.
  - Snapshot list displaying companion sprite, creation timestamp, Pokédex count, and lifetime tokens.
  - "Restore" button triggering a safety confirmation dialog comparing target vs current progress, taking a pre-restore backup snapshot, and seamlessly applying the rollback.
- **Full 7-language localization & safety**: All strings are routed through `Localization.swift` across all 7 supported languages (`ko`, `en`, `ja`, `es`, `fr`, `pt`, `de`), without Hangul string literals in UI sources. `CompanionState` stored properties remain unmodified, strictly preserving `SaveTransferTests` field classification.

## Type of change

- [ ] Bug fix
- [x] New feature
- [ ] Refactor / cleanup
- [ ] Documentation
- [ ] Other:

## UI changes

| Before | After |
| ------ | ----- |
| The Settings `Backup & Transfer` section only provided manual "Export save" and "Import save" buttons requiring manual JSON file management via system file dialogs. | The Settings `Backup & Transfer` section now includes an "Automatic Backups (Snapshots)" panel with a "Create snapshot" button and a scrollable list of recent restore points showing companion thumbnails, timestamp, Pokédex count, token count, and a 1-click "Restore" button with safety confirmation. |

## Checklist

- [x] `swift build` and `swift test` pass locally
- [x] PR title and description are written in English
- [x] UI changes are described above (before/after — images optional)
- [x] No copyrighted assets, secrets, or private tooling references are committed (see [CONTRIBUTING](../CONTRIBUTING.md))
- [x] Tests were added or updated for this change
