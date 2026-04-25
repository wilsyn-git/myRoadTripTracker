# Issues (cache)

> Synced from `gh issue list` by `/catchup`. Last sync: 2026-04-25.
> Future sessions can read this instead of hitting the API.

## Open

| #  | Title                                              | Type        | Opened     |
|----|----------------------------------------------------|-------------|------------|
| 5  | Ensure thread safety for persistence operations    | bug         | 2026-04-04 |
| 4  | Potential race condition in SceneDelegate          | bug         | 2026-04-04 |
| 3  | Add error recovery to PersistenceController init   | bug         | 2026-04-04 |
| 2  | Simplify CloudKit sharing path                     | enhancement | 2026-04-03 |
| 1  | Fix sharing logic: Records not accessible for invitees | bug     | 2026-04-03 |

Issue #1 was the original "shared records invisible" report that led to the SwiftData → Core Data migration. Real-time sync now works on `main`, so this may be ready to verify-and-close.

## Closed

(none recorded)

## Silent gaps — roadmap items not yet tracked as issues

From `docs/sharingSpec.md` Section 14 ("Implementation Status") — these are spec'd but not shipped, not in the issue list:

- **Universal Links** (Section 1.2 + 12.4): associated domains + AASA file. Without these, the share link only works if the recipient already has the app; the deferred-deep-link install flow doesn't work.
- **Sync status indicators** (Section 11.3): subtle UI for queued/syncing/synced.
- **Privacy policy page** (Section 10.4): required for App Store submission.
- **Location permission deferral** (Section 10.3): permission should be requested only on first plate tap, not earlier.

Recommend opening GitHub issues for each so they land in this list automatically on the next `/catchup`.
