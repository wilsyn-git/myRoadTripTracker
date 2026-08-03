import CoreData

@objc(Trip)
public class Trip: NSManagedObject {
    /// `name` deliberately has no default value. With one, this initializer's signature collapses to
    /// `init(context:)`, which collides with `NSManagedObject.init(context:)` — and Swift's overload
    /// resolution silently prefers the superclass version, leaving `createdDate` and `tripID` nil.
    convenience init(context: NSManagedObjectContext, name: String, createdDate: Date = .now, tripID: UUID = UUID()) {
        let entity = NSEntityDescription.entity(forEntityName: "Trip", in: context)!
        self.init(entity: entity, insertInto: context)
        self.tripID = tripID
        self.name = name
        self.createdDate = createdDate
        self.isClosed = false
    }
}
