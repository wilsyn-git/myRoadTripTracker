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

    /// Find the CloudKit record for a trip by querying the synced CD_Trip records.
    private func fetchCKRecord(for trip: Trip) async throws -> CKRecord {
        // First, try fetching ALL CD_Trip records to see what's synced
        let allPredicate = NSPredicate(value: true)
        let allQuery = CKQuery(recordType: "CD_Trip", predicate: allPredicate)

        let (allResults, _) = try await privateDB.records(
            matching: allQuery,
            inZoneWith: zoneID
        )

        print("[PersistenceController] Found \(allResults.count) CD_Trip records in CloudKit")
        for (recordID, result) in allResults {
            if let record = try? result.get() {
                let name = record["CD_name"] as? String ?? "?"
                let tripID = record["CD_tripID"] as? String ?? "no tripID"
                print("[PersistenceController]   - \(name) (CD_tripID=\(tripID), recordName=\(recordID.recordName))")
            }
        }

        // Try to match by tripID first
        let targetID = trip.tripID.uuidString
        for (_, result) in allResults {
            if let record = try? result.get(),
               let recordTripID = record["CD_tripID"] as? String,
               recordTripID == targetID {
                print("[PersistenceController] Matched by tripID")
                return record
            }
        }

        // Fallback: match by name + creation date if tripID hasn't synced yet
        for (_, result) in allResults {
            if let record = try? result.get(),
               let recordName = record["CD_name"] as? String,
               recordName == trip.name {
                print("[PersistenceController] Matched by name fallback")
                return record
            }
        }

        throw SharingError.tripNotFound
    }

    /// Create a CKShare for a trip and return the share URL.
    func shareTrip(_ trip: Trip) async throws -> URL {
        let record = try await fetchCKRecord(for: trip)

        // Check if a share already exists for this record
        if let existingShareRef = record.share {
            let existingShare = try await privateDB.record(for: existingShareRef.recordID)
            if let url = (existingShare as? CKShare)?.url ?? URL(string: existingShare.value(forKey: "url") as? String ?? "") {
                return url
            }
        }

        // Create a new share
        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = trip.name
        share.publicPermission = .none

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
