# Collaborative Trip Sharing - Feature Spec

**Version:** 1.0
**Date:** 2026-03-30
**Status:** Draft

---

## Overview

Enable multiple users to participate in the same road trip, collaboratively marking license plate sightings and recording observations in real time. Built on SwiftData + CloudKit with CKShare for multi-user collaboration.

---

## 1. Sharing & Invites

### 1.1 Share Flow (Owner)

1. Owner creates a trip (or opens an existing one)
2. Owner taps a "Share" action within the trip
3. iOS share sheet appears with a universal link
4. Owner sends link via iMessage, AirDrop, or any messaging app

### 1.2 Join Flow (Recipient)

**Has the app installed:**
1. Recipient taps the link
2. App opens, trip appears in their trip list immediately
3. Recipient is prompted to set a display name for this trip (pre-filled with their default name from onboarding)

**Does not have the app installed:**
1. Recipient taps the link
2. Universal link falls through to the App Store listing
3. Recipient installs the app
4. On first launch, recipient completes onboarding (see Section 7)
5. The share link is remembered through the install process
6. Trip appears in their trip list automatically after onboarding

### 1.3 Constraints

- iOS only - the app requires an iCloud account
- Tapping the link is the acceptance mechanism; there is no separate "accept invite" step
- Any participant (not just the owner) can share the trip link to invite additional people

---

## 2. Roles & Permissions

There are two roles: **Owner** (the person who created the trip) and **Participant** (everyone else).

| Action                          | Owner | Participant |
|---------------------------------|:-----:|:-----------:|
| Rename the trip                 | Yes   | Yes         |
| Mark a plate as seen            | Yes   | Yes         |
| Unmark/remove a plate sighting  | Yes   | Yes         |
| Write observations              | Yes   | Yes         |
| Add participants (share link)   | Yes   | Yes         |
| Leave the trip                  | N/A   | Yes         |
| Close/complete the trip         | Yes   | No          |
| Delete the trip entirely        | Yes   | No          |
| Remove a participant            | Yes   | No          |

### 2.1 Ownership Transfer

Not supported in v1. If the owner leaves or deletes the trip, it is deleted for all participants. This may be revisited in a future version.

---

## 3. Plate Sightings

### 3.1 Collaborative Collection

The group collectively works toward spotting all 63 North American license plates (50 US states, 10 Canadian provinces, 3 Canadian territories). Progress is shared - there is one checklist per trip, not per person.

### 3.2 Marking a Plate

1. Any participant taps a location in the plate list
2. A one-shot GPS location fix is requested at that moment
3. A `PlateSighting` record is created with:
   - Location code and name
   - Latitude/longitude from the GPS fix
   - Timestamp (`seenDate`)
4. No user attribution is stored on the sighting

### 3.3 Conflict Resolution

If two participants mark the same plate while offline, the sighting with the **earliest timestamp** wins. The duplicate is discarded on sync.

### 3.4 Unmarking a Plate

Any participant can swipe to remove a plate sighting. This deletes the sighting record entirely.

---

## 4. Observations

### 4.1 Append-Only Entries

Observations are organized by category. Each category contains a chronological list of entries contributed by any participant. Entries are **never deleted or edited** once posted - they are permanent trip history.

### 4.2 Entry Format

Each observation entry contains:
- **Author display name** (per-trip name, see Section 6)
- **Text content**
- **Timestamp**

Displayed as a simple attributed list:
```
Sam: saw a guy juggling on the highway
Alex: definitely the three-legged dog at the rest stop
```

### 4.3 Categories

Six predefined categories ship with every trip (carried over from existing implementation). Users can also add custom categories. All participants can add custom categories to a shared trip.

### 4.4 Offline Behavior

Entries created offline are appended to the list in chronological order when connectivity is restored. No conflict resolution needed - append-only means all entries are kept.

---

## 5. Trip Lifecycle

### 5.1 States

A trip has two states:

| State      | Description                                      |
|------------|--------------------------------------------------|
| **Active** | Default. All participants can read and write.     |
| **Closed** | Read-only for all participants. Set by owner only.|

### 5.2 Closing a Trip

- Only the owner can close a trip
- Closed trips remain visible in all participants' trip lists
- No edits are allowed: no new plates, no new observations, no renaming
- The map view remains accessible
- Closing is reversible by the owner (can reopen)

### 5.3 Deleting a Trip

- Only the owner can delete a trip
- Deletion removes the trip and all associated data for all participants
- This action should have a confirmation prompt

---

## 6. Identity & Display Names

