import CoreData

/// Nonisolated, like every managed object here: it belongs to its context's queue, not to an
/// actor, so code on a background context can use it too (#47).
@objc(ObservationEntry)
nonisolated public class ObservationEntry: NSManagedObject {
    convenience init(context: NSManagedObjectContext, category: String, authorName: String, text: String, imageData: Data? = nil, thumbnailData: Data? = nil, createdDate: Date = .now) {
        let entity = NSEntityDescription.entity(forEntityName: "ObservationEntry", in: context)!
        self.init(entity: entity, insertInto: context)
        self.category = category
        self.authorName = authorName
        self.text = text
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.createdDate = createdDate
    }
}
