# Leave Trip (Spec B / finding 2.4) — Design Spec

**Date:** 2026-06-26
**Source:** `docs/agy_general.md` finding 2.4, carved out of the Tier 1 batch for a CloudKit research spike.
**Reference implementation:** `~/code/iosJournal` `PersistenceController.leaveShare` (same two-store CloudKit architecture, in production).

---

## Problem

A participant who joined a shared trip cannot cleanly leave it, and the only way to remove it from their list is destructive:

1. **"Leave" doesn't leave.** `ParticipantsView.leaveTrip` (`ParticipantsView.swift:70-73`) calls `removeParticipant` which only does `viewContext.delete(participant)` on the local `TripParticipant`. The `Trip` stays in the shared store and the user stays in the `CKShare`, so the trip never disappears.
2. **The delete footgun.** `ContentView` shows a "Delete Trip" context menu on *every* card (`ContentView.swift:43-50`); the alert (`:86-97`) calls `viewContext.delete(trip)` unconditionally. For a *joined* trip this propagates a delete through CloudKit and **removes the trip for everyone, including the owner**.

## Goal

Let a participant truly leave a shared trip (severing CKShare membership without destroying the shared record), and make the destructive delete owner-only. Owner behavior is unchanged.

## Scope

**In:** participant leave-share; owner/participant branch on the `ContentView` context menu; post-leave UX (dismiss to root + confirmation toast).
**Out (flagged):** owner-revoke-participant (the owner's "Remove" swipe in `ParticipantsView` has the same bug class — only deletes the local `TripParticipant`, never revokes CloudKit access — template is iosJournal `revokeParticipant`); finding 3.3 `CKContainer.default()` mismatch (the leave path sidesteps it by using `share.currentUserParticipant`).

---

## 1. Core — `PersistenceController.leaveSharedTrip(_:)`

New method, mirroring iosJournal's `leaveShare`:

```swift
/// Leave a shared trip you joined as a participant. Removes ONLY your own CKShare participant
/// (never if you are the owner), then lets NSPersistentCloudKitContainer purge the local mirror.
/// All CloudKit work runs on a background context: persistUpdatedShare can block >10s and would
/// trip the iOS watchdog (0x8BADF00D) on the main thread.
func leaveSharedTrip(_ trip: Trip) async throws {
    let objectID = trip.objectID
    guard let store = privatePersistentStore else {
        throw NSError(domain: "PersistenceController", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Private store not loaded."])
    }
    let container = persistentContainer
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let bg = container.newBackgroundContext()
        bg.perform {
            do {
                guard (try? bg.existingObject(with: objectID)) as? Trip != nil else {
                    continuation.resume(); return                // already gone
                }
                guard let share = (try? container.fetchShares(matching: [objectID]))?[objectID] else {
                    continuation.resume(); return                // not shared — nothing to leave
                }
                guard let me = share.currentUserParticipant, me.role != .owner else {
                    continuation.resume(); return                // owner / not a participant — never leave
                }
                share.removeParticipant(me)
                container.persistUpdatedShare(share, in: store) { _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

**Why this is safe (the whole point of 2.4):** it uses `share.removeParticipant(me)` (share-level) rather than `context.delete(trip)` (record-level). The owner's record and zone are never touched, so leaving cannot delete the trip for the group. After CloudKit syncs the participant removal, `NSPersistentCloudKitContainer` auto-purges the local mirror; the trip's `@FetchRequest` row in `ContentView` disappears on its own.

**Edge cases** all resolve to a silent success no-op: trip already gone, no share found, caller is the owner or not a participant.

### Flagged unknown — which store for `persistUpdatedShare`

iosJournal passes the **private** store even on a participant leave (`PersistenceController.swift:642`), although the joined trip lives in the *shared* store. This spec mirrors that choice (proven in production with the same architecture). It is the **primary on-device verification risk**: if `persistUpdatedShare` errors with the private store, retry with `sharedPersistentStore`. (The app author may confirm the correct store up front, in which case bake it in and drop the fallback note.)

**Files:** `Services/PersistenceController.swift` (add method).

---

## 2. Close the delete footgun — `ContentView` context menu

Branch the card context menu on `persistenceController.isOwner(of: trip)` (synchronous, cheap):

- **Owner →** "Delete Trip" → existing delete alert (unchanged).
- **Participant →** "Leave Trip" → a leave confirmation alert → `Task { try await persistenceController.leaveSharedTrip(trip) }`. On success show the confirmation toast (§4); on failure show a leave-error alert.

This removes the only path by which a participant could destroy a shared trip for everyone.

**Files:** `Views/ContentView.swift`.

---

## 3. `ParticipantsView` "Leave" routing

Replace the self-leave (`viewContext.delete(participant)` for the current user) with `leaveSharedTrip(trip)`:

- The "Leave" swipe button runs `Task { try await persistenceController.leaveSharedTrip(trip) }`.
- On success: `dismiss()` the sheet, then call the injected `onLeave(trip.name)` closure (§4).
- On failure: set a `@State` error string and present an alert.
- `ParticipantsView` gains `@Environment(PersistenceController.self)` and an `var onLeave: (String) -> Void` property.

The owner's "Remove" swipe is left as-is (out of scope; flagged above).

**Files:** `Views/ParticipantsView.swift`.

---

## 4. Post-leave UX

A single `onLeave: (String) -> Void` is threaded `ContentView → TripDetailView → ParticipantsView`.

- `ContentView` defines it: it sets `@State leftTripName: String?` and resets `navigationPath = NavigationPath()` (pops `TripDetailView` to root).
- `ContentView` builds `TripDetailView` inside `navigationDestination`, so it captures `ContentView` state and passes `onLeave` down; `TripDetailView` forwards it into `ParticipantsView`.
- When leaving from the `ContentView` context menu directly (already at root), `ContentView` just sets `leftTripName` (no navigation reset needed).
- Confirmation toast: a brief auto-dismissing overlay ("You left *<name>*") driven by `leftTripName`, cleared after ~2.5s by a delayed `Task`. Self-contained; no third-party deps.

The card itself disappears when the next CloudKit sync lands (usually seconds) via auto-purge — the toast covers the gap.

**Files:** `Views/ContentView.swift`, `Views/TripDetailView.swift`, `Views/ParticipantsView.swift`.

---

## Data flow

```
Participant taps Leave (ContentView context menu OR ParticipantsView swipe)
  -> confirmation alert
  -> persistenceController.leaveSharedTrip(trip)        // bg context: removeParticipant + persistUpdatedShare
  -> on success:
       - if in detail sheet: dismiss sheet + reset navigationPath to root
       - ContentView shows "You left <name>" toast (~2.5s)
  -> NSPersistentCloudKitContainer purges local mirror on next sync
  -> trip card disappears from the list
  -> on failure: error alert
```

Owner's record is never modified; the trip persists for the owner and remaining participants.

---

## Verification (honest)

No unit/UI test targets exist, so:

1. **Compile check:**
   ```bash
   xcodebuild -project myRoadTripTracker/myRoadTripTracker.xcodeproj \
              -scheme myRoadTripTracker \
              -destination 'platform=iOS Simulator,name=iPhone 17' build
   ```
   (`iPhone 16` is not installed on this machine; use `iPhone 17`.) Expected: `** BUILD SUCCEEDED **`.
2. **On-device, two real iCloud accounts (the only meaningful test):** owner shares a trip → participant joins → participant leaves. Confirm:
   - (a) the trip leaves the participant's list after sync,
   - (b) **the trip still exists for the owner** (not deleted),
   - (c) the owner's participant list drops the leaver after sync,
   - (d) a participant's card shows "Leave Trip", an owner's shows "Delete Trip", and the owner's Delete still works.
3. **Store-choice check:** confirm `leaveSharedTrip` succeeds with the private store; if `persistUpdatedShare` errors, retry with the shared store and update the code.

CloudKit sharing cannot be exercised on the simulator (not signed into iCloud) — device testing is required.

---

## References

- `~/code/iosJournal/Glade/Persistence/PersistenceController.swift` — `leaveShare` (~L621), `revokeParticipant` (~L586).
- `docs/agy_general.md` — finding 2.4.
- `docs/superpowers/specs/2026-06-26-tier1FixesDesign.md` — Tier 1 (sibling spec).
