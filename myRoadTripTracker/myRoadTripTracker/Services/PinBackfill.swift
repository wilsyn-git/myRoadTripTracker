import CoreData
import CoreLocation

/// Gives a map pin to voice-marked plates that Siri saved without one.
///
/// A Siri mark runs in a background launch, where iOS may not hand a "While Using" app a
/// location fix. Such a sighting is saved at `0,0` and remembered here. The next time the
/// app is active, any remembered sighting from the last ten minutes gets the current
/// location: rough at highway speed, but better than no pin. The list lives on this phone
/// only, so only the speaker's own marks are touched. One fix, no prompt, no tracking
/// (privacy invariants, CLAUDE.md).
@MainActor
enum PinBackfill {
    static let pendingKey = "pinBackfill.pending"
    static let window: TimeInterval = 600

    /// Remembers a saved sighting that has no fix.
    static func remember(_ sighting: PlateSighting) {
        guard !sighting.objectID.isTemporaryID else { return }
        var pending = load()
        pending[sighting.objectID.uriRepresentation().absoluteString] = Date.now.timeIntervalSince1970
        UserDefaults.standard.set(pending, forKey: pendingKey)
    }

    /// Fills in pins for remembered sightings from the last ten minutes. Older ones are
    /// dropped; if no fix arrives, recent ones are kept for the next activation.
    static func run(in context: NSManagedObjectContext) async {
        let cutoff = Date.now.addingTimeInterval(-window).timeIntervalSince1970
        let due = load().filter { $0.value >= cutoff }
        store(due)
        guard !due.isEmpty else { return }

        guard let fix = await LocationManager().requestFixIfAuthorized(timeout: .seconds(10), maxCachedAge: 60) else {
            return
        }
        var filled = 0
        for uri in due.keys {
            guard let url = URL(string: uri),
                  let id = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
                  let sighting = try? context.existingObject(with: id) as? PlateSighting,
                  !sighting.isDeleted, !sighting.hasValidCoordinate else { continue }
            sighting.latitude = fix.coordinate.latitude
            sighting.longitude = fix.coordinate.longitude
            filled += 1
        }
        store([:])
        if filled > 0 {
            context.save(contextInfo: "pinBackfill")
        }
    }

    private static func load() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: Double] ?? [:]
    }

    private static func store(_ pending: [String: Double]) {
        if pending.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingKey)
        } else {
            UserDefaults.standard.set(pending, forKey: pendingKey)
        }
    }
}
