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

    /// The plates seen on this trip, one per region. Sync can leave two sightings of one
    /// plate (two phones marking it at once), so anything that counts plates counts these (#77).
    var seenRegionCodes: Set<String> {
        Set(((plateSightings as? Set<PlateSighting>) ?? []).map(\.locationCode))
    }

    /// Each seen region's sighting, keyed by code, in one unsorted pass (#38). With
    /// duplicates, the earliest dated sighting wins, so it's the one the grid opens and the
    /// recap credits. A partly synced record has no date yet, so it loses to any dated one
    /// instead of passing for the earliest and costing the trip its first-ever credit (#77).
    var firstSightingByCode: [String: PlateSighting] {
        let set = (plateSightings as? Set<PlateSighting>) ?? []
        return Dictionary(set.map { ($0.locationCode, $0) }) { first, second in
            (first.seenDate ?? .distantFuture) <= (second.seenDate ?? .distantFuture) ? first : second
        }
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
