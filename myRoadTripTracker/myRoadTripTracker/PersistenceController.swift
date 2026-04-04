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
