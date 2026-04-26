import CoreData
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "myRoadTripTracker", category: "CoreData")

// MARK: - Contextual Save

extension NSManagedObjectContext {
    /// Save with contextual info for debugging. No-op if no changes. Swallows errors (logs them).
    func save(contextInfo: String) {
        do {
            try trySave(contextInfo: contextInfo)
        } catch {
            // Already logged by trySave.
        }
    }

    /// Throwing variant — use when the caller needs to surface the error to the UI.
    func trySave(contextInfo: String) throws {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            let nsError = error as NSError
            logger.error("Failed to save (\(contextInfo)): \(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription) userInfo=\(nsError.userInfo)")
            if let detailed = nsError.userInfo[NSDetailedErrorsKey] as? [NSError] {
                for sub in detailed {
                    logger.error("  detailed (\(contextInfo)): \(sub.domain) code=\(sub.code) \(sub.localizedDescription) userInfo=\(sub.userInfo)")
                }
            }
            throw error
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
