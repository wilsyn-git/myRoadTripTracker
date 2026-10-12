import CoreData

/// Nonisolated, like every managed object here: it belongs to its context's queue, not to an
/// actor, so code on a background context can use it too (#47).
@objc(TripParticipant)
nonisolated public class TripParticipant: NSManagedObject {
    convenience init(context: NSManagedObjectContext, displayName: String, cloudKitUserID: String, joinedDate: Date = .now) {
        let entity = NSEntityDescription.entity(forEntityName: "TripParticipant", in: context)!
        self.init(entity: entity, insertInto: context)
        self.displayName = displayName
        self.cloudKitUserID = cloudKitUserID
        self.joinedDate = joinedDate
    }
}
