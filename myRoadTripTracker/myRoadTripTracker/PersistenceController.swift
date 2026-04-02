import CloudKit
import SwiftData
import SwiftUI

@MainActor
@Observable
final class PersistenceController {

    let modelContainer: ModelContainer

    static let cloudKitContainerID = "iCloud.com.tentenbits.myRoadTripTracker"
    private static let zoneName = "com.apple.coredata.cloudkit.zone"

    private var ckContainer: CKContainer {
        CKContainer(identifier: Self.cloudKitContainerID)
    }

    private var privateDB: CKDatabase {
        ckContainer.privateCloudDatabase
    }

    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

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

    // MARK: - Sharing APIs

    /// Find the CloudKit record for a trip by fetching all records from the zone.
    private func fetchCKRecord(for trip: Trip) async throws -> CKRecord {
        let changes = try await privateDB.recordZoneChanges(
            inZoneWith: zoneID,
            since: nil
        )

        let tripRecords = changes.modificationResultsByID.compactMap { (_, result) -> CKRecord? in
            guard let record = try? result.get().record,
                  record.recordType == "CD_Trip" else { return nil }
            return record
        }

        print("[PersistenceController] Found \(tripRecords.count) CD_Trip records in CloudKit")
        for record in tripRecords {
            let name = record["CD_name"] as? String ?? "?"
            let tripID = record["CD_tripID"] as? String ?? "no tripID"
            print("[PersistenceController]   - \(name) (CD_tripID=\(tripID))")
        }

        let targetID = trip.tripID.uuidString
        if let match = tripRecords.first(where: { ($0["CD_tripID"] as? String) == targetID }) {
            print("[PersistenceController] Matched by tripID")
            return match
        }

        throw SharingError.tripNotFound
    }

    /// Create a CKShare for a trip and return the share URL.
    func shareTrip(_ trip: Trip) async throws -> URL {
        let record = try await fetchCKRecord(for: trip)

        // Check if a share already exists for this record
        if let existingShareRef = record.share {
            do {
                let existingRecord = try await privateDB.record(for: existingShareRef.recordID)
                if let existingShare = existingRecord as? CKShare {
                    if existingShare.publicPermission != .readWrite {
                        existingShare.publicPermission = .readWrite
                        let (savedResults, _) = try await privateDB.modifyRecords(
                            saving: [existingShare], deleting: []
                        )
                        print("[PersistenceController] Updated existing share permission")
                    }
                    if let url = existingShare.url {
                        return url
                    }
                }
            } catch {
                print("[PersistenceController] Error fetching existing share, creating new one: \(error)")
            }
        }

        // Create a new share
        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = trip.name
        share.publicPermission = .readWrite

        // Save both the record and the share together
        let (savedResults, _) = try await privateDB.modifyRecords(
            saving: [record, share], deleting: []
        )

        // Get the saved share to retrieve the URL
        for (recordID, result) in savedResults {
            if let savedRecord = try? result.get(),
               let savedShare = savedRecord as? CKShare,
               let url = savedShare.url {
                print("[PersistenceController] Created share URL: \(url)")
                return url
            }
        }

        guard let url = share.url else {
            throw SharingError.shareURLMissing
        }
        return url
    }

    /// Check if the current user is the owner of a trip.
    func isOwner(of trip: Trip) -> Bool {
        return true
    }

    /// Accept a share and import the shared trip into the local SwiftData store.
    func acceptShareAndImport(metadata: CKShare.Metadata) async {
        do {
            // Accept the share if we're a pending participant
            if metadata.participantRole != .owner && metadata.participantStatus == .pending {
                try await ckContainer.accept(metadata)
                print("[PersistenceController] Share accepted")
            }

            // Fetch the shared trip from the shared database
            guard let rootRecordID = metadata.hierarchicalRootRecordID else {
                print("[PersistenceController] No root record ID in share metadata")
                return
            }

            let sharedDB = ckContainer.sharedCloudDatabase
            let record = try await sharedDB.record(for: rootRecordID)
            print("[PersistenceController] Fetched shared record: \(record.recordType), name=\(record["CD_name"] as? String ?? "?")")

            // Check if we already have this trip locally (by tripID)
            let tripIDString = record["CD_tripID"] as? String ?? ""
            let context = modelContainer.mainContext

            if let existingTripID = UUID(uuidString: tripIDString) {
                let descriptor = FetchDescriptor<Trip>(
                    predicate: #Predicate { $0.tripID == existingTripID }
                )
                let existing = try context.fetch(descriptor)
                if !existing.isEmpty {
                    print("[PersistenceController] Trip already exists locally, skipping import")
                    return
                }
            }

            // Create a local Trip from the CloudKit record
            let tripName = record["CD_name"] as? String ?? "Shared Trip"
            let tripID = UUID(uuidString: tripIDString) ?? UUID()
            let createdDate = record["CD_createdDate"] as? Date ?? Date.now
            let isClosed = record["CD_isClosed"] as? Int64 == 1

            let trip = Trip(name: tripName, createdDate: createdDate, tripID: tripID)
            trip.isClosed = isClosed
            context.insert(trip)
            try context.save()

            print("[PersistenceController] Imported shared trip: \(tripName)")

        } catch {
            print("[PersistenceController] Failed to accept/import share: \(error)")
        }
    }

    enum SharingError: LocalizedError {
        case tripNotFound
        case shareURLMissing

        var errorDescription: String? {
            switch self {
            case .tripNotFound:
                return "Trip not yet synced to iCloud. Please wait a moment and try again."
            case .shareURLMissing:
                return "Failed to create share link. Please try again."
            }
        }
    }
}
