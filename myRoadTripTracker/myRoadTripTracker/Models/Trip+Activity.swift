import CoreData

/// When a trip was active. Shared by the trip list and Siri so they agree on which trip is
/// current (#65). Nonisolated like the managed object itself (#47).
nonisolated extension Trip {
    /// The latest sighting, else when the trip was created.
    var lastActivity: Date {
        sightingDates.max() ?? createdDate ?? .distantPast
    }

    /// The first and last sighting; nil before the first plate.
    var activitySpan: ClosedRange<Date>? {
        let dates = sightingDates
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return first...last
    }

    private var sightingDates: [Date] {
        ((plateSightings as? Set<PlateSighting>) ?? []).compactMap(\.seenDate)
    }

    /// Trips paired with their last activity, most recent first, each computed once. Equal
    /// activity goes to the trip created later, then to the higher trip ID, so the order
    /// never depends on fetch order (#14).
    static func byRecentActivity(_ trips: some Sequence<Trip>) -> [(trip: Trip, lastActivity: Date)] {
        trips.map { (trip: $0, lastActivity: $0.lastActivity) }.sorted { a, b in
            if a.lastActivity != b.lastActivity { return a.lastActivity > b.lastActivity }
            let aCreated = a.trip.createdDate ?? .distantPast
            let bCreated = b.trip.createdDate ?? .distantPast
            if aCreated != bCreated { return aCreated > bCreated }
            return (a.trip.tripID?.uuidString ?? "") > (b.trip.tripID?.uuidString ?? "")
        }
    }
}
