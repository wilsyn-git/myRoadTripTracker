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

Real-time sync requires the remote-change handler to actually process persistent history; auto-merge alone is insufficient for live UI updates from CloudKit. Each pass (`PersistenceController.processRemoteChanges`):
- fetches history on a background `historyContext`, with one in-memory token per store starting at launch, skipping transactions authored `"app"` (the view context's own saves);
- coalesces bursts of notifications into one pass at a time;
- merges once with `NSManagedObjectContext.mergeChanges(fromRemoteContextSave:into:)`.

The pattern follows Apple's sample in `docs/apple-sample/Persistence/PersistenceController+History.swift`. See also the `cloudkit_coredata_lessons` memory.

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
3. `ShareLink` + `TripShareItem` (`CKShareTransferRepresentation`): the system sheet opens at once and runs steps 1–2 only after a destination is picked (#44)
4. `CKSharingSupported = true` in Info.plist (mandatory for URL acceptance)

**Participant accepts:**
1. `SceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)` (running) or `scene(_:willConnectTo:options:)` (cold launch)
2. `container.acceptShareInvitations(from: [metadata], into: sharedPersistentStore)`
3. Trip + children sync into shared store; bidirectional edits via CloudKit

**Owner check:** `privatePersistentStore.contains(managedObject: trip)` → owner; else participant. Helpers in `CoreDataHelpers.swift`.

## Source layout (`myRoadTripTracker/myRoadTripTracker/`)

- **App lifecycle:** `myRoadTripTrackerApp.swift`, `AppDelegate.swift` (SceneDelegate inside; share acceptance lives here)
- **Persistence:** `PersistenceController.swift`, `CoreDataHelpers.swift`, `CoreDataModels/*`
- **Trip list:** `ContentView.swift` (inset-grouped `List`: a `TripHeroCard` for the most recently active open trip, `TripRow`s for other open trips and for past trips by year; grouping in `Services/TripListSections.swift`; close/reopen/delete in `Services/TripLifecycle.swift`)
- **Trip detail:** `TripDetailView.swift`
- **Plates:** `PlateSightingsSection.swift` (grouped checklist + toolbar map button + plate filter dropdown), `PlateSightingsMapView.swift` (flag annotations, interpolation)
- **Observations:** `ObservationsSection.swift`, `ObservationRow.swift` (append-only with author attribution)
- **Sharing UI:** `ShareLink` in `TripDetailView.swift` with `Services/TripShareItem.swift`; `ParticipantsView.swift` (owner Remove revokes CloudKit access, #30); `JoinTripNameView.swift`
- **Identity / location:** `OnboardingView.swift`, `CloudKitUserHelper.swift`, `LocationManager.swift` (one-shot only)
- **Static data:** `Location.swift` (50 US states + 10 CA provinces + 3 territories = 63 regions)

Project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+ auto file discovery). New `.swift` files in the source dir are auto-included — do **not** add explicit `PBXFileReference` entries (will create duplicate compile targets).

## Privacy invariants (non-negotiable)

- One-shot GPS only, requested at first plate tap. No background, no Always permission, no route tracking.
- No user attribution on `PlateSighting` (only on `ObservationEntry`).
- Map: pins only, no lines/routes/animation.
- If location denied: plates can still be marked with coords `0,0`.

## Trip list (redesigned 2026-10-12, #65)

- Inset-grouped `List`. **Current**: the open trip with the latest activity as a hero card (same rule as Siri's current trip, `Trip.byRecentActivity`), then other open trips as rows. **Past Trips**: closed trips by year of last activity. Search appears with more than 5 past trips.
- Actions everywhere: leading swipe Close/Reopen (owner), trailing swipe Delete (owner) / Leave (participant), the same in the long-press menu; Delete Trip is also in the trip screen's overflow menu.
- Panels with white text use `Theme.panel(closed:)` (darkens downward; ≥ 4.5:1). Progress is `RegionProgressBars`, single hue; the red/yellow/green `DualProgressRingView` is gone.

## Known limitations / not started

- Universal Links (associated domains + AASA on a web server) — share URL is sent raw, recipient needs the app installed. Tracked in #6.
- Sync status indicators (subtle UI feedback for queued/syncing/synced). Tracked in #7.
- Privacy policy page (needed for App Store submission). Tracked in #8.
- v2: Trip PDF export, GDPR data purge for departed participants, ownership transfer, photos, push notifications.
