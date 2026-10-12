import Foundation

/// The trip list's grouping (#65). The hero is the open trip with the latest activity, the
/// same trip Siri treats as current. The other open trips follow it, newest activity first.
/// Closed trips are grouped by the year of their last activity, newest year first.
struct TripListSections {
    struct PastYear: Identifiable {
        let year: Int
        let trips: [Trip]
        var id: Int { year }
    }

    let hero: Trip?
    let otherOpen: [Trip]
    let pastYears: [PastYear]

    var isEmpty: Bool { hero == nil && pastYears.isEmpty }

    /// - Parameter query: Search text. Trips whose name doesn't contain it are left out.
    init(trips: some Sequence<Trip>, matching query: String = "", calendar: Calendar = .current) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = trips.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
        let ordered = Trip.byRecentActivity(matching)

        let open = ordered.filter { !$0.trip.isClosed }.map(\.trip)
        hero = open.first
        otherOpen = Array(open.dropFirst())

        var years: [Int: [Trip]] = [:]
        let thisYear = calendar.component(.year, from: .now)
        for entry in ordered where entry.trip.isClosed {
            // A partially synced trip can arrive with no dates at all; it goes in this
            // year's section rather than under "Year 1".
            let year = entry.lastActivity == .distantPast
                ? thisYear
                : calendar.component(.year, from: entry.lastActivity)
            years[year, default: []].append(entry.trip)
        }
        pastYears = years
            .sorted { $0.key > $1.key }
            .map { PastYear(year: $0.key, trips: $0.value) }
    }
}
