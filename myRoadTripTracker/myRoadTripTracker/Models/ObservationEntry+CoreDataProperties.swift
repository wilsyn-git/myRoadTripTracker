import Foundation
import CoreData

extension ObservationEntry {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ObservationEntry> {
        return NSFetchRequest<ObservationEntry>(entityName: "ObservationEntry")
    }

    @NSManaged public var category: String
    @NSManaged public var authorName: String
    @NSManaged public var text: String
    @NSManaged public var createdDate: Date?
    @NSManaged public var imageData: Data?
    @NSManaged public var thumbnailData: Data?
    @NSManaged public var trip: Trip?
}

extension ObservationEntry: Identifiable {}
