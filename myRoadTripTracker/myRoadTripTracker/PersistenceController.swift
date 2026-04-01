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
    /// Uses recordZoneChanges instead of CKQuery to avoid needing queryable field indexes.
    private func fetchCKRecord(for trip: Trip) async throws -> CKRecord {
        // Fetch all records from the CoreData CloudKit zone
        let changes = try await privateDB.recordZoneChanges(
            inZoneWith: zoneID,
            since: nil
        )

        // Filter to CD_Trip records only
        let tripRecords = changes.modificationResultsByID.compactMap { (_, result) -> CKRecord? in
            guard let record = try? result.get().record,
                  record.recordType == "CD_Trip" else { return nil }
            return record
        }

        print("[PersistenceController] Found \(tripRecords.count) CD_Trip records in CloudKit")
        for record in tripRecords {
            let name = record["CD_name"] as? String ?? "?"
            let tripID = record["CD_tripID"] as? String ?? "no tripID"
            print("[PersistenceController]   - \(name) (CD_tripID=\(tripID), recordName=\(record.recordID.recordName))")
        }

        // Match strictly by tripID
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
            let existingRecord = try await privateDB.record(for: existingShareRef.recordID)
            if let existingShare = existingRecord as? CKShare {
                // Ensure permission is up to date
                if existingShare.publicPermission != .readWrite {
                    existingShare.publicPermission = .readWrite
                    let updateOp = CKModifyRecordsOperation(recordsToSave: [existingShare])
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        updateOp.modifyRecordsResultBlock = { result in
                            switch result {
                            case .success: continuation.resume()
                            case .failure(let error): continuation.resume(throwing: error)
                            }
                        }
                        self.privateDB.add(updateOp)
                    }
                    print("[PersistenceController] Updated existing share permission to .readWrite")
                }
                if let url = existingShare.url {
                    return url
                }
            }
        }

        // Create a new share
        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = trip.name
        share.publicPermission = .readWrite

        // Save both the record and the share
        let modifyOp = CKModifyRecordsOperation(recordsToSave: [record, share])

        return try await withCheckedThrowingContinuation { continuation in
            modifyOp.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let url = share.url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: SharingError.shareURLMissing)
                    }
                case .failure(let error):
                    print("[PersistenceController] shareTrip error: \(error)")
                    continuation.resume(throwing: error)
                }
            }
            self.privateDB.add(modifyOp)
        }
    }

    /// Check if the current user is the owner of a trip.
    /// For now, assumes all local trips are owned by the current user.
    func isOwner(of trip: Trip) -> Bool {
        // Without Core Data's share management, we check ownership simply:
        // trips in the user's private database are owned by them
        return true
    }

    /// Accept incoming share invitations.
    func acceptShare(metadata: CKShare.Metadata) {
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
