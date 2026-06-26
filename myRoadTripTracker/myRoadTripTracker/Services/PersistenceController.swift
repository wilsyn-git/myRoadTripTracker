import CloudKit
import CoreData
import os.log
import SwiftUI

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "myRoadTripTracker", category: "Persistence")

@MainActor
@Observable
final class PersistenceController {

    static let shared = PersistenceController()

    static let cloudKitContainerID = "iCloud.com.tentenbits.myRoadTripTracker"

    let persistentContainer: NSPersistentCloudKitContainer

    private var _privatePersistentStore: NSPersistentStore?
    var privatePersistentStore: NSPersistentStore? {
        _privatePersistentStore
    }

    private var _sharedPersistentStore: NSPersistentStore?
    private var remoteChangeObserver: Any?
    private var lastHistoryToken: NSPersistentHistoryToken?
    private var pendingShareMetadata: [CKShare.Metadata] = []
    var shareAcceptanceError: String?
    /// Non-nil if the database failed to initialize. Observed by the UI to show an error screen.
    var setupError: String?
    var sharedPersistentStore: NSPersistentStore? {
        _sharedPersistentStore
    }

    var cloudKitContainer: CKContainer {
        CKContainer(identifier: Self.cloudKitContainerID)
    }

    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    /// One-time cleanup: remove old SwiftData store if it exists.
    private static func removeOldSwiftDataStoreIfNeeded() {
        let key = "didRemoveOldSwiftDataStore"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let baseURL = NSPersistentContainer.defaultDirectoryURL()
        // SwiftData's default store uses "default.store" naming
        let possibleNames = ["default.store", "default.store-shm", "default.store-wal"]
        for name in possibleNames {
            let url = baseURL.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    init() {
        Self.removeOldSwiftDataStoreIfNeeded()
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
            logger.error("Failed to retrieve a persistent store description.")
            setupError = "Unable to initialize the database. Please reinstall the app."
            return
        }
        privateStoreDescription.url = privateStoreFolderURL.appendingPathComponent("private.sqlite")
        privateStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateStoreDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let privateCloudKitOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
        privateCloudKitOptions.databaseScope = .private
        privateStoreDescription.cloudKitContainerOptions = privateCloudKitOptions

        // Configure the shared store (copy of private, different URL and scope)
        guard let sharedStoreDescription = privateStoreDescription.copy() as? NSPersistentStoreDescription else {
            logger.error("Failed to copy the private store description.")
            setupError = "Unable to initialize the database. Please reinstall the app."
            return
        }
        sharedStoreDescription.url = sharedStoreFolderURL.appendingPathComponent("shared.sqlite")

        let sharedCloudKitOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
        sharedCloudKitOptions.databaseScope = .shared
        sharedStoreDescription.cloudKitContainerOptions = sharedCloudKitOptions

        persistentContainer.persistentStoreDescriptions = [privateStoreDescription, sharedStoreDescription]

        // Load stores — use local vars to avoid capturing self during init
        var privateStore: NSPersistentStore?
        var sharedStore: NSPersistentStore?
        var loadError: Error?
        let coordinator = persistentContainer.persistentStoreCoordinator

        persistentContainer.loadPersistentStores { loadedStoreDescription, error in
            if let error {
                logger.error("Failed to load persistent store: \(error.localizedDescription)")
                loadError = error
                return
            }
            guard let scope = loadedStoreDescription.cloudKitContainerOptions?.databaseScope else { return }
            guard let storeURL = loadedStoreDescription.url,
                  let store = coordinator.persistentStore(for: storeURL) else { return }
            switch scope {
            case .private:
                privateStore = store
            case .shared:
                sharedStore = store
            default:
                break
            }
        }

        if let loadError {
            setupError = "Unable to load your data: \(loadError.localizedDescription)"
        }

        _privatePersistentStore = privateStore
        _sharedPersistentStore = sharedStore

        #if DEBUG
        do {
            try persistentContainer.initializeCloudKitSchema()
            logger.info("CloudKit schema initialized successfully.")
        } catch {
            logger.error("Failed to initialize CloudKit schema: \(error.localizedDescription)")
        }
        #endif

        // Configure view context
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
        persistentContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        do {
            try persistentContainer.viewContext.setQueryGenerationFrom(.current)
        } catch {
            logger.error("Failed to pin viewContext to current generation: \(error.localizedDescription)")
        }

        // Listen for remote changes and merge them into the view context
        lastHistoryToken = Self.loadHistoryToken()
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistentContainer.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.processRemoteChanges()
            }
        }

        // Process any share invitations queued before stores finished loading.
        drainPendingShares()
    }

    /// Fetch persistent history since the last token and merge changes into the view context.
    private func processRemoteChanges() {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: lastHistoryToken)
        guard let result = try? viewContext.execute(request) as? NSPersistentHistoryResult,
              let transactions = result.result as? [NSPersistentHistoryTransaction],
              !transactions.isEmpty else {
            return
        }
        for transaction in transactions {
            viewContext.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
        }
        lastHistoryToken = transactions.last?.token
        Self.saveHistoryToken(lastHistoryToken)
    }

    private static func loadHistoryToken() -> NSPersistentHistoryToken? {
        let url = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("historyToken.data")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
    }

    private static func saveHistoryToken(_ token: NSPersistentHistoryToken?) {
        let url = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("historyToken.data")
        guard let token,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        try? data.write(to: url)
    }

    // MARK: - Sharing

    /// Share a trip. Returns the CKShare for presentation.
    func shareTrip(_ trip: Trip) async throws -> CKShare {
        if let existingShare = existingShare(for: trip) {
            return existingShare
        }
        guard let store = privatePersistentStore else {
            throw NSError(domain: "PersistenceController", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Private store not loaded."])
        }
        let (_, share, _) = try await persistentContainer.share([trip], to: nil)
        share[CKShare.SystemFieldKey.title] = trip.name
        share.publicPermission = .readWrite
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            persistentContainer.persistUpdatedShare(share, in: store) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
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
        guard let store = sharedPersistentStore else {
            // Shared store not loaded yet — queue and process once it is ready, rather than
            // surfacing a user-blaming "restart the app" error.
            pendingShareMetadata.append(metadata)
            logger.info("Shared store not ready; queued share invitation for later acceptance.")
            return
        }
        persistentContainer.acceptShareInvitations(
            from: [metadata],
            into: store
        ) { _, error in
            if let error {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    self?.shareAcceptanceError = "Failed to join shared trip: \(message)"
                }
            }
        }
    }

    /// Process any share invitations that were queued before the shared store finished loading.
    private func drainPendingShares() {
        guard sharedPersistentStore != nil, !pendingShareMetadata.isEmpty else { return }
        let queued = pendingShareMetadata
        pendingShareMetadata = []
        for metadata in queued {
            acceptShare(metadata: metadata)
        }
    }

    /// Check if the current user owns this trip (i.e., it lives in the private store).
    func isOwner(of trip: Trip) -> Bool {
        guard let store = privatePersistentStore else { return true }
        return store.contains(managedObject: trip)
    }

    /// Check if the user can edit a record.
    func canEdit(_ object: NSManagedObject) -> Bool {
        persistentContainer.canUpdateRecord(forManagedObjectWith: object.objectID)
    }
}
