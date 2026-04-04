# TripSpotter

An iOS app for tracking license plate sightings on road trips. Spot plates from all 50 US states, 10 Canadian provinces, and 3 Canadian territories — collaboratively with friends and family.

## Features

- **License Plate Tracking** — Tap to mark plates as seen, with GPS location recorded for each sighting
- **Real-Time Collaborative Sharing** — Share trips via iCloud link; all participants see plate markings and observations sync live
- **Trip Observations** — Append-only notes organized by category (weirdest thing, coolest car, funniest billboard, etc.)
- **Per-Trip Display Names** — Each participant chooses how they appear on each trip
- **Sightings Map** — View all spotted plates on a map showing where each was seen
- **Trip Lifecycle** — Open and close trips; closed trips become read-only

## Tech Stack

- **SwiftUI** — UI framework
- **Core Data** with **NSPersistentCloudKitContainer** — Persistence + CloudKit sync
- **CloudKit** — Real-time collaborative sharing between iCloud users
- **CoreLocation** — One-shot GPS for plate sighting locations
- **MapKit** — Sightings map display

## Architecture

### Two-Store CloudKit Sync

The app uses `NSPersistentCloudKitContainer` with two persistent stores:

- **Private store** (`private.sqlite`) — Syncs with the user's CloudKit private database. Holds trips the user creates.
- **Shared store** (`shared.sqlite`) — Syncs with the CloudKit shared database. Holds trips shared with the user by others.

Both stores use the same Core Data model. The container handles bidirectional sync automatically. `@FetchRequest` spans both stores, so the trip list shows owned and shared trips together.

### Sharing Flow

**Owner shares a trip:**
1. `NSPersistentCloudKitContainer.share([trip], to: nil)` creates a `CKShare` + new CloudKit zone
2. The entire object graph (sightings, observations, participants) moves into the share's zone
3. Share URL presented via `UIActivityViewController`

**Participant accepts:**
1. `SceneDelegate` receives `CKShare.Metadata`
2. `container.acceptShareInvitations(from: [metadata], into: sharedStore)`
3. Trip + all children automatically sync into the shared store
4. Both users see the same trip — edits sync bidirectionally

### Data Model

Four Core Data entities:

- **Trip** (share root) — `tripID`, `name`, `createdDate`, `isClosed`
- **PlateSighting** — `locationCode`, `locationName`, `latitude`, `longitude`, `seenDate`
- **ObservationEntry** — `category`, `authorName`, `text`, `createdDate`
- **TripParticipant** — `displayName`, `cloudKitUserID`, `joinedDate`

## Migration from SwiftData to Core Data

The app was originally built with SwiftData (`cloudKitDatabase: .automatic`), which only syncs the private CloudKit database. Shared records from other users were invisible — meaning shared trips were one-way copies, not collaboratively editable.

To enable real-time collaborative sharing, the app was migrated to `NSPersistentCloudKitContainer` (Core Data) with the two-store architecture described above. This is Apple's blessed path for CloudKit sharing.

### Lessons Learned During Migration

1. **`[weak self]` in `loadPersistentStores` during init crashes with `@Observable`** — The macro's backing storage isn't fully initialized during init, making `weak self` nil in the callback. Fix: use local variables instead of capturing self, then assign after the callback completes.

2. **Store descriptions must be assigned as a full array** — Use `persistentContainer.persistentStoreDescriptions = [private, shared]`, not `.append()`. The `@NSCopying` property behavior makes append unreliable.

3. **Optional Core Data attributes require Optional Swift types** — Even if your convenience init always sets the value. CloudKit can deliver partially-synced records with nil fields. Non-optional `@NSManaged` properties crash on nil.

4. **The remote change handler must process persistent history** — `automaticallyMergesChangesFromParent` alone is not sufficient for real-time sync. You need `NSPersistentHistoryChangeRequest.fetchHistory(after: token)` + `viewContext.mergeChanges(fromContextDidSave:)` to get live UI updates when CloudKit pushes changes.

5. **`persistUpdatedShare` is async** — Must await completion (e.g., via `withCheckedThrowingContinuation`) before returning the `CKShare` to the UI, otherwise share URL/metadata may be missing.

6. **Use closure-based `NotificationCenter` observers** — Avoids `@objc` runtime dispatch issues with `@MainActor`-isolated classes.

7. **`codeGenerationType="manual/none"` is not a valid Xcode XML value** — It crashes Xcode on project open. Valid values are `"class"` or `"category"`. For Manual/None codegen, omit the attribute entirely or set it via Xcode's Data Model Inspector.

8. **Xcode 16+ auto-sync projects (`PBXFileSystemSynchronizedRootGroup`) don't need explicit file references** — All files in the synced source directory are auto-discovered. Adding explicit `PBXFileReference` entries (e.g., via the `pbxproj` Python library) creates duplicate compile targets.

9. **CloudKit requires `optional="YES"` on Date and UUID attributes** — These types don't support compile-time default values in the `.xcdatamodeld` XML.

## Project Structure

```
myRoadTripTracker/
├── myRoadTripTracker.xcodeproj/
├── myRoadTripTracker.xcdatamodeld/        # Core Data model (4 entities)
└── myRoadTripTracker/                     # Source code
    ├── CoreDataModels/                    # NSManagedObject subclasses
    │   ├── Trip+CoreDataClass.swift
    │   ├── Trip+CoreDataProperties.swift
    │   ├── PlateSighting+CoreData*.swift
    │   ├── ObservationEntry+CoreData*.swift
    │   └── TripParticipant+CoreData*.swift
    ├── PersistenceController.swift        # Two-store CloudKit container
    ├── CoreDataHelpers.swift              # Save + store membership extensions
    ├── myRoadTripTrackerApp.swift          # App entry point
    ├── AppDelegate.swift                  # Share acceptance (SceneDelegate)
    ├── ContentView.swift                  # Trip list
    ├── TripDetailView.swift               # Trip editor (plates + notes tabs)
    ├── PlateSightingsSection.swift         # Plate checklist
    ├── PlateSightingsMapView.swift         # Map of sightings
    ├── ObservationsSection.swift           # Category-organized notes
    ├── CloudSharingView.swift             # Share sheet
    ├── ParticipantsView.swift             # Participant management
    ├── Location.swift                     # 63 NA regions (states/provinces/territories)
    ├── LocationManager.swift              # One-shot GPS
    ├── CloudKitUserHelper.swift           # iCloud user identity
    ├── OnboardingView.swift               # First-launch flow
    └── JoinTripNameView.swift             # Join shared trip prompt
```

## Requirements

- iOS 18.1+
- Xcode 26+
- iCloud account (for sync and sharing)
- Apple Developer account (for CloudKit entitlements)

## Setup

1. Clone the repo
2. Open `myRoadTripTracker/myRoadTripTracker.xcodeproj`
3. Set your development team in Signing & Capabilities
4. Ensure the CloudKit container (`iCloud.com.tentenbits.myRoadTripTracker`) is configured
5. Build and run

## License

Private project — not open source.
