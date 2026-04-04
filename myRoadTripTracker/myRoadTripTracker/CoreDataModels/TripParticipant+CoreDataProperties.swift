import Foundation
import CoreData

extension TripParticipant {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TripParticipant> {
        return NSFetchRequest<TripParticipant>(entityName: "TripParticipant")
    }

    @NSManaged public var displayName: String
    @NSManaged public var cloudKitUserID: String
    @NSManaged public var joinedDate: Date?
    @NSManaged public var trip: Trip?
}

extension TripParticipant: Identifiable {}
