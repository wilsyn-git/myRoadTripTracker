# Core Data Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SwiftData with NSPersistentCloudKitContainer (Core Data) to enable real-time collaborative trip sharing between iCloud users.

**Architecture:** Two-store NSPersistentCloudKitContainer (private + shared SQLite files) with the same four entities (Trip, PlateSighting, ObservationEntry, TripParticipant). Views migrate from `@Query`/`@Model` to `@FetchRequest`/`NSManagedObject`. Sharing uses container's built-in `share(_:to:)` and `acceptShareInvitations(from:into:)` APIs.

**Tech Stack:** SwiftUI, Core Data, CloudKit (NSPersistentCloudKitContainer), CoreLocation, MapKit

**Reference:** Apple's "Sharing Core Data objects between iCloud users" sample at `docs/apple-sample/`

---

## File Structure

### Files to Create
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker.xcdatamodeld/myRoadTripTracker.xcdatamodel/contents` — Core Data model
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/Trip+CoreDataClass.swift` — Trip NSManagedObject subclass
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/Trip+CoreDataProperties.swift` — Trip properties extension
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/PlateSighting+CoreDataClass.swift` — PlateSighting NSManagedObject subclass
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/PlateSighting+CoreDataProperties.swift` — PlateSighting properties extension
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/ObservationEntry+CoreDataClass.swift` — ObservationEntry NSManagedObject subclass
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/ObservationEntry+CoreDataProperties.swift` — ObservationEntry properties extension
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/TripParticipant+CoreDataClass.swift` — TripParticipant NSManagedObject subclass
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/TripParticipant+CoreDataProperties.swift` — TripParticipant properties extension
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataHelpers.swift` — NSManagedObjectContext save helper, NSPersistentStore.contains helper

### Files to Rewrite
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/PersistenceController.swift` — Complete rewrite for NSPersistentCloudKitContainer
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CloudSharingView.swift` — Replace manual CKShare code with container APIs
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/AppDelegate.swift` — Update share acceptance to use container API
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/myRoadTripTrackerApp.swift` — Replace SwiftData container with Core Data

### Files to Modify (SwiftData → Core Data bindings)
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/ContentView.swift` — `@Query` → `@FetchRequest`, `modelContext` → `managedObjectContext`
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/TripDetailView.swift` — `@Bindable` → `@ObservedObject`, context changes
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/PlateSightingsSection.swift` — context changes, relationship handling
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/PlateSightingsMapView.swift` — type change from SwiftData model to NSManagedObject
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/ObservationsSection.swift` — context changes
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/ObservationRow.swift` — remove SwiftData import
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/ParticipantsView.swift` — context changes
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/TripRowView.swift` — type change
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/JoinTripNameView.swift` — remove SwiftData import, type change

### Files to Delete
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/Trip.swift` — replaced by CoreDataModels/Trip+*
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/PlateSighting.swift` — replaced by CoreDataModels/PlateSighting+*
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/ObservationEntry.swift` — replaced by CoreDataModels/ObservationEntry+*
- `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/TripParticipant.swift` — replaced by CoreDataModels/TripParticipant+*

### Files Unchanged
- `Location.swift`, `LocationManager.swift`, `CloudKitUserHelper.swift`, `OnboardingView.swift`, `Info.plist`, `myRoadTripTracker.entitlements`, all assets

---

### Task 1: Create Core Data Model (.xcdatamodeld)

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker.xcdatamodeld/myRoadTripTracker.xcdatamodel/contents`

The `.xcdatamodeld` is an XML file that Xcode reads. We create it directly.

- [ ] **Step 1: Create the .xcdatamodeld directory structure**

```bash
mkdir -p "myRoadTripTracker/myRoadTripTracker/myRoadTripTracker.xcdatamodeld/myRoadTripTracker.xcdatamodel"
```

- [ ] **Step 2: Write the Core Data model XML**

Create `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker.xcdatamodeld/myRoadTripTracker.xcdatamodel/contents`:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="23231" systemVersion="24D81" minimumToolsVersion="Automatic" sourceLanguage="Swift" usedWithCloudKit="YES" usedWithSwiftData="NO">
    <entity name="Trip" representedClassName="Trip" syncable="YES">
        <attribute name="tripID" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="name" attributeType="String" defaultValueString="New Trip"/>
        <attribute name="createdDate" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="isClosed" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
        <relationship name="plateSightings" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="PlateSighting" inverseName="trip" inverseEntity="PlateSighting"/>
        <relationship name="observationEntries" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="ObservationEntry" inverseName="trip" inverseEntity="ObservationEntry"/>
        <relationship name="participants" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="TripParticipant" inverseName="trip" inverseEntity="TripParticipant"/>
    </entity>
    <entity name="PlateSighting" representedClassName="PlateSighting" syncable="YES">
        <attribute name="locationCode" attributeType="String" defaultValueString=""/>
        <attribute name="locationName" attributeType="String" defaultValueString=""/>
        <attribute name="latitude" attributeType="Double" defaultValueString="0.0" usesScalarValueType="YES"/>
        <attribute name="longitude" attributeType="Double" defaultValueString="0.0" usesScalarValueType="YES"/>
        <attribute name="seenDate" attributeType="Date" usesScalarValueType="NO"/>
        <relationship name="trip" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Trip" inverseName="plateSightings" inverseEntity="Trip"/>
    </entity>
    <entity name="ObservationEntry" representedClassName="ObservationEntry" syncable="YES">
        <attribute name="category" attributeType="String" defaultValueString=""/>
        <attribute name="authorName" attributeType="String" defaultValueString=""/>
        <attribute name="text" attributeType="String" defaultValueString=""/>
        <attribute name="createdDate" attributeType="Date" usesScalarValueType="NO"/>
        <relationship name="trip" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Trip" inverseName="observationEntries" inverseEntity="Trip"/>
    </entity>
    <entity name="TripParticipant" representedClassName="TripParticipant" syncable="YES">
        <attribute name="displayName" attributeType="String" defaultValueString=""/>
        <attribute name="cloudKitUserID" attributeType="String" defaultValueString=""/>
        <attribute name="joinedDate" attributeType="Date" usesScalarValueType="NO"/>
        <relationship name="trip" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Trip" inverseName="participants" inverseEntity="Trip"/>
    </entity>
</model>
```

