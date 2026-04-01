import CloudKit
import CoreData
import SwiftData
import SwiftUI

@MainActor
@Observable
final class PersistenceController {

    let modelContainer: ModelContainer
    let cloudKitContainer: NSPersistentCloudKitContainer

    // References to the loaded persistent stores
    private var privatePersistentStore: NSPersistentStore?
    private var sharedPersistentStore: NSPersistentStore?

    static let cloudKitContainerID = "iCloud.com.tentenbits.myRoadTripTracker"

    init() {
        // 1. Build the NSManagedObjectModel from SwiftData @Model types
        let modelTypes: [any PersistentModel.Type] = [
            Trip.self, PlateSighting.self, ObservationEntry.self, TripParticipant.self
        ]
        guard let mom = NSManagedObjectModel.makeManagedObjectModel(for: modelTypes) else {
            fatalError("Failed to create NSManagedObjectModel from SwiftData models")
        }

        #if DEBUG
        Self.logModelInfo(mom)
        #endif

        // 2. Determine store URLs
        let baseURL = URL.applicationSupportDirectory.appending(path: "myRoadTripTracker")
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let privateStoreURL = baseURL.appending(path: "Private.sqlite")
        let sharedStoreURL = baseURL.appending(path: "Shared.sqlite")

        // 3. Configure NSPersistentCloudKitContainer
        let container = NSPersistentCloudKitContainer(name: "myRoadTripTracker", managedObjectModel: mom)

        // Private store description
        let privateDesc = NSPersistentStoreDescription(url: privateStoreURL)
        privateDesc.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: Self.cloudKitContainerID
        )
        privateDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // Shared store description
        let sharedDesc = NSPersistentStoreDescription(url: sharedStoreURL)
        let sharedOpts = NSPersistentCloudKitContainerOptions(
            containerIdentifier: Self.cloudKitContainerID
        )
        sharedOpts.databaseScope = .shared
        sharedDesc.cloudKitContainerOptions = sharedOpts
        sharedDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.persistentStoreDescriptions = [privateDesc, sharedDesc]

        // Load stores
        var loadedPrivateStore: NSPersistentStore?
        var loadedSharedStore: NSPersistentStore?

