import CloudKit
import CoreData
import CoreTransferable

/// What `ShareLink` shares for a trip: its CloudKit share. The share sheet opens at once, and
/// a new share is created only after the user picks where to send it (#44).
nonisolated struct TripShareItem: Transferable {
    /// The trip's ID rather than the trip: a managed object can't cross into the sheet's
    /// sendable closures.
    let tripID: NSManagedObjectID
    /// The trip's share, when it already had one as the screen opened.
    let existingShare: CKShare?

    /// Anyone with the link can join and edit. This keeps the sheet's sharing options in
    /// line with the `publicPermission` that `PersistenceController.shareTrip` sets.
    private static var sharingOptions: CKAllowedSharingOptions {
        CKAllowedSharingOptions(
            allowedParticipantPermissionOptions: .readWrite,
            allowedParticipantAccessOptions: .anyoneWithLink
        )
    }

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { item in
            let container = CKContainer(identifier: PersistenceController.cloudKitContainerID)
            if let share = item.existingShare {
                return .existing(share, container: container, allowedSharingOptions: sharingOptions)
            }
            // `shareTrip` returns the trip's share if one was made since the screen opened.
            return .prepareShare(container: container, allowedSharingOptions: sharingOptions) {
                try await PersistenceController.shared.shareTrip(withID: item.tripID)
            }
        }
    }
}