Note: No `codeGenerationType` attribute is set — we write all `+CoreDataClass` and `+CoreDataProperties` files manually. In Task 12, we'll also set Codegen to "Manual/None" in Xcode's Data Model Inspector for each entity.

- [ ] **Step 3: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker.xcdatamodeld/
git commit -m "feat: add Core Data model for Trip, PlateSighting, ObservationEntry, TripParticipant"
```

---

### Task 2: Create NSManagedObject Subclasses

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/Trip+CoreDataClass.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/Trip+CoreDataProperties.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/PlateSighting+CoreDataClass.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/PlateSighting+CoreDataProperties.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/ObservationEntry+CoreDataClass.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/ObservationEntry+CoreDataProperties.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/TripParticipant+CoreDataClass.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/TripParticipant+CoreDataProperties.swift`
- Delete: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/Trip.swift`
- Delete: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/PlateSighting.swift`
- Delete: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/ObservationEntry.swift`
- Delete: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/TripParticipant.swift`

- [ ] **Step 1: Create the CoreDataModels directory**

```bash
mkdir -p myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels
```

- [ ] **Step 2: Write Trip+CoreDataClass.swift**

```swift
import CoreData

@objc(Trip)
public class Trip: NSManagedObject {
    /// Convenience initializer matching the old SwiftData API.
    convenience init(context: NSManagedObjectContext, name: String = "New Trip", createdDate: Date = .now, tripID: UUID = UUID()) {
        let entity = NSEntityDescription.entity(forEntityName: "Trip", in: context)!
        self.init(entity: entity, insertInto: context)
        self.tripID = tripID
        self.name = name
        self.createdDate = createdDate
        self.isClosed = false
    }
}
```

- [ ] **Step 3: Write Trip+CoreDataProperties.swift**

```swift
import Foundation
import CoreData

extension Trip {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Trip> {
        return NSFetchRequest<Trip>(entityName: "Trip")
    }

    @NSManaged public var tripID: UUID
    @NSManaged public var name: String
    @NSManaged public var createdDate: Date
    @NSManaged public var isClosed: Bool
    @NSManaged public var plateSightings: NSSet?
    @NSManaged public var observationEntries: NSSet?
    @NSManaged public var participants: NSSet?
}

// MARK: - Convenience Accessors

extension Trip: Identifiable {
    /// Typed array of plate sightings, sorted by seenDate.
    var plateSightingsArray: [PlateSighting] {
        let set = plateSightings as? Set<PlateSighting> ?? []
        return set.sorted { $0.seenDate < $1.seenDate }
    }

    /// Typed array of observation entries, sorted by createdDate.
    var observationEntriesArray: [ObservationEntry] {
        let set = observationEntries as? Set<ObservationEntry> ?? []
        return set.sorted { $0.createdDate < $1.createdDate }
    }

    /// Typed array of participants, sorted by joinedDate.
    var participantsArray: [TripParticipant] {
        let set = participants as? Set<TripParticipant> ?? []
        return set.sorted { $0.joinedDate < $1.joinedDate }
    }
}

// MARK: - Generated accessors for plateSightings
extension Trip {
    @objc(addPlateSightingsObject:)
    @NSManaged public func addToPlateSightings(_ value: PlateSighting)

    @objc(removePlateSightingsObject:)
    @NSManaged public func removeFromPlateSightings(_ value: PlateSighting)

    @objc(addPlateSightings:)
    @NSManaged public func addToPlateSightings(_ values: NSSet)

    @objc(removePlateSightings:)
    @NSManaged public func removeFromPlateSightings(_ values: NSSet)
}

// MARK: - Generated accessors for observationEntries
extension Trip {
    @objc(addObservationEntriesObject:)
    @NSManaged public func addToObservationEntries(_ value: ObservationEntry)

    @objc(removeObservationEntriesObject:)
    @NSManaged public func removeFromObservationEntries(_ value: ObservationEntry)

    @objc(addObservationEntries:)
    @NSManaged public func addToObservationEntries(_ values: NSSet)

    @objc(removeObservationEntries:)
    @NSManaged public func removeFromObservationEntries(_ values: NSSet)
}

// MARK: - Generated accessors for participants
extension Trip {
    @objc(addParticipantsObject:)
    @NSManaged public func addToParticipants(_ value: TripParticipant)

    @objc(removeParticipantsObject:)
    @NSManaged public func removeFromParticipants(_ value: TripParticipant)

    @objc(addParticipants:)
    @NSManaged public func addToParticipants(_ values: NSSet)

    @objc(removeParticipants:)
    @NSManaged public func removeFromParticipants(_ values: NSSet)
}
```

- [ ] **Step 4: Write PlateSighting+CoreDataClass.swift**

```swift
import CoreData

@objc(PlateSighting)
public class PlateSighting: NSManagedObject {
    convenience init(context: NSManagedObjectContext, locationCode: String, locationName: String, latitude: Double, longitude: Double, seenDate: Date = .now) {
        let entity = NSEntityDescription.entity(forEntityName: "PlateSighting", in: context)!
        self.init(entity: entity, insertInto: context)
        self.locationCode = locationCode
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.seenDate = seenDate
    }
}
```

- [ ] **Step 5: Write PlateSighting+CoreDataProperties.swift**

