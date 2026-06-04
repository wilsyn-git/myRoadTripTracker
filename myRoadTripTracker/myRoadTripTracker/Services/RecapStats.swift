import Foundation

/// One participant's plate count, for the recap leaderboard.
struct SpotterTally: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

/// All numbers the recap card needs, computed deterministically from a Trip.
/// Performs no Core Data writes.
struct RecapStats {
    let usSeenCount: Int
    let usTotalCount: Int
    let caSeenCount: Int
    let caTotalCount: Int
    let totalSightings: Int
    let dayCount: Int                 // inclusive days from first to last sighting; 0 if none
    let spotterTallies: [SpotterTally] // sorted by count desc, then name
    let rareCatches: [String]          // location NAMES of rare regions caught
    let observationCount: Int
    let observationsWithPhoto: Int

    /// Region codes considered "rare" (remote / low-population).
    static let rareCodes: Set<String> = ["AK", "HI", "NL", "PE", "NT", "NU", "YT"]

    var mvp: SpotterTally? { spotterTallies.first }

    /// True when there is genuinely nothing to recap.
    var isEmpty: Bool { totalSightings == 0 && observationCount == 0 }

    init(trip: Trip) {
        let sightings = trip.plateSightingsArray
        let observations = trip.observationEntriesArray

        let usCodes = Set(Location.usStates.map(\.code))
        let caCodes = Set(Location.canadaLocations.map(\.code))

        usTotalCount = usCodes.count
        caTotalCount = caCodes.count
        usSeenCount = sightings.filter { usCodes.contains($0.locationCode) }.count
        caSeenCount = sightings.filter { caCodes.contains($0.locationCode) }.count
        totalSightings = sightings.count

        // Day span (inclusive). plateSightingsArray is sorted ascending by seenDate.
        let dates = sightings.compactMap(\.seenDate)
        if let first = dates.first, let last = dates.last {
            let cal = Calendar.current
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: first), to: cal.startOfDay(for: last)).day ?? 0
            dayCount = days + 1
        } else {
            dayCount = 0
        }

        // Per-spotter tallies.
        var counts: [String: Int] = [:]
        for s in sightings {
            let name = s.spottedByName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            counts[name, default: 0] += 1
        }
        spotterTallies = counts
            .map { SpotterTally(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }

        // Rare catches (unique region names, ordered by the canonical list).
        let seenRareCodes = Set(sightings.map(\.locationCode)).intersection(Self.rareCodes)
        rareCatches = Location.allLocations
            .filter { seenRareCodes.contains($0.code) }
            .map(\.name)

        observationCount = observations.count
        observationsWithPhoto = observations.filter { $0.imageData != nil || $0.thumbnailData != nil }.count
    }

    /// Deterministic fallback blurb used when the AI model is unavailable.
    func templateNarrative(tripName: String) -> String {
        var parts: [String] = []
        let regions = usSeenCount + caSeenCount
        if dayCount > 0 {
            parts.append("\(regions) plate\(regions == 1 ? "" : "s") spotted over \(dayCount) day\(dayCount == 1 ? "" : "s").")
        } else if regions > 0 {
            parts.append("\(regions) plate\(regions == 1 ? "" : "s") spotted.")
        }
        if let mvp {
            parts.append("\(mvp.name) led the way with \(mvp.count).")
        }
        if !rareCatches.isEmpty {
            parts.append("Rare finds: \(rareCatches.joined(separator: ", ")).")
        }
        if parts.isEmpty {
            return "Your \(tripName) recap."
        }
        return parts.joined(separator: " ")
    }

    /// Compact description handed to the language model as prompt input.
    func promptDescription(tripName: String) -> String {
        var lines: [String] = []
        lines.append("Trip name: \(tripName)")
        lines.append("US states spotted: \(usSeenCount) of \(usTotalCount)")
        lines.append("Canadian provinces/territories spotted: \(caSeenCount) of \(caTotalCount)")
        lines.append("Total plates: \(totalSightings)")
        if dayCount > 0 { lines.append("Trip length: \(dayCount) days") }
        if let mvp { lines.append("Top spotter: \(mvp.name) with \(mvp.count) plates") }
        if !rareCatches.isEmpty { lines.append("Rare catches: \(rareCatches.joined(separator: ", "))") }
        lines.append("Observations recorded: \(observationCount) (\(observationsWithPhoto) with photos)")
        return lines.joined(separator: "\n")
    }
}
