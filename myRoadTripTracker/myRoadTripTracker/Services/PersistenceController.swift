import CloudKit
import CoreData
import os.log
import SwiftUI

nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "myRoadTripTracker", category: "Persistence")

@MainActor
@Observable
final class PersistenceController {

    static let shared = PersistenceController()

    nonisolated static let cloudKitContainerID = "iCloud.com.tentenbits.myRoadTripTracker"

    let persistentContainer: NSPersistentCloudKitContainer

    private var _privatePersistentStore: NSPersistentStore?
    var privatePersistentStore: NSPersistentStore? {
        _privatePersistentStore
    }

    private var _sharedPersistentStore: NSPersistentStore?
    private var remoteChangeObserver: Any?
    /// The author stamped on contexts this app saves from. History processing skips these
    /// transactions, since they're already in the view context (#40).
    nonisolated static let appTransactionAuthor = "app"
    /// Reads persistent history off the main thread.
    private let historyContext: NSManagedObjectContext
    /// Per store identifier: the last history transaction merged into `viewContext`.
    @ObservationIgnored private var historyTokens: [String: NSPersistentHistoryToken] = [:]
    @ObservationIgnored private var isProcessingHistory = false
    @ObservationIgnored private var historyNeedsAnotherPass = false
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
        historyContext = persistentContainer.newBackgroundContext()

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
        // Pushes the model to the CloudKit development schema. It's a synchronous CloudKit
        // round-trip on the main thread before the first frame, so it runs only when asked:
        // launch with `-initCloudKitSchema` after changing the model (docs/releaseProcess.md).
        if ProcessInfo.processInfo.arguments.contains("-initCloudKitSchema") {
            do {
                try persistentContainer.initializeCloudKitSchema()
                logger.info("CloudKit schema initialized successfully.")
            } catch {
                logger.error("Failed to initialize CloudKit schema: \(error.localizedDescription)")
            }
        }
        #endif

        // Configure view context
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
        persistentContainer.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        persistentContainer.viewContext.transactionAuthor = Self.appTransactionAuthor

        // Merge only history from here on. A freshly loaded view context already reads
        // everything saved before launch, so tokens live in memory and start at "now".
        // Take them before pinning the generation, so nothing falls between the two.
        for store in [privateStore, sharedStore].compactMap({ $0 }) {
            if let token = coordinator.currentPersistentHistoryToken(fromStores: [store]) {
                historyTokens[store.identifier] = token
            }
        }
        // Tokens used to be kept on disk; remove the old file.
        try? FileManager.default.removeItem(at: baseURL.appendingPathComponent("historyToken.data"))

        do {
            try persistentContainer.viewContext.setQueryGenerationFrom(.current)
        } catch {
            logger.error("Failed to pin viewContext to current generation: \(error.localizedDescription)")
        }