```swift
import Foundation
import CoreData
import CoreLocation

extension PlateSighting {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PlateSighting> {
        return NSFetchRequest<PlateSighting>(entityName: "PlateSighting")
    }

    @NSManaged public var locationCode: String
    @NSManaged public var locationName: String
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var seenDate: Date
    @NSManaged public var trip: Trip?
}

extension PlateSighting: Identifiable {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
```

- [ ] **Step 6: Write ObservationEntry+CoreDataClass.swift**

```swift
import CoreData

@objc(ObservationEntry)
public class ObservationEntry: NSManagedObject {
    convenience init(context: NSManagedObjectContext, category: String, authorName: String, text: String, createdDate: Date = .now) {
        let entity = NSEntityDescription.entity(forEntityName: "ObservationEntry", in: context)!
        self.init(entity: entity, insertInto: context)
        self.category = category
        self.authorName = authorName
        self.text = text
        self.createdDate = createdDate
    }
}
```

- [ ] **Step 7: Write ObservationEntry+CoreDataProperties.swift**

```swift
import Foundation
import CoreData

extension ObservationEntry {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ObservationEntry> {
        return NSFetchRequest<ObservationEntry>(entityName: "ObservationEntry")
    }

    @NSManaged public var category: String
    @NSManaged public var authorName: String
    @NSManaged public var text: String
    @NSManaged public var createdDate: Date
    @NSManaged public var trip: Trip?
}

extension ObservationEntry: Identifiable {}
```

- [ ] **Step 8: Write TripParticipant+CoreDataClass.swift**

```swift
import CoreData

@objc(TripParticipant)
public class TripParticipant: NSManagedObject {
    convenience init(context: NSManagedObjectContext, displayName: String, cloudKitUserID: String, joinedDate: Date = .now) {
        let entity = NSEntityDescription.entity(forEntityName: "TripParticipant", in: context)!
        self.init(entity: entity, insertInto: context)
        self.displayName = displayName
        self.cloudKitUserID = cloudKitUserID
        self.joinedDate = joinedDate
    }
}
```

- [ ] **Step 9: Write TripParticipant+CoreDataProperties.swift**

```swift
import Foundation
import CoreData

extension TripParticipant {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TripParticipant> {
        return NSFetchRequest<TripParticipant>(entityName: "TripParticipant")
    }

    @NSManaged public var displayName: String
    @NSManaged public var cloudKitUserID: String
    @NSManaged public var joinedDate: Date
    @NSManaged public var trip: Trip?
}

extension TripParticipant: Identifiable {}
```

- [ ] **Step 10: Delete old SwiftData model files**

```bash
git rm myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/Trip.swift
git rm myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/PlateSighting.swift
git rm myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/ObservationEntry.swift
git rm myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/TripParticipant.swift
```

- [ ] **Step 11: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataModels/
git commit -m "feat: add NSManagedObject subclasses, remove SwiftData models"
```

---

### Task 3: Create Core Data Helpers

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataHelpers.swift`

- [ ] **Step 1: Write CoreDataHelpers.swift**

```swift
import CoreData

// MARK: - Contextual Save

extension NSManagedObjectContext {
    /// Save with contextual info for debugging. No-op if no changes.
    func save(contextInfo: String) {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            print("[CoreData] Failed to save (\(contextInfo)): \(error)")
        }
    }
}

// MARK: - Store Membership

extension NSPersistentStore {
    /// Check whether a managed object belongs to this store.
    func contains(managedObject: NSManagedObject) -> Bool {
        guard let entityName = managedObject.entity.name,
              let context = managedObject.managedObjectContext else {
            return false
        }
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.predicate = NSPredicate(format: "self == %@", managedObject)
        fetchRequest.affectedStores = [self]
        if let count = try? context.count(for: fetchRequest), count > 0 {
            return true
        }
        return false
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CoreDataHelpers.swift
git commit -m "feat: add Core Data helper extensions for save and store membership"
```

---

### Task 4: Rewrite PersistenceController

**Files:**
- Rewrite: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/PersistenceController.swift`

- [ ] **Step 1: Rewrite PersistenceController.swift**

Replace the entire file with:

```swift
import CloudKit
import CoreData
import SwiftUI

@MainActor
@Observable
final class PersistenceController {

    static let shared = PersistenceController()

    static let cloudKitContainerID = "iCloud.com.tentenbits.myRoadTripTracker"

    let persistentContainer: NSPersistentCloudKitContainer

    private var _privatePersistentStore: NSPersistentStore?
    var privatePersistentStore: NSPersistentStore {
        _privatePersistentStore!
    }

    private var _sharedPersistentStore: NSPersistentStore?
    var sharedPersistentStore: NSPersistentStore {
        _sharedPersistentStore!
    }

    var cloudKitContainer: CKContainer {
        CKContainer(identifier: Self.cloudKitContainerID)
    }

    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    init() {
        persistentContainer = NSPersistentCloudKitContainer(name: "myRoadTripTracker")

        let baseURL = NSPersistentContainer.defaultDirectoryURL()
        let storeFolderURL = baseURL.appendingPathComponent("CoreDataStores")
        let privateStoreFolderURL = storeFolderURL.appendingPathComponent("Private")
        let sharedStoreFolderURL = storeFolderURL.appendingPathComponent("Shared")

        // Create directories
        for url in [privateStoreFolderURL, sharedStoreFolderURL] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        // Configure the private store
        guard let privateStoreDescription = persistentContainer.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve a persistent store description.")
        }
        privateStoreDescription.url = privateStoreFolderURL.appendingPathComponent("private.sqlite")
        privateStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateStoreDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let privateCloudKitOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
        privateCloudKitOptions.databaseScope = .private
        privateStoreDescription.cloudKitContainerOptions = privateCloudKitOptions

        // Configure the shared store (copy of private, different URL and scope)
        guard let sharedStoreDescription = privateStoreDescription.copy() as? NSPersistentStoreDescription else {
            fatalError("Failed to copy the private store description.")
        }
        sharedStoreDescription.url = sharedStoreFolderURL.appendingPathComponent("shared.sqlite")

