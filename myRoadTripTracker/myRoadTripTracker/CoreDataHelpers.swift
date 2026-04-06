import CoreData
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "myRoadTripTracker", category: "CoreData")

// MARK: - Contextual Save

extension NSManagedObjectContext {
    /// Save with contextual info for debugging. No-op if no changes.
    func save(contextInfo: String) {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            logger.error("Failed to save (\(contextInfo)): \(error.localizedDescription)")
        }
    }
}

// MARK: - Store Membership

extension NSPersistentStore {
    /// Check whether a managed object belongs to this store.
    func contains(managedObject: NSManagedObject) -> Bool {
        guard let entityName = managedObject.entity.name,
              let context = managedObject.managedObjectContext else {
            return false
        }
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.predicate = NSPredicate(format: "self == %@", managedObject)
        fetchRequest.affectedStores = [self]
        if let count = try? context.count(for: fetchRequest), count > 0 {
            return true
        }
        return false
    }
}
