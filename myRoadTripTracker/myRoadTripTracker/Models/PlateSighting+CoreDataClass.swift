import CoreData

/// Nonisolated, like every managed object here: it belongs to its context's queue, not to an
/// actor, so code on a background context can use it too (#47).
@objc(PlateSighting)
nonisolated public class PlateSighting: NSManagedObject {
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
