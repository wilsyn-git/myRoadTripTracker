import AppIntents
import CoreData

/// What Siri says when an intent can't do what was asked (spec, "Edge cases").
nonisolated enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case storeUnavailable
    case noTrips
    case noOpenTrip
    case tripNotFound
    case tripClosed(String)
    case cannotEdit(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .storeUnavailable: "I couldn't open your trips just now."
        case .noTrips: "You don't have any trips yet. Start one in TripSpotter."
        case .noOpenTrip: "You don't have an open trip. Start one in TripSpotter."
        case .tripNotFound: "I couldn't find that trip."
        case .tripClosed(let name): "\(name) is closed."
        case .cannotEdit(let name): "You can't add to \(name)."
        }
    }
}

/// The intents' only door into Core Data. Works from a background launch:
/// `PersistenceController.shared` loads its stores synchronously in `init`,
/// and nothing here depends on a view existing.
@MainActor
enum IntentTrips {

    static var context: NSManagedObjectContext { PersistenceController.shared.viewContext }

    /// Every trip, open first, newest first (the trip list's order).
    static func allTrips() throws -> [Trip] {
        guard PersistenceController.shared.setupError == nil else { throw IntentFailure.storeUnavailable }
        let request = Trip.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Trip.isClosed, ascending: true),
            NSSortDescriptor(keyPath: \Trip.createdDate, ascending: false),
        ]
        do {
            return try context.fetch(request)
        } catch {
            throw IntentFailure.storeUnavailable
        }
    }

    /// The trip a request means: the one named, else the current trip.
    /// Never reads `tripID` when no trip is named, so a joined trip with a nil
    /// `tripID` can still be the current trip.
    static func resolve(_ entity: TripEntity?) throws -> Trip {
        let trips = try allTrips()
        if let entity {
            guard let trip = trips.first(where: { $0.tripID?.uuidString == entity.id }) else {
                throw IntentFailure.tripNotFound
            }
            return trip
        }
        guard !trips.isEmpty else { throw IntentFailure.noTrips }
        guard let current = currentTrip(in: trips) else { throw IntentFailure.noOpenTrip }
        return current
    }

    /// Spec, "Decisions": the open trip with the most recent activity — latest
    /// sighting, else creation date.
    static func currentTrip(in trips: [Trip]) -> Trip? {
        trips.filter { !$0.isClosed }.max { lastActivity($0) < lastActivity($1) }
    }

    private static func lastActivity(_ trip: Trip) -> Date {
        let sightings = (trip.plateSightings as? Set<PlateSighting>) ?? []
        return sightings.compactMap(\.seenDate).max() ?? trip.createdDate ?? .distantPast
    }

    static func snapshot(of trip: Trip) -> TripSnapshot {
        TripSnapshot(
            name: trip.name,
            isClosed: trip.isClosed,
            sightings: trip.plateSightingsArray.map {
                TripSnapshot.Sighting(code: $0.locationCode, name: $0.locationName,
                                      spottedBy: $0.spottedByName, seenDate: $0.seenDate)
            }
        )
    }
}
