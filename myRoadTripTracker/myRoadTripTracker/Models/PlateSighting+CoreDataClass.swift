import CoreData

@objc(PlateSighting)
public class PlateSighting: NSManagedObject {
    convenience init(context: NSManagedObjectContext, locationCode: String, locationName: String, latitude: Double, longitude: Double, seenDate: Date = .now, spottedByName: String? = nil) {
        let entity = NSEntityDescription.entity(forEntityName: "PlateSighting", in: context)!
        self.init(entity: entity, insertInto: context)
        self.locationCode = locationCode
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.seenDate = seenDate
        self.spottedByName = spottedByName
    }
}
