import CoreData

@objc(Trip)
public class Trip: NSManagedObject {
    convenience init(context: NSManagedObjectContext, name: String = "New Trip", createdDate: Date = .now, tripID: UUID = UUID()) {
        let entity = NSEntityDescription.entity(forEntityName: "Trip", in: context)!
        self.init(entity: entity, insertInto: context)
        self.tripID = tripID
        self.name = name
        self.createdDate = createdDate
        self.isClosed = false
    }
}