### 6.1 Onboarding Name

On first app launch, the user goes through a brief onboarding flow and sets a **default friendly name**. This name is used as the default when creating or joining trips.

### 6.2 Per-Trip Display Name

When joining a shared trip, the user is prompted to set a display name for that trip, pre-filled with their onboarding default. Users can change their per-trip display name at any time.

This allows a user to be "Sam" in a family trip and something different in another group.

### 6.3 No Global Profile

There is no user profile, avatar, or account system beyond the iCloud account used for CloudKit sync. The only user-facing identity is the display name.

---

## 7. Onboarding Flow

First-time app launch:

1. **Welcome screen** - brief app introduction
2. **Set friendly name** - text field for default display name
3. **Landing:**
   - If the user arrived via a share link: drop them into the shared trip
   - Otherwise: drop them on the main trip list with the "+" button highlighted or pulsing to encourage creating their first trip

Onboarding is completed once and not shown again.

---

## 8. Trip List

### 8.1 Layout

One flat list of all trips, sorted by creation date (newest first). No separation between owned trips and shared trips - a trip is a trip.

### 8.2 Visual Indicators

Each trip row shows:
- Trip name
- Creation date
- Plate collection progress (X/63, Y%)
- A subtle indicator distinguishing owned vs. joined trips (e.g., a small "shared" icon or participant count)
- Closed/completed state if applicable

---

## 9. Participant Lifecycle

### 9.1 Leaving a Trip

Any participant can leave a trip voluntarily. The trip disappears from their list. Their observation entries **remain** in the trip for other participants.

### 9.2 Removal by Owner

The owner can remove a participant. The trip disappears from the removed participant's list. Their observation entries **remain** in the trip.

### 9.3 Future Consideration: Data Purge

For future GDPR/privacy compliance, we may need to add a "purge my data" flow that removes a departed participant's observation entries. The data model should be structured so this is feasible without significant rework. Flag for v2.

---

## 10. Privacy Principles

These are non-negotiable design constraints for the entire application.

### 10.1 Location Data

- **One-shot GPS only.** Location is captured at the exact moment a user taps to mark a plate. No continuous tracking.
- **No background location.** The app never requests "Always" location permission. Only "When In Use" is requested, and only when actively marking a plate.
- **No route tracking.** The app does not record paths, breadcrumbs, or movement history.
- **No real-time location sharing.** Participants cannot see each other's live locations.
- **No user attribution on location data.** A plate sighting records where it was seen, not who saw it.

### 10.2 Map View

- The map displays **pins only** - one per plate sighting showing where it was spotted.
- **No lines, routes, or connections** between pins.
- **No animation of movement** or trip replay.

### 10.3 Location Permission Timing

Location permission is **not** requested on app launch or trip creation. It is requested only when the user first attempts to mark a plate as seen. If permission is denied, plates can still be marked but with coordinates recorded as 0,0 (no location).

### 10.4 App Store Privacy

A privacy policy page will be created for App Store submission that clearly communicates:
- What location data is collected and when
- That location is never tracked continuously
- That no user identity is attached to location data
- How CloudKit data is stored and shared
- Data retention and deletion policies

---

## 11. Offline Support

The app must function fully without network connectivity. This is critical for a road trip app.

### 11.1 Offline Capabilities

All features work offline:
- Creating trips
- Marking/unmarking plates (GPS permitting)
- Writing observations
- Viewing the map with previously synced data
- Browsing all trip data

### 11.2 Sync Behavior

- Changes are queued locally and synced when connectivity returns
- **Plate conflicts:** earliest timestamp wins; duplicate discarded
- **Observations:** all entries appended in chronological order; no conflicts possible
- **Trip metadata** (name, status): last write wins via CloudKit default behavior

### 11.3 Sync Indicators

The UI should provide subtle feedback when:
- Data is syncing
- Data is pending sync (queued offline changes)
- Sync has completed

This should be unobtrusive - not a blocker or modal, just an informational indicator.

---

## 12. Technical Architecture

### 12.1 Data Layer Migration

**Current:** SwiftData with local-only ModelContainer

**Target:** SwiftData with CloudKit sync, using two logical databases:
- **Private database** - user's own trips and data
- **Shared database** - trips shared via CKShare

### 12.2 Model Changes

**Trip**
- Add `isClosed: Bool` flag for trip lifecycle state
- Add `ownerName: String` for display purposes
- CloudKit zone association for sharing

**PlateSighting**
- No changes needed; already CloudKit-compatible (simple types, optional relationship)

