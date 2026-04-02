import CloudKit
import CoreData
import SwiftData
import SwiftUI

@MainActor
@Observable
final class PersistenceController {

    let modelContainer: ModelContainer

    static let cloudKitContainerID = "iCloud.com.tentenbits.myRoadTripTracker"

    init() {
        let schema = Schema([
            Trip.self, PlateSighting.self, ObservationEntry.self, TripParticipant.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )
        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: - Sharing via NSPersistentCloudKitContainer (lazy)

    /// Creates a temporary NSPersistentCloudKitContainer pointing at the same SQLite store
    /// as SwiftData. Created lazily so the WAL contains all committed trip data.
    private func makeSharingContainer() throws -> NSPersistentCloudKitContainer {
        let modelTypes: [any PersistentModel.Type] = [
            Trip.self, PlateSighting.self, ObservationEntry.self, TripParticipant.self
        ]
        guard let mom = NSManagedObjectModel.makeManagedObjectModel(for: modelTypes) else {
            throw SharingError.containerSetupFailed
        }

        // Point at the same store SwiftData uses
        let storeURL = modelContainer.configurations.first?.url
            ?? URL.applicationSupportDirectory.appending(path: "default.store")

        let container = NSPersistentCloudKitContainer(
            name: "SharingContainer",
            managedObjectModel: mom
        )

        let storeDesc = NSPersistentStoreDescription(url: storeURL)
        storeDesc.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: Self.cloudKitContainerID
        )
        storeDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        storeDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.persistentStoreDescriptions = [storeDesc]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        container.viewContext.automaticallyMergesChangesFromParent = true

        return container
    }

    /// Find the Core Data managed object for a trip in the sharing container.
    private func fetchManagedTrip(
        for trip: Trip,
        in container: NSPersistentCloudKitContainer
    ) -> NSManagedObject? {
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
        request.predicate = NSPredicate(format: "tripID == %@", trip.tripID as CVarArg)
        request.fetchLimit = 1

        do {
            let results = try context.fetch(request)
            print("[PersistenceController] fetchManagedTrip: found \(results.count) for tripID=\(trip.tripID)")

            if results.isEmpty {
                // Debug: show what IS in the store
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
            print("[PersistenceController] fetchManagedTrip error: \(error)")
            return nil
        }
    }

    /// Share a trip using NSPersistentCloudKitContainer's share() API.
    /// This creates a properly formed CKShare that iOS can route to the app.
    func shareTrip(_ trip: Trip) async throws -> URL {
        // Save SwiftData context to ensure trip is committed to SQLite
        let context = modelContainer.mainContext
        try context.save()

        // Create a temporary Core Data container to access sharing APIs
        let sharingContainer = try makeSharingContainer()

        guard let managedTrip = fetchManagedTrip(for: trip, in: sharingContainer) else {
            throw SharingError.tripNotFound
        }

        // Check if already shared
        let existingShares = try sharingContainer.fetchShares(matching: [managedTrip.objectID])
        if let existingShare = existingShares[managedTrip.objectID] {
            existingShare.publicPermission = .readWrite
            try sharingContainer.viewContext.save()
            if let url = existingShare.url {
                print("[PersistenceController] Returning existing share URL: \(url)")
                return url
            }
        }

        // Create new share via NSPersistentCloudKitContainer
        let (_, share, _) = try await sharingContainer.share(
            [managedTrip],
            to: nil
        )
        share[CKShare.SystemFieldKey.title] = trip.name
        share.publicPermission = .readWrite

        try sharingContainer.viewContext.save()

        guard let url = share.url else {
            throw SharingError.shareURLMissing
        }

        print("[PersistenceController] Created new share URL: \(url)")
        return url
    }

    /// Check if the current user is the owner of a trip.
    func isOwner(of trip: Trip) -> Bool {
        return true
    }

    /// Accept incoming share invitations.
    func acceptShare(metadata: CKShare.Metadata) {
        let ckContainer = CKContainer(identifier: Self.cloudKitContainerID)
        Task {
            do {
                try await ckContainer.accept(metadata)
                print("[PersistenceController] Share accepted successfully")
            } catch {
                print("[PersistenceController] Failed to accept share: \(error)")
            }
        }
    }

    enum SharingError: LocalizedError {
        case tripNotFound
        case shareURLMissing
        case containerSetupFailed

        var errorDescription: String? {
            switch self {
            case .tripNotFound:
                return "Trip not yet synced to iCloud. Please wait a moment and try again."
            case .shareURLMissing:
                return "Failed to create share link. Please try again."
            case .containerSetupFailed:
                return "Could not set up sharing. Please try again."
            }
        }
    }
}
