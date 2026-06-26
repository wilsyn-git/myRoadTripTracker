# Tier 1 Fixes — Design Spec

**Date:** 2026-06-26
**Source:** `docs/agy_general.md` review pass (findings 2.1, 2.2, 2.3), verified against source.
**Scope:** Three independent correctness fixes, shippable together. Finding 2.4 ("Leave Trip") is
deliberately carved out into a separate spec (Spec B) because it requires a CloudKit research spike.

---

## Overview

Three confirmed defects from the usability/performance review, all in the "real correctness" tier:

| ID  | Title                                   | File                       | Severity framing                |
|-----|-----------------------------------------|----------------------------|---------------------------------|
| 2.1 | Location authorization race             | `LocationManager.swift`    | Real bug — silent data loss     |
| 2.2 | Share-acceptance robustness             | `PersistenceController.swift` | Defensive hardening + UX     |
| 2.3 | Failed save poisons the managed context | `ComposeEntryRow.swift`    | Real bug — cascading failures   |

These are independent (no shared state, no ordering dependency) and map cleanly to three
subagent-driven tasks.

---

## Fix 2.1 — Location authorization race

### Current behavior
`LocationManager.requestCurrentLocation(timeout:)` (`LocationManager.swift:32-39`):

```swift
if authorizationStatus != .authorizedWhenInUse && authorizationStatus != .authorizedAlways {
    requestPermission()
    try? await Task.sleep(for: .milliseconds(500))
    guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
        return nil
    }
}
// ... existing retry loop (lines 44-56) already uses continuations correctly ...
```

### Root cause
The system permission dialog is asynchronous and takes seconds for the user to read and respond.
The fixed `500ms` sleep almost always expires while the dialog is still on screen, so the `guard`
fails and the method returns `nil`. The caller then saves the **first** plate sighting at `(0, 0)`
— even when the user taps **Allow**. Only the authorization gate is broken; the location-fix retry
loop below it is already correct.

### Design
Replace the fixed sleep with an `await` on the real authorization decision, delivered via the
existing `locationManagerDidChangeAuthorization` delegate callback.

- Add `private var authorizationContinuations: [CheckedContinuation<CLAuthorizationStatus, Never>] = []`.
- Branch on current status before requesting:
  - `.notDetermined` → call `requestWhenInUseAuthorization()`, `await` a continuation that is resumed
    inside `locationManagerDidChangeAuthorization`, then re-evaluate.
  - `.denied` / `.restricted` → return `nil` immediately. No dialog will appear, so awaiting a
    callback would hang forever.
  - `.authorizedWhenInUse` / `.authorizedAlways` → fall through to the existing retry loop.
- Resume **all** pending authorization continuations inside `locationManagerDidChangeAuthorization`
  with the new status, then clear the array (same pattern already used for `locationContinuations`).
- Add a modest safety timeout around the auth `await` (e.g. race against a short `Task.sleep`) so a
  pathological case (Screen Time restriction, MDM, dialog never resolving) cannot hang the call
  indefinitely. On timeout, return `nil`.

Sketch:

```swift
private func awaitAuthorizationDecision() async -> CLAuthorizationStatus {
    await withCheckedContinuation { continuation in
        authorizationContinuations.append(continuation)
        manager.requestWhenInUseAuthorization()
    }
}
```

```swift
nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
        self.authorizationStatus = manager.authorizationStatus
        let pending = self.authorizationContinuations
        self.authorizationContinuations = []
        for continuation in pending {
            continuation.resume(returning: manager.authorizationStatus)
        }
    }
}
```

### Edge cases
- `locationManagerDidChangeAuthorization` also fires once at startup. At that point there are no
  pending continuations, so the resume loop is a no-op — safe.
- If the user denies, the granted check fails and we return `nil`, which preserves the documented
  privacy behavior: plates can still be marked with coords `(0, 0)`.

### Privacy invariant
Unchanged. Still one-shot, when-in-use only. No background, no Always, no route tracking.

### Files touched
- `myRoadTripTracker/myRoadTripTracker/Services/LocationManager.swift`

---

## Fix 2.2 — Share-acceptance robustness

### Current behavior
`PersistenceController.acceptShare(metadata:)` (`PersistenceController.swift:224-228`):

```swift
func acceptShare(metadata: CKShare.Metadata) {
    guard let store = sharedPersistentStore else {
        shareAcceptanceError = "Unable to accept share: storage is not ready. Please restart the app and try again."
        return
    }
    ...
}
```

### Framing
This is **defensive hardening**, not a proven crash. The container reads loaded stores into
`_sharedPersistentStore` synchronously immediately after `loadPersistentStores` (lines 126-127),
and local SQLite stores load synchronously in practice — so on cold launch, accessing
`PersistenceController.shared` fully runs `init` (including store loading) *before* `acceptShare`
is ever called. The guard therefore rarely (if ever) fires today. The fix removes a scary,
user-blaming error message and makes acceptance resilient regardless of load timing.

