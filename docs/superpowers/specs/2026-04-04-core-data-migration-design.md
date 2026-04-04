# Core Data Migration for Collaborative Sharing

**Date:** 2026-04-04
**Status:** Approved
**Goal:** Replace SwiftData with NSPersistentCloudKitContainer to enable real-time collaborative trip sharing between iCloud users.

## Context

SwiftData's `cloudKitDatabase: .automatic` only syncs the private CloudKit database. Shared records from other users are invisible. This means shared trips are one-way copies — not collaboratively editable. The fix is Apple's blessed path: NSPersistentCloudKitContainer with private + shared stores.

Reference implementation: Apple's "Sharing Core Data objects between iCloud users" sample (stored at `docs/apple-sample/`).

## Architecture

### Two-Store Model

NSPersistentCloudKitContainer configured with two persistent stores:

1. **Private store** (`private.sqlite`) — `CKDatabase.Scope.private`. Holds trips the user creates.
2. **Shared store** (`shared.sqlite`) — `CKDatabase.Scope.shared`. Holds trips shared with the user by others.

Both stores use the same Core Data model. The container handles bidirectional CloudKit sync for both stores automatically.

Configuration:
- Same CloudKit container ID: `iCloud.com.tentenbits.myRoadTripTracker`
- NSPersistentHistoryTrackingKey enabled on both stores
- NSPersistentStoreRemoteChangeNotificationPostOptionKey enabled on both stores
- `viewContext.automaticallyMergesChangesFromParent = true`
- `viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy`

### Data Model (.xcdatamodeld)

Four entities, same as current SwiftData models:

**Trip** (share root)
- `tripID` (UUID) — unique identifier
- `name` (String) — trip name
- `createdDate` (Date) — creation timestamp
- `isClosed` (Boolean) — closed/active state
- Relationships: `plateSightings` (to-many, cascade), `observationEntries` (to-many, cascade), `participants` (to-many, cascade)

**PlateSighting**
- `locationCode` (String), `locationName` (String)
- `latitude` (Double), `longitude` (Double)
- `seenDate` (Date)
- Relationship: `trip` (to-one, nullify)

**ObservationEntry**
- `category` (String), `authorName` (String), `text` (String)
- `createdDate` (Date)
- Relationship: `trip` (to-one, nullify)

**TripParticipant**
- `displayName` (String), `cloudKitUserID` (String)
- `joinedDate` (Date)
- Relationship: `trip` (to-one, nullify)

All entities marked `syncable` and `usedWithCloudKit`.

## Sharing Flow

### Owner Creates Share
1. `NSPersistentCloudKitContainer.share([trip], to: nil)` creates CKShare + new CloudKit zone
2. Entire object graph (trip + sightings + observations + participants) moves into that zone
3. Share URL presented via UIActivityViewController
4. Share persisted via `persistUpdatedShare(share, in: privatePersistentStore)`

### Participant Accepts Share
1. SceneDelegate receives `CKShare.Metadata` via `windowScene(_:userDidAcceptCloudKitShareWith:)`
2. `container.acceptShareInvitations(from: [metadata], into: sharedPersistentStore)`
3. Trip + all children automatically sync into shared store
4. Both users see the same trip — edits sync bidirectionally via CloudKit

### Ownership Determination
- Trip in `privatePersistentStore` → user is owner
- Trip in `sharedPersistentStore` → user is participant
- `canUpdateRecord(forManagedObjectWith:)` for permission checks
- `canDeleteRecord(forManagedObjectWith:)` for delete permission

## View Layer Changes

Mechanical transformations, no UI changes:

| SwiftData | Core Data |
|---|---|
| `@Model class Trip` | `NSManagedObject` subclass + `.xcdatamodeld` |
| `@Query var trips: [Trip]` | `@FetchRequest(sortDescriptors:) var trips: FetchedResults<Trip>` |
| `@Environment(\.modelContext)` | `@Environment(\.managedObjectContext)` |
| `context.insert(obj)` (auto-save) | `context.insert(obj)` + `context.save()` |
| `.modelContainer(container)` | `.environment(\.managedObjectContext, viewContext)` |

`@FetchRequest` automatically spans both stores, so the trip list shows owned + shared trips with no special merge logic.

Owner vs participant UI gated by `privatePersistentStore.contains(managedObject: trip)`.

New objects assigned to private store on creation: `context.assign(trip, to: privatePersistentStore)`.

## PersistenceController Rewrite

Rewritten from scratch following Apple's sample pattern:

- Configures NSPersistentCloudKitContainer with two store descriptions
- Exposes `privatePersistentStore` and `sharedPersistentStore` references
- Provides `shareTrip(_:)`, `existingShare(trip:)` helper methods
- Handles remote change notifications via persistent history
- `save(with:)` contextual save helper

## What Gets Deleted

- All `@Model` Swift files (Trip.swift, PlateSighting.swift, ObservationEntry.swift, TripParticipant.swift)
- Current `PersistenceController.swift` (complete rewrite)
- `CloudSharingView.swift` (manual CKShare code replaced by container APIs)
- No existing data migration (clean break — TestFlight only, 2 users)

## What Stays Unchanged

- All SwiftUI view structure and UI design
- LocationManager.swift
- CloudKitUserHelper.swift
- Location.swift (63 regions)
- OnboardingView.swift, JoinTripNameView.swift
- PlateSightingsMapView.swift
- All flag image assets
- Entitlements (same CloudKit container)
- Info.plist (CKSharingSupported already true)

## Conflict Resolution

Inherited from current design:
- **Plate sightings:** Earliest timestamp wins if duplicate
- **Observations:** Append-only, no conflicts
- **Trip metadata:** Last write wins (NSMergeByPropertyObjectTrumpMergePolicy)
