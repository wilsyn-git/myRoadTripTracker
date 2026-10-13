import CoreData

/// What your trips add up to, across every trip on this phone: your own and the ones shared
/// with you (#78). A plate counts once per trip (`firstSightingByCode`), so a sync duplicate
/// never counts twice (#77). Group-level only: trips are shared ad hoc and `spottedByName` is
/// free text, so there's no person to total across trips.
///
/// Cheap enough to rebuild on every render: at most 64 plates per trip.
struct PlateHistory {
    /// Trips with at least one plate, most plates first; ties go to the more recent trip.
    let trips: [TripPlateTotal]
    /// How many trips saw each plate, by region code.
    let tripCounts: [String: Int]
    /// The trip with each plate's earliest sighting, by region code. A sighting with no date
    /// (a partly synced record) never counts as first.
    let firstTripByCode: [String: NSManagedObjectID]
    /// The earliest dated sighting on any trip.
    let since: Date?

    init(trips: some Sequence<Trip>) {
        var totals: [TripPlateTotal] = []
        var counts: [String: Int] = [:]
        var firsts: [String: (date: Date, trip: NSManagedObjectID)] = [:]
        var earliest: Date?
        for trip in trips where !trip.isDeleted && trip.managedObjectContext != nil {
            let sightings = trip.firstSightingByCode
            guard !sightings.isEmpty else { continue }
            totals.append(TripPlateTotal(
                id: trip.objectID,
                name: trip.name,
                plateCount: sightings.count,
                isOpen: !trip.isClosed,
                lastActivity: trip.lastActivity
            ))
            for (code, sighting) in sightings {
                counts[code, default: 0] += 1
                guard let date = sighting.seenDate else { continue }
                if earliest.map({ date < $0 }) ?? true { earliest = date }
                if firsts[code].map({ date < $0.date }) ?? true {
                    firsts[code] = (date, trip.objectID)
                }
            }
        }
        self.trips = totals.sorted {
            $0.plateCount != $1.plateCount ? $0.plateCount > $1.plateCount : $0.lastActivity > $1.lastActivity
        }
        tripCounts = counts
        firstTripByCode = firsts.mapValues(\.trip)
        since = earliest
    }

    /// Every plate any trip has seen.
    var collected: Set<String> { Set(tripCounts.keys) }

    var usCollected: Int { Location.usStates.count(where: { tripCounts[$0.code] != nil }) }
    var caCollected: Int { Location.canadaLocations.count(where: { tripCounts[$0.code] != nil }) }

    /// Plates no trip has seen, in the app's usual order.
    var neverSeen: [Location] { Location.allLocations.filter { tripCounts[$0.code] == nil } }

    /// Plates exactly one trip saw, in the app's usual order.
    var seenOnce: [Location] { Location.allLocations.filter { tripCounts[$0.code] == 1 } }

    /// Seen plates, on the most trips first, then by name.
    var byTripCount: [PlateCount] {
        Location.allLocations
            .compactMap { location in tripCounts[location.code].map { PlateCount(location: location, trips: $0) } }
            .sorted { $0.trips != $1.trips ? $0.trips > $1.trips : $0.location.name < $1.location.name }
    }

    /// The middle plate count of finished trips, rounded; nil until there are two of them.
    var typicalPlateCount: Int? {
        let counts = trips.filter { !$0.isOpen }.map(\.plateCount).sorted()
        guard counts.count >= 2 else { return nil }
        let mid = counts.count / 2
        if counts.count.isMultiple(of: 2) {
            return Int((Double(counts[mid - 1] + counts[mid]) / 2).rounded())
        }
        return counts[mid]
    }

    /// The trip with the most plates.
    var record: TripPlateTotal? { trips.first }

    /// Enough history to compare trips: two trips with plates.
    var hasComparisons: Bool { trips.count >= 2 }

    /// The trip list shows the Passport row once a finished trip has plates (spec §1).
    var showsPassport: Bool { trips.contains { !$0.isOpen } }

    /// Trips with plates other than `trip`.
    func otherTripCount(than trip: Trip) -> Int {
        trips.count(where: { $0.id != trip.objectID })
    }

    /// Whether `trip` saw this plate before any other trip did.
    func isFirstEver(_ code: String, on trip: Trip) -> Bool {
        firstTripByCode[code] == trip.objectID
    }

    /// Plates `trip` hasn't seen that other trips have, on the most trips first (spec §4).
    func watchFor(on trip: Trip, limit: Int = 8) -> [PlateCount] {
        let seen = trip.seenRegionCodes
        return Array(byTripCount.filter { !seen.contains($0.location.code) }.prefix(limit))
    }
}
