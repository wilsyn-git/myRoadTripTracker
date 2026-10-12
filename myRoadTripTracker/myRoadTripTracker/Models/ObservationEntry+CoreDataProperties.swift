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

extension ObservationEntry: Identifiable {
    /// Whether the note has a photo. Checks the small inline thumbnail first. `imageData`
    /// uses external storage and is about 1024 px, so touching it can read the whole file
    /// just to answer yes or no (#39). Only older notes with no thumbnail fall through to it.
    var hasPhoto: Bool {
        thumbnailData != nil || imageData != nil
    }
}
