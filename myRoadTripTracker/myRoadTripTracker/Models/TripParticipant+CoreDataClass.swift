import CoreData

@objc(TripParticipant)
public class TripParticipant: NSManagedObject {
    convenience init(context: NSManagedObjectContext, displayName: String, cloudKitUserID: String, joinedDate: Date = .now) {
        let entity = NSEntityDescription.entity(forEntityName: "TripParticipant", in: context)!
        self.init(entity: entity, insertInto: context)
        self.displayName = displayName
        self.cloudKitUserID = cloudKitUserID
        self.joinedDate = joinedDate
    }
}