        container.loadPersistentStores { description, error in
            if let error {
                fatalError("Failed to load persistent store: \(error)")
            }
            // Match loaded stores by URL
            if let store = container.persistentStoreCoordinator.persistentStore(for: description.url!) {
                if description.cloudKitContainerOptions?.databaseScope == .shared {
                    loadedSharedStore = store
                } else {
                    loadedPrivateStore = store
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        assert(loadedPrivateStore != nil, "Private persistent store failed to load")
        assert(loadedSharedStore != nil, "Shared persistent store failed to load")

        self.cloudKitContainer = container
        self.privatePersistentStore = loadedPrivateStore
        self.sharedPersistentStore = loadedSharedStore

        // 4. Create SwiftData ModelContainer pointing at same store files, CloudKit disabled
        let schema = Schema(modelTypes)
        let privateConfig = ModelConfiguration(
            "Private",
            schema: schema,
            url: privateStoreURL,
            cloudKitDatabase: .none
        )
        let sharedConfig = ModelConfiguration(
            "Shared",
            schema: schema,
            url: sharedStoreURL,
            cloudKitDatabase: .none
        )

        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [privateConfig, sharedConfig])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: - Sharing APIs

    /// Find the Core Data managed object corresponding to a SwiftData Trip (by tripID UUID).
    private func fetchManagedObject(for trip: Trip) -> NSManagedObject? {
        let context = cloudKitContainer.viewContext
        // Refresh context to pick up any changes from SwiftData's coordinator
        context.refreshAllObjects()

        let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
        request.predicate = NSPredicate(format: "tripID == %@", trip.tripID as CVarArg)
        request.fetchLimit = 1

        do {
            let results = try context.fetch(request)
            print("[PersistenceController] fetchManagedObject: found \(results.count) trips for tripID=\(trip.tripID)")
            if results.isEmpty {
                // Debug: list all trips in Core Data to see what's there
                let allRequest = NSFetchRequest<NSManagedObject>(entityName: "Trip")
                let allTrips = try context.fetch(allRequest)
                print("[PersistenceController] All trips in Core Data (\(allTrips.count)):")
                for t in allTrips {
                    let name = t.value(forKey: "name") as? String ?? "?"
                    let id = t.value(forKey: "tripID") as? UUID ?? UUID()
                    print("  - \(name) (tripID=\(id))")
                }
            }
            return results.first
        } catch {
            print("[PersistenceController] fetchManagedObject error: \(error)")
            return nil
        }
    }

    /// Create a CKShare for a trip and return the share + CKContainer for UICloudSharingController.
    func shareTrip(_ trip: Trip) async throws -> (CKShare, CKContainer) {
        guard let managedObject = fetchManagedObject(for: trip) else {
            throw SharingError.tripNotFound
        }

        print("[PersistenceController] shareTrip: sharing managed object \(managedObject.objectID), store: \(managedObject.objectID.persistentStore?.url?.lastPathComponent ?? "unknown")")

        do {
            let (_, share, ckContainer) = try await cloudKitContainer.share(
                [managedObject],
                to: nil
            )
            share[CKShare.SystemFieldKey.title] = trip.name

            // Save the context to persist the share
            try cloudKitContainer.viewContext.save()

            return (share, ckContainer)
        } catch {
            print("[PersistenceController] shareTrip error: \(error)")
            throw error
        }
    }

    /// Fetch an existing CKShare for a trip, if one exists.
    func fetchShare(for trip: Trip) -> CKShare? {
        guard let managedObject = fetchManagedObject(for: trip) else { return nil }
        let shares = try? cloudKitContainer.fetchShares(matching: [managedObject.objectID])
        return shares?[managedObject.objectID]
    }

    /// Check if the current user is the owner of a trip.
    func isOwner(of trip: Trip) -> Bool {
        guard let share = fetchShare(for: trip) else {
            return true // No share = private trip, user is owner
        }
        return share.currentUserParticipant?.role == .owner
    }

    /// Accept incoming share invitations.
    func acceptShare(metadata: CKShare.Metadata) {
        guard let sharedStore = sharedPersistentStore else { return }
        cloudKitContainer.acceptShareInvitations(
            from: [metadata],
            into: sharedStore
        ) { _, error in
            if let error {
                print("Failed to accept share: \(error)")
            }
        }
    }

    /// Check which store a managed object belongs to (private or shared).
    func isShared(_ trip: Trip) -> Bool {
        guard let managedObject = fetchManagedObject(for: trip),
              let store = managedObject.objectID.persistentStore else {
            return false
        }
        return store == sharedPersistentStore
    }

    // MARK: - Debug Helpers

    #if DEBUG
    /// Logs the entity names and attribute names/types from the generated NSManagedObjectModel.
    /// Use this to verify that makeManagedObjectModel(for:) produces plain Swift class names
    /// (e.g. "Trip", not "CD_Trip") and unmodified attribute names (e.g. "tripID", not "CD_tripID").
    /// The CD_ prefix only appears in CloudKit record type names — not in the Core Data model itself.
    private static func logModelInfo(_ mom: NSManagedObjectModel) {
        print("[PersistenceController] --- NSManagedObjectModel entity map ---")
        for entity in mom.entities {
            print("[PersistenceController] Entity: \(entity.name ?? "unnamed")")
            for (name, attr) in entity.attributesByName {
                print("  - \(name): \(attr.attributeType.rawValue)")
            }
        }
        print("[PersistenceController] --- end entity map ---")
    }
    #endif

    enum SharingError: LocalizedError {
        case tripNotFound

        var errorDescription: String? {
            switch self {
            case .tripNotFound:
                return "Could not find this trip in CloudKit. Make sure you're signed into iCloud."
            }
        }
    }
}