        let sharedCloudKitOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
        sharedCloudKitOptions.databaseScope = .shared
        sharedStoreDescription.cloudKitContainerOptions = sharedCloudKitOptions

        persistentContainer.persistentStoreDescriptions.append(sharedStoreDescription)

        // Load stores
        persistentContainer.loadPersistentStores { [weak self] loadedStoreDescription, error in
            guard let self else { return }
            if let error {
                fatalError("Failed to load persistent stores: \(error)")
            }
            guard let scope = loadedStoreDescription.cloudKitContainerOptions?.databaseScope else { return }
            let store = persistentContainer.persistentStoreCoordinator.persistentStore(for: loadedStoreDescription.url!)
            switch scope {
            case .private:
                self._privatePersistentStore = store
            case .shared:
                self._sharedPersistentStore = store
            default:
                break
            }
        }

        // Configure view context
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
        persistentContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        do {
            try persistentContainer.viewContext.setQueryGenerationFrom(.current)
        } catch {
            fatalError("Failed to pin viewContext to current generation: \(error)")
        }

        // Listen for remote changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeRemoteChange),
            name: .NSPersistentStoreRemoteChange,
            object: persistentContainer.persistentStoreCoordinator
        )
    }

    @objc
    nonisolated private func storeRemoteChange(_ notification: Notification) {
        // The viewContext auto-merges changes. This observer is here so we can
        // add logging or additional processing in the future if needed.
    }

    // MARK: - Sharing

    /// Share a trip. Returns the CKShare for presentation.
    func shareTrip(_ trip: Trip) async throws -> CKShare {
        // Check if already shared
        if let existingShare = existingShare(for: trip) {
            return existingShare
        }
        let (_, share, _) = try await persistentContainer.share([trip], to: nil)
        share[CKShare.SystemFieldKey.title] = trip.name
        share.publicPermission = .readWrite
        persistentContainer.persistUpdatedShare(share, in: privatePersistentStore) { share, error in
            if let error {
                print("[PersistenceController] Failed to persist updated share: \(error)")
            }
        }
        return share
    }

    /// Get the existing CKShare for a trip, if any.
    func existingShare(for trip: Trip) -> CKShare? {
        if let shareSet = try? persistentContainer.fetchShares(matching: [trip.objectID]),
           let (_, share) = shareSet.first {
            return share
        }
        return nil
    }

    /// Accept a share invitation and import it into the shared store.
    func acceptShare(metadata: CKShare.Metadata) {
        persistentContainer.acceptShareInvitations(
            from: [metadata],
            into: sharedPersistentStore
        ) { _, error in
            if let error {
                print("[PersistenceController] Failed to accept share: \(error)")
            }
        }
    }

    /// Check if the current user owns this trip (i.e., it lives in the private store).
    func isOwner(of trip: Trip) -> Bool {
        privatePersistentStore.contains(managedObject: trip)
    }

    /// Check if the user can edit a record.
    func canEdit(_ object: NSManagedObject) -> Bool {
        persistentContainer.canUpdateRecord(forManagedObjectWith: object.objectID)
    }
}
```

- [ ] **Step 2: Verify the file compiles conceptually** — check that it references `Trip`, `NSPersistentCloudKitContainer`, and `CoreDataHelpers` correctly.

- [ ] **Step 3: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/PersistenceController.swift
git commit -m "feat: rewrite PersistenceController with NSPersistentCloudKitContainer two-store setup"
```

---

### Task 5: Rewrite App Entry Point and Delegates

**Files:**
- Rewrite: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/myRoadTripTrackerApp.swift`
- Rewrite: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/AppDelegate.swift`

- [ ] **Step 1: Rewrite myRoadTripTrackerApp.swift**

Replace entire file with:

```swift
import SwiftUI
import CoreData

@main
struct myRoadTripTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .task {
                appDelegate.persistenceController = persistenceController
            }
        }
        .environment(\.managedObjectContext, persistenceController.viewContext)
        .environment(persistenceController)
    }
}
```

- [ ] **Step 2: Rewrite AppDelegate.swift**

Replace entire file with:

```swift
import UIKit
import CloudKit

class AppDelegate: NSObject, UIApplicationDelegate {
    var persistenceController: PersistenceController?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        PersistenceController.shared.acceptShare(metadata: cloudKitShareMetadata)
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            PersistenceController.shared.acceptShare(metadata: metadata)
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/myRoadTripTrackerApp.swift
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/AppDelegate.swift
git commit -m "feat: update app entry point and delegates for Core Data"
```

---

### Task 6: Rewrite CloudSharingView

**Files:**
- Rewrite: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CloudSharingView.swift`

The old file manually created CKShare records. The new version uses the container's share API and UICloudSharingController for managing existing shares.

- [ ] **Step 1: Rewrite CloudSharingView.swift**

Replace entire file with:

```swift
import CloudKit
import CoreData
import LinkPresentation
import SwiftUI

/// Activity item source that provides a CKShare URL with rich link metadata.
final class ShareActivityItem: NSObject, UIActivityItemSource {
    let url: URL
    let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.url = url
        return metadata
    }
}