The sibling app `~/code/iosJournal` has the identical guard with no queue, and uses an
`importWaiters`-style array to gate on readiness — the precedent we mirror here.

### Design
- Add `private var pendingShareMetadata: [CKShare.Metadata] = []`.
- In `acceptShare`, when `sharedPersistentStore == nil`: append the metadata to the queue and
  return **without** setting `shareAcceptanceError`.
- Add `private func drainPendingShares()` that, if `sharedPersistentStore != nil`, dequeues all
  pending metadata and runs each through the normal acceptance path.
- Call `drainPendingShares()` at the end of `init`, after `_sharedPersistentStore = sharedStore`
  is assigned.
- Genuine errors returned by `acceptShareInvitations` continue to surface via
  `shareAcceptanceError` exactly as today.

### Edge cases / limitations
- Because store loading is synchronous in practice, the queue is belt-and-suspenders. If Apple ever
  loads stores asynchronously, fully robust draining would require assigning `_sharedPersistentStore`
  inside the `loadPersistentStores` completion handler and draining there. That is a larger change to
  currently-working code and is **out of scope**; noted here for the record.

### Files touched
- `myRoadTripTracker/myRoadTripTracker/Services/PersistenceController.swift`

---

## Fix 2.3 — Failed save no longer poisons the context

### Current behavior
`ComposeEntryRow.submitEntry()` (`ComposeEntryRow.swift:118-139`):

```swift
let entry = ObservationEntry(context: viewContext, ...)
entry.trip = trip
do {
    try viewContext.trySave(contextInfo: "addObservation")
} catch {
    let nsError = error as NSError
    saveError = "[\(nsError.domain) \(nsError.code)] \(nsError.localizedDescription)"
    return
}
```

### Root cause
On a failed `trySave()`, the catch reports the error and returns but leaves the freshly inserted
`ObservationEntry` in `viewContext`. Every subsequent context save (marking a plate, editing the
trip) re-attempts to persist the bad object, causing repeated failures or duplicated garbage.

### Design
In the catch block, remove the just-inserted object before reporting the error:

```swift
} catch {
    viewContext.delete(entry)   // surgical: drop only the object we inserted
    let nsError = error as NSError
    saveError = "[\(nsError.domain) \(nsError.code)] \(nsError.localizedDescription)"
    return
}
```

Surgical delete is preferred over `viewContext.rollback()` because rollback discards *all* pending
changes in the context, which could drop unrelated unsaved edits. Deleting an inserted-but-never-saved
object simply removes it from the context (and cleans up the `trip` inverse relationship); no
follow-up save is required.

### Follow-up note (out of scope for this spec)
Audit sibling insert-then-save sites (e.g. plate marking, participant creation) for the same
missing cleanup, and apply the same pattern if found. Flagged, not fixed here.

### Files touched
- `myRoadTripTracker/myRoadTripTracker/Views/ComposeEntryRow.swift`

---

## Verification

No unit/UI test targets exist in this project (per CLAUDE.md), so verification is build + manual:

1. **Compile check** (all three fixes):
   ```bash
   xcodebuild -project myRoadTripTracker/myRoadTripTracker.xcodeproj \
              -scheme myRoadTripTracker \
              -destination 'platform=iOS Simulator,name=iPhone 16' build
   ```
2. **2.1 — manual, on a real device with iCloud:** delete + reinstall the app, tap a plate for the
   first time, wait several seconds before tapping **Allow**, then confirm the first sighting records
   a real coordinate (not `0,0`). This is the one fix fully verifiable by hand.
3. **2.2 / 2.3 — hard to reproduce live.** Rely on compile + code review. For 2.3, optionally confirm
   by code inspection that the inserted entry is removed on the failure path.

Honest limit: 2.2 and 2.3 cannot be deterministically exercised without contrived failure injection;
this is stated rather than papered over.

---

## Out of scope

- **Finding 2.4 ("Leave Trip")** → separate spec (Spec B), gated on a CloudKit research spike.
  Reference implementation already located: `~/code/iosJournal` `PersistenceController.leaveShare`
  (uses `share.currentUserParticipant` + `share.removeParticipant` + `persistUpdatedShare`, with an
  owner-guard).
- **Section 1.x performance** and **Section 3.x accessibility** findings — later tiers.
- Async-store-loading robustness for 2.2 (see limitation note above).
- Sibling insert-then-save cleanup for 2.3 (see follow-up note above).

## References

- `docs/agy_general.md` — original review findings.
- `~/code/iosJournal/Glade/Persistence/PersistenceController.swift` — share/store patterns mirrored here.
