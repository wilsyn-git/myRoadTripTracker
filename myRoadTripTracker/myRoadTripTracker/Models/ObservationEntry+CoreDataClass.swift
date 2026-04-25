import CoreData

@objc(ObservationEntry)
public class ObservationEntry: NSManagedObject {
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
