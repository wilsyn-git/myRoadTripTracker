# Architecture (cache)

> Snapshot of system design. Updated by `/catchup`. If code has drifted, regenerate.
> Last updated: 2026-04-25

## Project

**TripSpotter** (`com.tentenbits.myRoadTripTracker`) — iOS app for tracking license plate sightings on road trips, collaboratively. SwiftUI front, Core Data + NSPersistentCloudKitContainer back, CloudKit sharing for multi-user trips.

- iOS 18.1+ / Xcode 26+
- CloudKit container: `iCloud.com.tentenbits.myRoadTripTracker`
- TestFlight active (Sam + Marie testing)

## Tech stack

- SwiftUI (views) + `@FetchRequest` / `@ObservedObject`
- Core Data via `NSPersistentCloudKitContainer` (replaced SwiftData; migration complete)
- CloudKit (private + shared databases) for sync; `CKShare` for trip sharing
- CoreLocation (one-shot GPS only — no continuous tracking, no Always permission)
- MapKit (sightings map)

## Two-store CloudKit sync

`PersistenceController` (`@MainActor @Observable`, singleton `.shared`) configures **two persistent stores** on the same Core Data model:

| Store              | File              | Scope                       | Holds                          |
|--------------------|-------------------|-----------------------------|--------------------------------|
| `privatePersistentStore` | `private.sqlite`  | `CKDatabase.Scope.private` | Trips the user owns            |
| `sharedPersistentStore`  | `shared.sqlite`   | `CKDatabase.Scope.shared`  | Trips shared with the user     |

Both have `NSPersistentHistoryTrackingKey` and `NSPersistentStoreRemoteChangeNotificationPostOptionKey`. The view context auto-merges (`automaticallyMergesChangesFromParent = true`, `NSMergeByPropertyObjectTrumpMergePolicy`).

`@FetchRequest` spans both stores → trip list shows owned + shared together.

Real-time sync requires the remote-change handler to actually process persistent history (`NSPersistentHistoryChangeRequest.fetchHistory(after: token)` + `viewContext.mergeChanges(fromContextDidSave:)`); auto-merge alone is insufficient for live UI updates from CloudKit. See `cloudkit_coredata_lessons` memory.

## Data model (`myRoadTripTracker.xcdatamodeld`)

Four entities, all `syncable`, `usedWithCloudKit="YES"`. Date/UUID attrs marked `optional="YES"` (CloudKit requirement — no compile-time defaults).

- **Trip** (share root) — `tripID: UUID`, `name: String`, `createdDate: Date?`, `isClosed: Bool`. Cascading to-many: `plateSightings`, `observationEntries`, `participants`.
- **PlateSighting** — `locationCode`, `locationName`, `latitude: Double`, `longitude: Double`, `seenDate: Date?`. Nullify to `trip`.
- **ObservationEntry** — `category`, `authorName`, `text`, `createdDate: Date?`. Append-only. Nullify to `trip`.
- **TripParticipant** — `displayName`, `cloudKitUserID`, `joinedDate: Date?`. Nullify to `trip`.

NSManagedObject subclasses live in `CoreDataModels/<Entity>+CoreDataClass.swift` and `<Entity>+CoreDataProperties.swift`. CloudKit attrs that may sync partial → corresponding Swift types are Optional.

## Sharing flow

**Owner shares:**
1. `container.share([trip], to: nil)` → creates `CKShare` + new CloudKit zone, moves object graph in
2. `persistUpdatedShare(share, in: privatePersistentStore)` (must be awaited via `withCheckedThrowingContinuation` before returning the share to the UI)
3. Share URL → `UIActivityViewController`
4. `CKSharingSupported = true` in Info.plist (mandatory for URL acceptance)

**Participant accepts:**
1. `SceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)` (running) or `scene(_:willConnectTo:options:)` (cold launch)
2. `container.acceptShareInvitations(from: [metadata], into: sharedPersistentStore)`
3. Trip + children sync into shared store; bidirectional edits via CloudKit

**Owner check:** `privatePersistentStore.contains(managedObject: trip)` → owner; else participant. Helpers in `CoreDataHelpers.swift`.

## Source layout (`myRoadTripTracker/myRoadTripTracker/`)

- **App lifecycle:** `myRoadTripTrackerApp.swift`, `AppDelegate.swift` (SceneDelegate inside; share acceptance lives here)
- **Persistence:** `PersistenceController.swift`, `CoreDataHelpers.swift`, `CoreDataModels/*`
- **Trip list / cards:** `ContentView.swift` (currently being reworked into a `LazyVGrid` of cards — see "In-flight" below), `TripRowView.swift` (contains `TripCardView` + `ProgressRingView` post-rework)
- **Trip detail:** `TripDetailView.swift`
- **Plates:** `PlateSightingsSection.swift` (grouped checklist + toolbar map button + plate filter dropdown), `PlateSightingsMapView.swift` (flag annotations, interpolation)
- **Observations:** `ObservationsSection.swift`, `ObservationRow.swift` (append-only with author attribution)
- **Sharing UI:** `CloudSharingView.swift`, `ParticipantsView.swift`, `JoinTripNameView.swift`
- **Identity / location:** `OnboardingView.swift`, `CloudKitUserHelper.swift`, `LocationManager.swift` (one-shot only)
- **Static data:** `Location.swift` (50 US states + 10 CA provinces + 3 territories = 63 regions)

Project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+ auto file discovery). New `.swift` files in the source dir are auto-included — do **not** add explicit `PBXFileReference` entries (will create duplicate compile targets).

## Privacy invariants (non-negotiable)

- One-shot GPS only, requested at first plate tap. No background, no Always permission, no route tracking.
- No user attribution on `PlateSighting` (only on `ObservationEntry`).
- Map: pins only, no lines/routes/animation.
- If location denied: plates can still be marked with coords `0,0`.

## Trip list grid (landed in 17a1f31, 2026-04-25)

Trip list redesign in `ContentView.swift` and `TripCardView.swift`:

- Trip list: `List` → `LazyVGrid` of `TripCardView` (renamed from `TripRowView`).
- Cards have a progress ring (`DualProgressRingView`), recent-flag strip, and color-coded background (closed = grey, active = green).
- Swipe-to-delete replaced with long-press context menu + confirmation alert.
- Sort: closed trips pushed to the bottom (sort by `isClosed` asc, then `createdDate` desc).

## Known limitations / not started

- Universal Links (associated domains + AASA on a web server) — share URL is sent raw, recipient needs the app installed. Tracked in #6.
- Sync status indicators (subtle UI feedback for queued/syncing/synced). Tracked in #7.
- Privacy policy page (needed for App Store submission). Tracked in #8.
- v2: Trip PDF export, GDPR data purge for departed participants, ownership transfer, photos, push notifications.
