# Leave Trip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a participant truly leave a shared trip (severing CKShare membership without destroying the shared record), and make the destructive delete owner-only.

**Architecture:** A new `PersistenceController.leaveSharedTrip(_:)` removes only the current user's CKShare participant on a background context (watchdog-safe) and relies on `NSPersistentCloudKitContainer` to auto-purge the local mirror. The UI branches the trip-card context menu on ownership (owner → Delete, participant → Leave), routes both the card menu and the `ParticipantsView` swipe through the same leave method, and shows a dismiss-to-root + confirmation-toast flow via a single `onLeave` closure. Source spec: `docs/superpowers/specs/2026-06-26-leaveTripDesign.md`.

**Tech Stack:** Swift, SwiftUI, Core Data + `NSPersistentCloudKitContainer`, CloudKit (`CKShare`), Xcode.

## Global Constraints

- **No test targets exist.** Do not invent `xcodebuild test`. Verification = compile via `xcodebuild ... build` + code inspection + (for the human) on-device testing with two real iCloud accounts. (CLAUDE.md)
- **Do not edit `project.pbxproj`.** Files are auto-discovered. These tasks modify existing files only. (CLAUDE.md sharp edge #1)
- **Leaving must use `share.removeParticipant(currentUserParticipant)` — never `context.delete(trip)`.** The record-level delete would propagate through CloudKit and destroy the trip for the owner. This is the entire point of the fix. (Spec §1)
- **All CloudKit share work runs on a background context.** `persistUpdatedShare` can block >10s and trips the iOS watchdog (0x8BADF00D) on the main thread. (Spec §1)
- **CloudKit sharing cannot be exercised on the simulator** (not signed into iCloud) — full verification requires devices. (CLAUDE.md / spec)
- **Build command** (used in every task's verify step; this machine has `iPhone 17`, not `iPhone 16`):
  ```bash
  xcodebuild -project myRoadTripTracker/myRoadTripTracker.xcodeproj \
             -scheme myRoadTripTracker \
             -destination 'platform=iOS Simulator,name=iPhone 17' build
  ```
  Expected tail: `** BUILD SUCCEEDED **`
- **Branch:** work happens on `leaveTrip` (already created; spec already committed there).

---

### Task 1: Add `PersistenceController.leaveSharedTrip(_:)`

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/Services/PersistenceController.swift`

**Interfaces:**
- Consumes: existing `privatePersistentStore`, `persistentContainer`.
- Produces: `func leaveSharedTrip(_ trip: Trip) async throws` — used by Task 2. Throws on a CloudKit failure; resolves to a silent no-op for already-gone / not-shared / owner / not-a-participant cases.

- [ ] **Step 1: Add the method**

In `PersistenceController.swift`, inside the `// MARK: - Sharing` section, insert the following method immediately **before** the `func isOwner(of trip: Trip) -> Bool` method (i.e., before its `/// Check if the current user owns this trip` doc comment):

```swift
    /// Leave a shared trip you joined as a participant. Removes ONLY your own CKShare participant
    /// (never if you are the owner), then lets NSPersistentCloudKitContainer purge the local mirror.
    /// Runs on a background context: persistUpdatedShare can block >10s and would trip the iOS
    /// watchdog (0x8BADF00D) on the main thread.
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

Note on the store choice: this mirrors iosJournal's production `leaveShare`, which passes the **private** store even for a participant leave. If on-device testing shows `persistUpdatedShare` erroring with the private store, the fallback is to use `sharedPersistentStore` instead — but ship the private-store version first.

- [ ] **Step 2: Build and verify it compiles**

Run:
```bash
xcodebuild -project myRoadTripTracker/myRoadTripTracker.xcodeproj \
           -scheme myRoadTripTracker \
           -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`. If `CKShare.currentUserParticipant` / `removeParticipant` / `role` raise a compiler error, confirm `import CloudKit` is present at the top of the file (it is) and that the types resolve; fix and rebuild.

- [ ] **Step 3: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/Services/PersistenceController.swift
git commit -m "feat(leaveTrip): add leaveSharedTrip to remove self from a CKShare

Removes only the current user's CKShare participant on a background
context (watchdog-safe) and lets NSPersistentCloudKitContainer purge the
local mirror. Uses share.removeParticipant, never context.delete, so
leaving never propagates a delete to the owner."
```

---

### Task 2: Wire the Leave UX (context menu + ParticipantsView + post-leave navigation)

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/ContentView.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/TripDetailView.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/ParticipantsView.swift`

**Interfaces:**
- Consumes: `persistenceController.leaveSharedTrip(_:) async throws` (Task 1), existing `persistenceController.isOwner(of:)`.
- Produces: no external API. Internally threads `onLeave: (String) -> Void` from `ContentView` → `TripDetailView` → `ParticipantsView`.

These three files must change together: adding the required `onLeave` parameter to `ParticipantsView` and `TripDetailView` breaks compilation until their call sites are updated. Treat this as one buildable unit.

- [ ] **Step 1: `ParticipantsView` — accept `onLeave`/`persistenceController` and route Leave through the new method**

In `ParticipantsView.swift`, replace the property/environment block:
```swift
struct ParticipantsView: View {
    @ObservedObject var trip: Trip
    let isOwner: Bool
    let currentUserID: String
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
```
with:
```swift
struct ParticipantsView: View {
    @ObservedObject var trip: Trip
    let isOwner: Bool
    let currentUserID: String
    let onLeave: (String) -> Void
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PersistenceController.self) private var persistenceController
    @State private var leaveError: String?
```

Replace the Leave swipe button:
```swift
                        if !isOwner && participant.cloudKitUserID == currentUserID {
                            Button("Leave", role: .destructive) {
                                leaveTrip(participant)
                            }
                        }
```
with:
```swift
                        if !isOwner && participant.cloudKitUserID == currentUserID {
                            Button("Leave", role: .destructive) {
                                leaveTrip()
                            }
                        }
```

Replace the `leaveTrip(_:)` method:
```swift
    private func leaveTrip(_ participant: TripParticipant) {
        removeParticipant(participant)
        dismiss()
    }
```
with:
```swift
    private func leaveTrip() {
        let name = trip.name
        Task {
            do {
                try await persistenceController.leaveSharedTrip(trip)
                dismiss()
                onLeave(name)
            } catch {
                leaveError = "Couldn't leave the trip: \(error.localizedDescription)"
            }
        }
    }
```
(Leave `removeParticipant(_:)` in place — the owner's "Remove" swipe still uses it.)

Add an error alert. Find the `.overlay` block that ends the `List` (the `ContentUnavailableView` "No Participants" overlay) and insert the alert immediately after that overlay's closing `}`:
```swift
            .alert(
                "Couldn't Leave",
                isPresented: Binding(
                    get: { leaveError != nil },
                    set: { if !$0 { leaveError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { leaveError = nil }
            } message: {
                if let leaveError {
                    Text(leaveError)
                }
            }
```

- [ ] **Step 2: `TripDetailView` — declare `onLeave` and forward it to `ParticipantsView`**

In `TripDetailView.swift`, find:
```swift
    let isNewTrip: Bool
```
and replace with:
```swift
    let isNewTrip: Bool
    let onLeave: (String) -> Void
```

Then replace the participants sheet:
```swift
        .sheet(isPresented: $showingParticipants) {
            ParticipantsView(
                trip: trip,
                isOwner: isOwner,
                currentUserID: cloudKitUserID
            )
        }
```
with:
```swift
        .sheet(isPresented: $showingParticipants) {
            ParticipantsView(
                trip: trip,
                isOwner: isOwner,
                currentUserID: cloudKitUserID,
                onLeave: onLeave
            )
        }
```

- [ ] **Step 3: `ContentView` — owner/participant context menu, leave alert, toast, and `onLeave` wiring**

In `ContentView.swift`, replace the state block:
```swift
    @State private var tripToDelete: Trip?
    @State private var showingDeleteAlert = false
```
with:
```swift
    @State private var tripToDelete: Trip?
    @State private var showingDeleteAlert = false
    @State private var tripToLeave: Trip?
    @State private var showingLeaveAlert = false
    @State private var leaveError: String?
    @State private var leftTripName: String?
```

Replace the card context menu:
```swift
                        .contextMenu {
                            Button(role: .destructive) {
                                tripToDelete = trip
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete Trip", systemImage: "trash")
                            }
                        }
```
with:
```swift
                        .contextMenu {
                            if persistenceController.isOwner(of: trip) {
                                Button(role: .destructive) {
                                    tripToDelete = trip
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Delete Trip", systemImage: "trash")
                                }
                            } else {
                                Button(role: .destructive) {
                                    tripToLeave = trip
                                    showingLeaveAlert = true
                                } label: {
                                    Label("Leave Trip", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                            }
                        }
```

Replace the empty-state overlay's closing to add the confirmation toast. Find:
```swift
            .overlay {
                if trips.isEmpty {
                    ContentUnavailableView {
                        Label("No Trips", systemImage: "car.fill")
                    } description: {
                        Text("Start tracking your road trip games by creating your first trip.")
                    } actions: {
                        Button("Create Trip", action: addTrip)
                    }
                }
            }
```
and insert the following immediately **after** that `.overlay { ... }` block:
```swift
            .overlay(alignment: .bottom) {
                if let leftTripName {
                    Text("You left \(leftTripName)")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: leftTripName) {
                            try? await Task.sleep(for: .seconds(2.5))
                            withAnimation { self.leftTripName = nil }
                        }
                }
            }
            .animation(.spring, value: leftTripName)
```

Replace the navigation destination:
```swift
            .navigationDestination(for: NSManagedObjectID.self) { objectID in
                if let trip = viewContext.object(with: objectID) as? Trip {
                    TripDetailView(trip: trip, isNewTrip: objectID == newlyCreatedTrip?.objectID)
                }
            }
```
with:
```swift
            .navigationDestination(for: NSManagedObjectID.self) { objectID in
                if let trip = viewContext.object(with: objectID) as? Trip {
                    TripDetailView(
                        trip: trip,
                        isNewTrip: objectID == newlyCreatedTrip?.objectID,
                        onLeave: { name in
                            navigationPath = NavigationPath()
                            confirmLeft(name)
                        }
                    )
                }
            }
```

Add the leave alert and leave-error alert. Find the delete alert's end:
```swift
            } message: { _ in
                Text("Are you sure you want to delete this trip? This cannot be undone.")
            }
```
and insert immediately **after** it:
```swift
            .alert("Leave Trip", isPresented: $showingLeaveAlert, presenting: tripToLeave) { trip in
                Button("Leave", role: .destructive) {
                    let name = trip.name
                    Task {
                        do {
                            try await persistenceController.leaveSharedTrip(trip)
                            confirmLeft(name)
                        } catch {
                            leaveError = "Couldn't leave the trip: \(error.localizedDescription)"
                        }
                        tripToLeave = nil
                    }
                }
                Button("Cancel", role: .cancel) { tripToLeave = nil }
            } message: { _ in
                Text("You'll be removed from this shared trip. It stays available for everyone else.")
            }
            .alert(
                "Couldn't Leave",
                isPresented: Binding(
                    get: { leaveError != nil },
                    set: { if !$0 { leaveError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { leaveError = nil }
            } message: {
                if let leaveError {
                    Text(leaveError)
                }
            }
```

Add the `confirmLeft` helper. Find the `addTrip()` method:
```swift
    private func addTrip() {
        let newTrip = Trip(context: viewContext)
        if let store = persistenceController.privatePersistentStore {
            viewContext.assign(newTrip, to: store)
        }
        viewContext.save(contextInfo: "addTrip")
        newlyCreatedTrip = newTrip
        navigationPath.append(newTrip.objectID)
    }
```
and insert immediately **after** it (before the final closing `}` of the struct):
```swift

    private func confirmLeft(_ name: String) {
        withAnimation { leftTripName = name }
    }
```

- [ ] **Step 4: Build and verify it compiles**

Run:
```bash
xcodebuild -project myRoadTripTracker/myRoadTripTracker.xcodeproj \
           -scheme myRoadTripTracker \
           -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`. Common issues to fix if they arise: a missing `onLeave:` argument at the `TripDetailView`/`ParticipantsView` call sites; `leftTripName` shadowing inside the toast `.task` (use `self.leftTripName = nil`).

- [ ] **Step 5: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/Views/ContentView.swift \
        myRoadTripTracker/myRoadTripTracker/Views/TripDetailView.swift \
        myRoadTripTracker/myRoadTripTracker/Views/ParticipantsView.swift
git commit -m "feat(leaveTrip): leave UX — owner-only delete, participant leave + toast

Branch the trip-card context menu on ownership (owner: Delete, participant:
Leave), route the ParticipantsView swipe and the card menu through
leaveSharedTrip, and pop to root with a brief confirmation toast on success."
```

---

## Post-implementation manual verification (not a task — for the human)

On **two devices with two real iCloud accounts** (CloudKit sharing can't be tested in the simulator):
- Owner shares a trip → participant joins → participant taps **Leave** (from the card menu and, separately, from the Participants sheet). Confirm:
  - (a) the trip leaves the participant's list after sync,
  - (b) **the trip still exists for the owner** (not deleted),
  - (c) the owner's participant list drops the leaver after sync,
  - (d) a participant's card shows "Leave Trip"; an owner's shows "Delete Trip", and the owner's Delete still removes it for everyone.
- **Store-choice check:** if `leaveSharedTrip` throws on a real participant leave, switch `persistUpdatedShare(share, in: store)` from `privatePersistentStore` to `sharedPersistentStore` and retest.

## Out of scope (tracked elsewhere)

- Owner-revoke-participant (the owner's "Remove" swipe only deletes the local `TripParticipant`; same bug class, iosJournal `revokeParticipant` is the template) — separate fix.
- Finding 3.3 `CKContainer.default()` mismatch — independent; the leave path sidesteps it via `share.currentUserParticipant`.