        // Listen for remote changes and merge them into the view context
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistentContainer.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleHistoryProcessing()
            }
        }

        // Repair trips created before `Trip(context:)` was fixed to run the convenience initializer.
        backfillTripMetadata()

        // Process any share invitations queued before stores finished loading.
        drainPendingShares()
    }

    /// Repairs trips saved with a nil `createdDate` / `tripID`.
    ///
    /// Trips created before the `Trip(context:)` initializer fix silently skipped the convenience
    /// initializer, so neither field was ever written. `createdDate` is reconstructed from the trip's
    /// earliest child record — usually the first plate sighting — which is the closest thing to a real
    /// start date we still have. Trips with no children keep a nil date rather than being given a
    /// fabricated one; they self-heal on a later launch once they gain their first sighting or note.
    ///
    /// Scoped to the private store: we can only safely write to trips we own.
    private func backfillTripMetadata() {
        guard let privateStore = _privatePersistentStore else { return }

        let request = Trip.fetchRequest()
        request.predicate = NSPredicate(format: "createdDate == nil OR tripID == nil")
        request.affectedStores = [privateStore]

        let trips: [Trip]
        do {
            trips = try viewContext.fetch(request)
        } catch {
            logger.error("Trip metadata backfill fetch failed: \(error.localizedDescription)")
            return
        }
        guard !trips.isEmpty else { return }

        var repairedDates = 0
        for trip in trips {
            if trip.tripID == nil {
                trip.tripID = UUID()
            }
            if trip.createdDate == nil, let earliest = Self.earliestActivityDate(in: trip) {
                trip.createdDate = earliest
                repairedDates += 1
            }
        }

        guard viewContext.hasChanges else { return }
        viewContext.save(contextInfo: "backfillTripMetadata")
        logger.info("Backfilled metadata for \(trips.count) trip(s); \(repairedDates) date(s) recovered.")
    }

    /// The earliest timestamp across a trip's plate sightings and observation entries, if any.
    private static func earliestActivityDate(in trip: Trip) -> Date? {
        let sightingDates = trip.plateSightingsArray.compactMap(\.seenDate)
        let observationDates = trip.observationEntriesArray.compactMap(\.createdDate)
        return (sightingDates + observationDates).min()
    }

    // MARK: - Remote changes

    /// Coalesces bursts of store-change notifications (a CloudKit import posts many): one
    /// pass at a time, plus one more if notifications arrived during it.
    private func scheduleHistoryProcessing() {
        guard !isProcessingHistory else {
            historyNeedsAnotherPass = true
            return
        }
        isProcessingHistory = true
        Task {
            repeat {
                historyNeedsAnotherPass = false
                await processRemoteChanges()
            } while historyNeedsAnotherPass
            isProcessingHistory = false
        }
    }

    /// Fetches the stores' new history off the main thread, skipping our own transactions,
    /// and merges it into the view context in one pass. Live sync depends on this
    /// (CLAUDE.md): `automaticallyMergesChangesFromParent` alone doesn't refresh the UI.
    private func processRemoteChanges() async {
        let context = historyContext
        let tokens = historyTokens
        let (changes, newTokens) = await context.perform {
            // Read the stores on this queue: `NSPersistentStore` isn't Sendable, so they can't
            // be captured (#47). The coordinator holds exactly the private and shared stores.
            let stores = context.persistentStoreCoordinator?.persistentStores ?? []
            return Self.fetchHistory(in: context, stores: stores, after: tokens)
        }
        historyTokens = newTokens
        guard !changes.isEmpty else { return }
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes.userInfo, into: [viewContext])
    }

    /// Object IDs changed by a batch of history transactions, ready for a single merge.
    /// Built on `historyContext`'s queue, so it's nonisolated.
    nonisolated private struct HistoryChanges {
        var inserted = Set<NSManagedObjectID>()
        var updated = Set<NSManagedObjectID>()
        var deleted = Set<NSManagedObjectID>()

        var isEmpty: Bool { inserted.isEmpty && updated.isEmpty && deleted.isEmpty }

        var userInfo: [AnyHashable: Any] {
            [NSInsertedObjectsKey: Array(inserted),
             NSUpdatedObjectsKey: Array(updated),
             NSDeletedObjectsKey: Array(deleted)]
        }

        mutating func add(_ change: NSPersistentHistoryChange) {
            let id = change.changedObjectID
            switch change.changeType {
            case .insert: inserted.insert(id)
            case .update: updated.insert(id)
            case .delete:
                deleted.insert(id)
                inserted.remove(id)
                updated.remove(id)
            @unknown default: break
            }
        }
    }

    /// Runs on `historyContext`'s queue. Reads each store's history after its token, minus
    /// our own transactions, and returns the changes plus the advanced tokens.
    nonisolated private static func fetchHistory(
        in context: NSManagedObjectContext,
        stores: [NSPersistentStore],
        after tokens: [String: NSPersistentHistoryToken]
    ) -> (HistoryChanges, [String: NSPersistentHistoryToken]) {
        var changes = HistoryChanges()
        var newTokens = tokens
        for store in stores {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: tokens[store.identifier])
            if let transactionRequest = NSPersistentHistoryTransaction.fetchRequest {
                transactionRequest.predicate = NSPredicate(
                    format: "author == nil OR author != %@", appTransactionAuthor)
                request.fetchRequest = transactionRequest
            }
            request.affectedStores = [store]
            guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction],
                  let last = transactions.last else { continue }
            for transaction in transactions {
                for change in transaction.changes ?? [] {
                    changes.add(change)
                }
            }
            newTokens[store.identifier] = last.token
        }
        return (changes, newTokens)
    }

    // MARK: - Export

    /// Waits until CloudKit reports an export that started at or after `date` and has finished, or until `timeout`.
    /// (An export already in flight when the save happened may not include the new record.)
    /// A Siri mark runs in a short background launch; this gives the new sighting a chance
    /// to upload before iOS suspends the app (spec, "Sync after a voice mark").
    func awaitExport(after date: Date, timeout: Duration) async {
        let center = NotificationCenter.default
        var observer: NSObjectProtocol?
        let exported = AsyncStream<Void> { continuation in
            observer = center.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: persistentContainer,
                queue: .main
            ) { note in
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event,
                      event.type == .export,
                      event.startDate >= date, event.endDate != nil else { return }
                continuation.yield()
            }
        }
        defer { if let observer { center.removeObserver(observer) } }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { for await _ in exported { return } }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Sharing

    /// Shares the trip with this ID. `TripShareItem` calls this from the share sheet, which
    /// can't carry the managed object itself.
    func shareTrip(withID objectID: NSManagedObjectID) async throws -> CKShare {
        guard let trip = try viewContext.existingObject(with: objectID) as? Trip else {
            throw NSError(domain: "PersistenceController", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "This trip no longer exists."])
        }
        return try await shareTrip(trip)
    }

    /// Share a trip. Returns the trip's existing share, or creates one.
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
            // Core Data calls this off the main thread. `@Sendable` makes the compiler hold it
            // to that; without it, main-actor state touched here would compile and race (#47).
            persistentContainer.persistUpdatedShare(share, in: store) { @Sendable _, error in
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
            // Shared store not loaded yet. Hold the invitation and tell the user (gently) to retry.
            // This is recoverable — reopening the share link re-runs acceptance once the store is up —
            // and avoids both the old user-blaming "restart the app" error and a silent no-op drop.
            // Note: the end-of-init drain is belt-and-suspenders; the realistic recovery is the retry.
            pendingShareMetadata.append(metadata)
            shareAcceptanceError = "Still preparing your data — please open the trip link again in a moment."
            logger.info("Shared store not ready; queued share invitation and prompted the user to retry.")
            return
        }
        persistentContainer.acceptShareInvitations(
            from: [metadata],
            into: store
        ) { @Sendable [weak self] _, error in   // runs off the main thread; see shareTrip
            if let error {
                let message = error.localizedDescription
                Task { @MainActor in
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

    /// Leave a shared trip you joined as a participant. Removes ONLY your own CKShare participant
    /// (never if you are the owner), then lets NSPersistentCloudKitContainer purge the local mirror.
    /// Runs on a background context: persistUpdatedShare can block >10s and would trip the iOS
    /// watchdog (0x8BADF00D) on the main thread.
    func leaveSharedTrip(_ trip: Trip) async throws {
        let objectID = trip.objectID
        guard let storeID = privatePersistentStore?.identifier else {
            throw NSError(domain: "PersistenceController", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Private store not loaded."])
        }
        let container = persistentContainer
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let bg = container.newBackgroundContext()
            bg.perform {
                guard (try? bg.existingObject(with: objectID)) as? Trip != nil else {
                    continuation.resume(); return                // already gone
                }
                guard let share = (try? container.fetchShares(matching: [objectID]))?[objectID] else {
                    continuation.resume(); return                // not shared — nothing to leave
                }
                guard let me = share.currentUserParticipant, me.role != .owner else {
                    continuation.resume(); return                // owner / not a participant — never leave
                }
                guard let store = Self.store(withID: storeID, in: container) else {
                    continuation.resume(throwing: NSError(
                        domain: "PersistenceController", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Private store not loaded."]))
                    return
                }
                share.removeParticipant(me)
                container.persistUpdatedShare(share, in: store) { _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
        }
    }

    /// Takes a participant off the owner's CKShare for a trip, so they lose access (#30). The
    /// person is matched by CloudKit user record name, the ID a `TripParticipant` stores.
    /// Does nothing if they aren't on the share, e.g. a row saved with an offline stand-in ID.
    /// Never removes the owner. Runs on a background context, like `leaveSharedTrip`.
    func revokeAccess(to trip: Trip, forUserID userID: String) async throws {
        let objectID = trip.objectID
        guard let storeID = privatePersistentStore?.identifier else {
            throw NSError(domain: "PersistenceController", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Private store not loaded."])
        }
        let container = persistentContainer
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let bg = container.newBackgroundContext()
            bg.perform {
                guard let share = (try? container.fetchShares(matching: [objectID]))?[objectID] else {
                    continuation.resume(); return                // not shared: nothing to revoke
                }
                guard let participant = share.participants.first(where: {
                    $0.role != .owner && $0.userIdentity.userRecordID?.recordName == userID
                }) else {
                    logger.info("Revoke: no share participant matches this user ID; only the row is removed.")
                    continuation.resume(); return
                }
                guard let store = Self.store(withID: storeID, in: container) else {
                    continuation.resume(throwing: NSError(
                        domain: "PersistenceController", code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Private store not loaded."]))
                    return
                }
                share.removeParticipant(participant)
                container.persistUpdatedShare(share, in: store) { _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
        }
    }

    /// The loaded store with this identifier. Background closures capture the identifier, a
    /// `String`, and look the store up on their own queue: `NSPersistentStore` isn't Sendable (#47).
    nonisolated private static func store(withID id: String, in container: NSPersistentContainer) -> NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first { $0.identifier == id }
    }

    /// Check if the current user owns this trip (i.e., it lives in the private store).
    func isOwner(of trip: Trip) -> Bool {
        guard let store = privatePersistentStore else { return true }
        // A saved object's ID already names its store, so there's no need to fetch. The trip
        // list asks this for every card on every render (#38). Only an unsaved trip
        // falls back to the fetch.
        if !trip.objectID.isTemporaryID, let tripStore = trip.objectID.persistentStore {
            return tripStore === store
        }
        return store.contains(managedObject: trip)
    }

    /// Check if the user can edit a record.
    func canEdit(_ object: NSManagedObject) -> Bool {
        persistentContainer.canUpdateRecord(forManagedObjectWith: object.objectID)
    }
}
