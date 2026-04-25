import Foundation
import CoreData
import CoreLocation

extension PlateSighting {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PlateSighting> {
        return NSFetchRequest<PlateSighting>(entityName: "PlateSighting")
    }

    @NSManaged public var locationCode: String
    @NSManaged public var locationName: String
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var seenDate: Date?
    @NSManaged public var spottedByName: String?
    @NSManaged public var trip: Trip?
}

extension PlateSighting: Identifiable {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var hasValidCoordinate: Bool {
        latitude != 0.0 || longitude != 0.0
    }

    var flagImageName: String {
        locationName.lowercased().replacing(" ", with: "_")
    }
}