**TripObservation (renamed/restructured)**
- Becomes a list of discrete entries rather than a single response string
- Each entry: `authorName: String`, `text: String`, `createdDate: Date`, `category: String`
- Relationship to Trip maintained

**New: TripParticipant**
- `displayName: String` - per-trip display name
- `cloudKitUserID: String` - for identifying the participant
- `joinedDate: Date`
- Relationship to Trip

**New: UserProfile (local only, not synced)**
- `defaultDisplayName: String` - set during onboarding
- `hasCompletedOnboarding: Bool`

### 12.3 CloudKit Configuration

- Enable CloudKit capability in Xcode project
- Configure CKContainer
- Set up CloudKit schema (auto-generated from SwiftData models)
- Implement CKShare creation and acceptance
- Handle universal links for share URLs

### 12.4 Universal Links

- Register an associated domain (applinks:)
- Configure Apple App Site Association (AASA) file on a web domain
- Handle incoming URLs in the app delegate / scene delegate
- Support deferred deep linking for users who install after tapping the link

---

## 13. Future Considerations

These items are explicitly out of scope for v1 but should not be designed against:

- **Trip PDF export** - generate a shareable keepsake document with trip highlights, plate map, and observations
- **GDPR data purge** - allow departed participants to request removal of their contributions
- **Ownership transfer** - allow the owner to transfer ownership to another participant
- **Trip photos** - attach photos to observations or plate sightings
- **Push notifications** - notify participants when plates are marked or observations are added
- **Android support** - not planned; iOS only
- **Abuse prevention / reporting** - needed before wide App Store release if the app gains traction

---

## 14. Implementation Status (as of 2026-04-02)

### Completed
- **Phase 1: CloudKit Foundation** — CloudKit enabled, ModelContainer with `.automatic` sync, observation model restructured, models CloudKit-compatible
- **Phase 3: Identity & Onboarding** — onboarding flow, per-trip display names, participant management UI
- **Phase 4: Trip Lifecycle** — closed/completed state, owner-only close/reopen, sharing indicators in trip list
- **Phase 5: TestFlight** — app on TestFlight, tested with two users

### Partially Completed — Sharing (Phase 2)
- CKShare creation via direct CloudKit API — **working**
- Share URL generation and sending via UIActivityViewController — **working**
- Share acceptance via SceneDelegate (`CKSharingSupported` in Info.plist) — **working**
- One-way trip import after share acceptance — **working**
- **NOT working: real-time collaborative sync** — SwiftData with `cloudKitDatabase: .automatic` only syncs the private CloudKit database. Shared records from other users live in the shared database, which SwiftData does not read from. The imported trip is a local copy, not a live-synced object.

### Known Limitation: Collaborative Sync
Full collaborative sync (both users seeing each other's edits in real time) requires `NSPersistentCloudKitContainer` with two stores (private + shared). This is incompatible with SwiftData's internal CloudKit mirroring — they conflict when pointed at the same store. The proper solution is to migrate from SwiftData to Core Data (using `NSPersistentCloudKitContainer` directly with `@FetchRequest`). This is a significant refactor tracked for a future iteration.

### Not Started
- Universal Links (associated domains + AASA file on web server)
- Sync status indicators
- Privacy policy page
- Location permission deferral to first plate tap

### Architecture Notes (Lessons Learned)
- **SwiftData + CloudKit sharing is not supported.** SwiftData has no sharing APIs. `cloudKitDatabase: .automatic` only syncs the private database.
- **`NSPersistentCloudKitContainer` is required for sharing** but cannot coexist with SwiftData's CloudKit mirroring on the same store (duplicate mirroring delegate error).
- **Direct CloudKit API** (`CKShare(rootRecord:)`) works for creating shares, but the share URL only routes correctly when `CKSharingSupported = true` is in Info.plist.
- **`CKSharingSupported`** in Info.plist is mandatory for share URL acceptance.
- **SceneDelegate** (not just AppDelegate) is needed for share acceptance — both `windowScene(_:userDidAcceptCloudKitShareWith:)` and `scene(_:willConnectTo:options:)`.
- **CloudKit record naming:** SwiftData syncs with `CD_` prefix on record types and attributes in CloudKit (e.g., `CD_Trip`, `CD_name`, `CD_tripID`). The Core Data entity names themselves (via `NSManagedObjectModel.makeManagedObjectModel`) do NOT have the prefix.
- **CloudKit schema must be deployed to production** for TestFlight builds to sync.
- Prepare for App Store submission
