import CoreData

/// One trip's distinct plate count, for Plate Passport's comparisons (#78).
struct TripPlateTotal: Identifiable {
    let id: NSManagedObjectID
    let name: String
    let plateCount: Int
    let isOpen: Bool
    let lastActivity: Date
}
