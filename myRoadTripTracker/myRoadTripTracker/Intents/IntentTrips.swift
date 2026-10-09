import AppIntents
import CoreData
import CoreLocation

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

    enum MarkOutcome {
        /// `number` is how many distinct plates the trip now has.
        case added(number: Int)
        case alreadySeen(TripSnapshot.Sighting)
    }

    /// The name a tap would credit: your display name on this trip, else the
    /// default display name, else "Me". Never creates a `TripParticipant`.
    static func speakerName(for trip: Trip, userID: String) -> String {
        if let participant = trip.participantsArray.first(where: { $0.cloudKitUserID == userID }),
           let name = IntentAnswers.cleanName(participant.displayName) {
            return name
        }
        return IntentAnswers.cleanName(UserDefaults.standard.string(forKey: "defaultDisplayName")) ?? "Me"
    }

    /// Adds `region` to `trip` the way `PlateSightingsGrid.markAsSeen` does.
    static func markPlate(_ region: PlateRegion, on trip: Trip) async throws -> MarkOutcome {
        guard !trip.isClosed else { throw IntentFailure.tripClosed(trip.name) }
        guard PersistenceController.shared.canEdit(trip) else { throw IntentFailure.cannotEdit(trip.name) }
        let location = region.location
        if let existing = snapshot(of: trip).sighting(of: location.code) { return .alreadySeen(existing) }

        // The user-ID lookup runs while we wait on GPS.
        let userIDLookup = Task { await CloudKitUserHelper.currentUserID() }
        let locator = LocationManager()
        let fix = await locator.requestFixIfAuthorized(timeout: .seconds(6))
        let userID = await userIDLookup.value
        let name = speakerName(for: trip, userID: userID)

        // The trip may have been deleted, closed or made read-only while we waited.
        guard !trip.isDeleted, trip.managedObjectContext != nil else { throw IntentFailure.tripNotFound }
        guard !trip.isClosed else { throw IntentFailure.tripClosed(trip.name) }
        guard PersistenceController.shared.canEdit(trip) else { throw IntentFailure.cannotEdit(trip.name) }

        // A tap or a sync may have added it while we waited.
        if let existing = snapshot(of: trip).sighting(of: location.code) { return .alreadySeen(existing) }

        let sighting = PlateSighting(
            context: context,
            locationCode: location.code,
            locationName: location.name,
            latitude: fix?.coordinate.latitude ?? 0.0,
            longitude: fix?.coordinate.longitude ?? 0.0,
            spottedByName: name
        )
        sighting.trip = trip
        let savedAt = Date.now
        do {
            try context.trySave(contextInfo: "intentMarkPlate")
        } catch {
            context.delete(sighting)
            throw IntentFailure.storeUnavailable
        }
        if fix == nil, locator.isAuthorized {
            // iOS gave no fix to the background launch: pin it next time the app is open.
            PinBackfill.remember(sighting)
        }
        await PersistenceController.shared.awaitExport(after: savedAt, timeout: .seconds(4))
        return .added(number: snapshot(of: trip).seenCodes.count)
    }
}