/// Presents UIActivityViewController with a CKShare URL.
struct CloudSharingView: UIViewControllerRepresentable {
    let shareURL: URL
    let tripName: String
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let item = ShareActivityItem(url: shareURL, title: tripName)
        let controller = UIActivityViewController(
            activityItems: [item],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss()
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

/// ViewModifier that creates/fetches a CKShare then presents the standard share sheet.
struct CloudSharingSheet: ViewModifier {
    @ObservedObject var trip: Trip
    let persistenceController: PersistenceController
    @Binding var isPresented: Bool
    @State private var shareURL: URL?
    @State private var sharingError: String?
    @State private var showingError = false
    @State private var showingSheet = false
    @State private var isSyncing = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, shouldPresent in
                guard shouldPresent else { return }
                Task {
                    await prepareShare()
                }
            }
            .sheet(isPresented: $showingSheet, onDismiss: { isPresented = false }) {
                if let shareURL {
                    CloudSharingView(
                        shareURL: shareURL,
                        tripName: trip.name,
                        onDismiss: {
                            showingSheet = false
                        }
                    )
                }
            }
            .overlay {
                if isSyncing {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Preparing share...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .alert("Sharing Unavailable", isPresented: $showingError) {
                Button("OK") { sharingError = nil }
            } message: {
                Text(
                    sharingError
                        ?? "Unable to share this trip. Please make sure you're signed into iCloud and try again."
                )
            }
    }

    @MainActor
    private func prepareShare() async {
        isSyncing = true
        do {
            let share = try await persistenceController.shareTrip(trip)
            isSyncing = false
            if let url = share.url {
                shareURL = url
                showingSheet = true
            } else {
                isPresented = false
                sharingError = "Failed to create share link. Please try again."
                showingError = true
            }
        } catch {
            isSyncing = false
            isPresented = false
            sharingError = error.localizedDescription
            showingError = true
        }
    }
}

extension View {
    func cloudSharingSheet(
        for trip: Trip, persistenceController: PersistenceController,
        isPresented: Binding<Bool>
    ) -> some View {
        modifier(
            CloudSharingSheet(
                trip: trip, persistenceController: persistenceController,
                isPresented: isPresented))
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/CloudSharingView.swift
git commit -m "feat: rewrite CloudSharingView to use NSPersistentCloudKitContainer share API"
```

---

### Task 7: Migrate ContentView

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/ContentView.swift`

- [ ] **Step 1: Rewrite ContentView.swift**

Replace entire file with:

```swift
import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(PersistenceController.self) private var persistenceController

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Trip.createdDate, ascending: false)],
        animation: .default
    )
    private var trips: FetchedResults<Trip>

    @State private var navigationPath = NavigationPath()
    @State private var newlyCreatedTrip: Trip?
    @State private var isPulsing = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                ForEach(trips) { trip in
                    NavigationLink(value: trip.objectID) {
                        TripRowView(trip: trip)
                    }
                }
                .onDelete(perform: deleteTrips)
            }
            .navigationTitle("Road Trips")
            .navigationDestination(for: NSManagedObjectID.self) { objectID in
                if let trip = viewContext.object(with: objectID) as? Trip {
                    TripDetailView(trip: trip, isNewTrip: objectID == newlyCreatedTrip?.objectID)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addTrip) {
                        Label("Add Trip", systemImage: "plus")
                    }
                    .symbolEffect(.pulse, isActive: isPulsing)
                }
            }
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
            .onAppear {
                isPulsing = trips.isEmpty
            }
            .onChange(of: trips.count) { _, newCount in
                isPulsing = newCount == 0
            }
        }
    }

    private func addTrip() {
        let newTrip = Trip(context: viewContext)
        viewContext.assign(newTrip, to: persistenceController.privatePersistentStore)
        viewContext.save(contextInfo: "addTrip")
        newlyCreatedTrip = newTrip
        navigationPath.append(newTrip.objectID)
    }

    private func deleteTrips(at offsets: IndexSet) {
        for index in offsets {
            viewContext.delete(trips[index])
        }
        viewContext.save(contextInfo: "deleteTrips")
    }
}
```

Note: We use `NSManagedObjectID` for navigation instead of `Trip` directly because `NSManagedObject` is not `Hashable` by default for `NavigationPath`. `NSManagedObjectID` is `Hashable`.

- [ ] **Step 2: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/ContentView.swift
git commit -m "feat: migrate ContentView from SwiftData to Core Data"
```

---

### Task 8: Migrate TripDetailView

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/TripDetailView.swift`

- [ ] **Step 1: Rewrite TripDetailView.swift**

Replace entire file with:

```swift
import SwiftUI
import CoreData

enum TripTab: String, CaseIterable {
    case plates = "Plates"
    case notes = "Notes"
}

struct TripDetailView: View {
    @ObservedObject var trip: Trip
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(PersistenceController.self) private var persistenceController
    @FocusState private var isNameFieldFocused: Bool
    @State private var locationManager = LocationManager()
    @State private var selectedTab: TripTab = .plates
    @State private var showingSharingSheet = false
    @AppStorage("defaultDisplayName") private var currentUserName = "Me"
    let isNewTrip: Bool
    @State private var showingNamePrompt = false
    @State private var resolvedDisplayName: String?
    @State private var cloudKitUserID: String = ""
    @State private var showingParticipants = false
    @State private var isOwner = true

    var body: some View {
        VStack(spacing: 0) {
            TextField("Trip Name", text: $trip.name)
                .font(.title2)
                .fontWeight(.bold)
                .focused($isNameFieldFocused)
                .disabled(trip.isClosed)
                .padding(.horizontal)
                .padding(.top, 8)
                .onChange(of: trip.name) { _, _ in
                    viewContext.save(contextInfo: "tripNameChange")
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isNameFieldFocused = false
                        }
                    }
                }
                .task {
                    if isNewTrip {
                        try? await Task.sleep(for: .milliseconds(100))
                        isNameFieldFocused = true
                    }
                }

            Picker("Tab", selection: $selectedTab) {
                ForEach(TripTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch selectedTab {
            case .plates:
                PlatesTabView(trip: trip, locationManager: locationManager)
            case .notes:
                NotesTabView(trip: trip, currentUserName: resolvedDisplayName ?? currentUserName)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingSharingSheet = true
                } label: {
                    Label("Share Trip", systemImage: "square.and.arrow.up")
                }
                .disabled(!isOwner)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingParticipants = true
                } label: {
                    Label("Participants", systemImage: "person.2")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    trip.isClosed.toggle()
                    viewContext.save(contextInfo: "toggleClosed")
                } label: {
                    Label(
                        trip.isClosed ? "Reopen Trip" : "Close Trip",
                        systemImage: trip.isClosed ? "lock.open" : "lock"
                    )
                }
                .disabled(!isOwner)
            }
        }
        .task {
            cloudKitUserID = await CloudKitUserHelper.currentUserID()
            isOwner = persistenceController.isOwner(of: trip)
            let participants = trip.participantsArray
            if participants.isEmpty {
                let participant = TripParticipant(
                    context: viewContext,
                    displayName: currentUserName,
                    cloudKitUserID: cloudKitUserID
                )
                participant.trip = trip
                viewContext.save(contextInfo: "addInitialParticipant")
                resolvedDisplayName = currentUserName
            } else if let existing = participants.first(where: { $0.cloudKitUserID == cloudKitUserID }) {
                resolvedDisplayName = existing.displayName
            } else {
                showingNamePrompt = true
            }
        }
        .cloudSharingSheet(for: trip, persistenceController: persistenceController, isPresented: $showingSharingSheet)
        .sheet(isPresented: $showingParticipants) {
            ParticipantsView(
                trip: trip,
                isOwner: isOwner,
                currentUserID: cloudKitUserID
            )
        }
        .sheet(isPresented: $showingNamePrompt) {
            JoinTripNameView(trip: trip) { name in
                let participant = TripParticipant(
                    context: viewContext,
                    displayName: name,
                    cloudKitUserID: cloudKitUserID
                )
                participant.trip = trip
                viewContext.save(contextInfo: "joinTrip")
                resolvedDisplayName = name
                showingNamePrompt = false
            }
        }
    }
}

// MARK: - Plates Tab

struct PlatesTabView: View {
    @ObservedObject var trip: Trip
    var locationManager: LocationManager
    @State private var showingMapView = false

    var body: some View {
        List {
            PlateSightingsSection(trip: trip, locationManager: locationManager)

            Section {
                Button {
                    showingMapView = true
                } label: {
                    Label("View Sightings Map", systemImage: "map")
                }
                .disabled(trip.plateSightingsArray.isEmpty)
            }
        }
        .sheet(isPresented: $showingMapView) {
            PlateSightingsMapView(sightings: trip.plateSightingsArray)
        }
    }
}

// MARK: - Notes Tab

struct NotesTabView: View {
    @ObservedObject var trip: Trip
    let currentUserName: String

    var body: some View {
        List {
            ObservationsSection(trip: trip, currentUserName: currentUserName)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/TripDetailView.swift
git commit -m "feat: migrate TripDetailView from SwiftData to Core Data"
```

---

### Task 9: Migrate PlateSightingsSection

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/PlateSightingsSection.swift`

- [ ] **Step 1: Rewrite PlateSightingsSection.swift**

Replace entire file with:

```swift
import SwiftUI
import CoreData
import CoreLocation

struct PlateSightingsSection: View {
    @ObservedObject var trip: Trip
    var locationManager: LocationManager
    @Environment(\.managedObjectContext) private var viewContext
    @State private var locationToRemove: Location?

    private var sightings: [PlateSighting] {
        trip.plateSightingsArray
    }

    private var seenCount: Int {
        sightings.count
    }

    private var totalCount: Int {
        Location.allLocations.count
    }

    var body: some View {
        Section {
            ForEach(Location.allLocations) { location in
                PlateRow(
                    location: location,
                    isSeen: isSeen(location),
                    onTap: { markAsSeen(location) },
                    onRemove: { locationToRemove = location }
                )
                .disabled(trip.isClosed)
            }
        } header: {
            HStack {
                Text("License Plates")
                Spacer()
                Text("\(seenCount)/\(totalCount)")
                    .fontWeight(.semibold)
            }
        }
        .alert(
            "Remove Sighting",
            isPresented: Binding(
                get: { locationToRemove != nil },
                set: { if !$0 { locationToRemove = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let location = locationToRemove {
                    unmarkAsSeen(location)
                }
                locationToRemove = nil
            }
            Button("Cancel", role: .cancel) {
                locationToRemove = nil
            }
        } message: {
            if let location = locationToRemove {
                Text("Remove the \(location.name) plate sighting? This will delete the location data.")
            }
        }
    }

    private func isSeen(_ location: Location) -> Bool {
        sightings.contains { $0.locationCode == location.code }
    }

    private func markAsSeen(_ location: Location) {
        guard !isSeen(location) else { return }

        Task {
            let loc = await locationManager.requestCurrentLocation()
            let latitude = loc?.coordinate.latitude ?? 0.0
            let longitude = loc?.coordinate.longitude ?? 0.0

            let sighting = PlateSighting(
                context: viewContext,
                locationCode: location.code,
                locationName: location.name,
                latitude: latitude,
                longitude: longitude
            )
            sighting.trip = trip
            viewContext.save(contextInfo: "markAsSeen")
        }
    }

    private func unmarkAsSeen(_ location: Location) {
        guard let sighting = sightings.first(where: { $0.locationCode == location.code }) else { return }
        viewContext.delete(sighting)
        viewContext.save(contextInfo: "unmarkAsSeen")
    }
}

struct PlateRow: View {
    let location: Location
    let isSeen: Bool
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: { isSeen ? onRemove() : onTap() }) {
            HStack(spacing: 12) {
                Image(location.flagImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 20)
                    .clipShape(.rect(cornerRadius: 2))
                    .accessibilityHidden(true)

                Text(location.code)
                    .font(.system(.body, design: .monospaced))
                    .bold()
                    .frame(width: 36, alignment: .leading)

                Text(location.name)

                Spacer()

                if isSeen {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
            .background(isSeen ? Color.green.opacity(0.1) : Color.clear)
            .accessibilityLabel("\(location.name), \(isSeen ? "seen" : "not seen")")
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if isSeen {
                Button("Remove", role: .destructive, action: onRemove)
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/PlateSightingsSection.swift
git commit -m "feat: migrate PlateSightingsSection from SwiftData to Core Data"
```

---

### Task 10: Migrate ObservationsSection and ObservationRow

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/ObservationsSection.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/ObservationRow.swift`

- [ ] **Step 1: Rewrite ObservationsSection.swift**

Replace entire file with:

```swift
import SwiftUI
import CoreData

struct ObservationsSection: View {
    @ObservedObject var trip: Trip
    let currentUserName: String
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""

    private let predefinedCategories = [
        "Weirdest thing we've seen",
        "Coolest car",
        "Funniest billboard",
        "Weirdest billboard",
        "Best roadside attraction",
        "Most interesting license plate",
    ]

    var body: some View {
        ForEach(allCategories, id: \.self) { category in
            Section {
                let entries = entriesForCategory(category)
                if entries.isEmpty {
                    Text("No entries yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                ForEach(entries) { entry in
                    ObservationEntryRow(entry: entry)
                }
                if !trip.isClosed {
                    ComposeEntryRow(category: category, authorName: currentUserName) { text in
                        addEntry(category: category, text: text)
                    }
                }
            } header: {
                Text(category)
            }
        }

        if !trip.isClosed {
            Section {
                Button {
                    showingAddCategory = true
                } label: {
                    Label("Add Custom Category", systemImage: "plus.circle.fill")
                }
            }
            .alert("Add Custom Category", isPresented: $showingAddCategory) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) {
                    newCategoryName = ""
                }
                Button("Add") {
                    newCategoryName = ""
                }
            }
        }
    }

    private var allCategories: [String] {
        let entries = trip.observationEntriesArray
        let entryCategories = Set(entries.map { $0.category })
        var categories = predefinedCategories
        let custom = entryCategories.filter { !predefinedCategories.contains($0) }.sorted()
        categories.append(contentsOf: custom)
        return categories
    }

    private func entriesForCategory(_ category: String) -> [ObservationEntry] {
        trip.observationEntriesArray
            .filter { $0.category == category }
    }

    private func addEntry(category: String, text: String) {
        let entry = ObservationEntry(
            context: viewContext,
            category: category,
            authorName: currentUserName,
            text: text
        )
        entry.trip = trip
        viewContext.save(contextInfo: "addObservation")
    }
}

struct ComposeEntryRow: View {
    let category: String
    let authorName: String
    let onSubmit: (String) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            TextField("Add an observation...", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    submitEntry()
                }
            Button("Submit", systemImage: "arrow.up.circle.fill") {
                submitEntry()
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func submitEntry() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        text = ""
    }
}
```

- [ ] **Step 2: Rewrite ObservationRow.swift**

Replace entire file with:

```swift
import SwiftUI

struct ObservationEntryRow: View {
    @ObservedObject var entry: ObservationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.authorName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(entry.createdDate, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.text)
                .font(.body)
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/ObservationsSection.swift
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/ObservationRow.swift
git commit -m "feat: migrate ObservationsSection and ObservationRow from SwiftData to Core Data"
```

---

### Task 11: Migrate Remaining Views

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/ParticipantsView.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/TripRowView.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/JoinTripNameView.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/PlateSightingsMapView.swift`

- [ ] **Step 1: Rewrite ParticipantsView.swift**

Replace entire file with:

```swift
import SwiftUI
import CoreData

struct ParticipantsView: View {
    @ObservedObject var trip: Trip
    let isOwner: Bool
    let currentUserID: String
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(trip.participantsArray) { participant in
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(participant.displayName)
                                    .font(.body)
                                if participant.cloudKitUserID == currentUserID {
                                    Text("(you)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("Joined \(participant.joinedDate, style: .date)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        if isOwner && participant.cloudKitUserID != currentUserID {
                            Button("Remove", role: .destructive) {
                                removeParticipant(participant)
                            }
                        }
                        if !isOwner && participant.cloudKitUserID == currentUserID {
                            Button("Leave", role: .destructive) {
                                leaveTrip(participant)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Participants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if trip.participantsArray.isEmpty {
                    ContentUnavailableView {
                        Label("No Participants", systemImage: "person.2")
                    } description: {
                        Text("Share this trip to add participants.")
                    }
                }
            }
        }
    }

    private func removeParticipant(_ participant: TripParticipant) {
        viewContext.delete(participant)
        viewContext.save(contextInfo: "removeParticipant")
    }

    private func leaveTrip(_ participant: TripParticipant) {
        removeParticipant(participant)
        dismiss()
    }
}
```

- [ ] **Step 2: Rewrite TripRowView.swift**

Replace entire file with:

```swift
import SwiftUI

struct TripRowView: View {
    @ObservedObject var trip: Trip

    private var sightings: [PlateSighting] { trip.plateSightingsArray }
    private var seenCount: Int { sightings.count }
    private var totalCount: Int { Location.allLocations.count }
    private var percentage: Int {
        totalCount > 0 ? (seenCount * 100) / totalCount : 0
    }
    private var isShared: Bool { trip.participantsArray.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trip.name)
                    .font(.headline)
                if trip.isClosed {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                if isShared {
                    HStack(spacing: 2) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text("\(trip.participantsArray.count)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("^[\(trip.participantsArray.count) participant](inflect: true)")
                }
            }
            HStack(spacing: 0) {
                Text(trip.createdDate, style: .date)
                Text("  —  \(seenCount)/\(totalCount): \(percentage)%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 3: Rewrite JoinTripNameView.swift**

Replace entire file with:

```swift
import SwiftUI

struct JoinTripNameView: View {
    @ObservedObject var trip: Trip
    let onComplete: (String) -> Void
    @AppStorage("defaultDisplayName") private var defaultDisplayName = ""
    @State private var displayName = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Joining \"\(trip.name)\"")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("What should other participants call you on this trip?")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Display name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)

                Spacer()
            }
            .padding(32)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        onComplete(name)
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                displayName = defaultDisplayName
                isFocused = true
            }
        }
    }
}
```

- [ ] **Step 4: Rewrite PlateSightingsMapView.swift**

Replace entire file with:

```swift
import SwiftUI
import MapKit

struct PlateSightingsMapView: View {
    let sightings: [PlateSighting]
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                ForEach(sightings) { sighting in
                    Marker(sighting.locationCode, coordinate: sighting.coordinate)
                        .tint(.green)
                }
            }
            .mapStyle(.standard)
            .navigationTitle("Plate Sightings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/ParticipantsView.swift
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/TripRowView.swift
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/JoinTripNameView.swift
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/PlateSightingsMapView.swift
git commit -m "feat: migrate ParticipantsView, TripRowView, JoinTripNameView, PlateSightingsMapView to Core Data"
```

---

### Task 12: Update Xcode Project and Build Verification

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/myRoadTripTracker.xcodeproj/project.pbxproj`

This task requires Xcode interaction because the `.pbxproj` file needs to:
1. Add the new `.xcdatamodeld` to the project
2. Add all new `CoreDataModels/*.swift` files to the build
3. Add `CoreDataHelpers.swift` to the build
4. Remove old SwiftData model files from the build

- [ ] **Step 1: Open the project in Xcode**

```bash
open myRoadTripTracker/myRoadTripTracker/myRoadTripTracker.xcodeproj
```

- [ ] **Step 2: In Xcode, add new files to the project**

In the Project Navigator:
1. Right-click the `myRoadTripTracker` group → "Add Files to myRoadTripTracker..."
2. Add the `myRoadTripTracker.xcdatamodeld` file
3. Add the `CoreDataModels/` folder (check "Create groups")
4. Add `CoreDataHelpers.swift`
5. Verify old SwiftData model files (`Trip.swift`, `PlateSighting.swift`, `ObservationEntry.swift`, `TripParticipant.swift`) are no longer in the project (they were `git rm`'d)

- [ ] **Step 3: In the .xcdatamodeld, set Codegen to Manual/None for all entities**

1. Open `myRoadTripTracker.xcdatamodeld` in Xcode
2. Select each entity (Trip, PlateSighting, ObservationEntry, TripParticipant)
3. In the Data Model Inspector (right panel), set:
   - **Codegen**: Manual/None
   - **Module**: Current Product Module

- [ ] **Step 4: Build the project**

In Xcode: Product → Build (⌘B)

Fix any compilation errors. Common issues to watch for:
- Missing imports (add `import CoreData` where needed)
- Type mismatches (ensure `NSSet?` is handled via the array convenience properties)
- Missing `@ObservedObject` where `@Bindable` was used

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: update Xcode project for Core Data migration, verify build"
```

---

### Task 13: Delete Old SwiftData SQLite Data

Since this is a clean break, we should delete any old SwiftData SQLite files on the device so they don't conflict.

- [ ] **Step 1: Add cleanup code to PersistenceController.init()**

Add the following method to `PersistenceController` and call it at the start of `init()`:

In `PersistenceController.swift`, add this static method before the `init()`:

```swift
/// One-time cleanup: remove old SwiftData store if it exists.
private static func removeOldSwiftDataStoreIfNeeded() {
    let key = "didRemoveOldSwiftDataStore"
    guard !UserDefaults.standard.bool(forKey: key) else { return }
    let baseURL = NSPersistentContainer.defaultDirectoryURL()
    let oldStoreURL = baseURL.appendingPathComponent("default.store")
    for suffix in ["", "-shm", "-wal"] {
        let url = oldStoreURL.appendingPathExtension(suffix.isEmpty ? "" : String(suffix.dropFirst()))
        // Try both possible naming patterns
        let fileURL = suffix.isEmpty ? oldStoreURL : URL(fileURLWithPath: oldStoreURL.path + suffix)
        try? FileManager.default.removeItem(at: fileURL)
    }
    UserDefaults.standard.set(true, forKey: key)
}
```

Then at the very start of `init()`, add:

```swift
Self.removeOldSwiftDataStoreIfNeeded()
```

- [ ] **Step 2: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/myRoadTripTracker/PersistenceController.swift
git commit -m "chore: add one-time cleanup of old SwiftData store files"
```

---

### Task 14: Test on Device

This task is manual testing on a physical device or simulator pair.

- [ ] **Step 1: Run on simulator — basic trip CRUD**

1. Launch app in iOS simulator
2. Complete onboarding (enter display name)
3. Create a new trip, name it
4. Mark several plates as seen
5. Add observation entries
6. Verify plate count updates in trip list
7. Close and reopen the trip
8. Delete the trip

- [ ] **Step 2: Run on two devices — sharing flow**

1. Install on Device A (your phone) and Device B (Marie's phone or second simulator)
2. On Device A: create a trip, mark a few plates
3. On Device A: tap Share Trip, send the link to Device B
4. On Device B: tap the share link, accept
5. **Verify:** trip appears on Device B with existing plate sightings
6. On Device B: mark a new plate
7. **Verify:** new plate appears on Device A within seconds
8. On Device A: add an observation
9. **Verify:** observation appears on Device B

- [ ] **Step 3: Verify edge cases**

1. Mark the same plate on both devices simultaneously → only one sighting should remain
2. Both devices add observations → both appear on both devices (append-only)
3. Close trip on Device A → verify Device B sees it as closed

- [ ] **Step 4: If all tests pass, commit any final fixes**

```bash
git add -A
git commit -m "fix: address issues found during device testing"
```
