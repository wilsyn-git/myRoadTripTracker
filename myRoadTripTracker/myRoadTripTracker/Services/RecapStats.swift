import Foundation

/// All numbers the recap card needs, computed deterministically from a Trip.
/// Performs no Core Data writes.
struct RecapStats {
    let usSeenCount: Int
    let usTotalCount: Int
    let caSeenCount: Int
    let caTotalCount: Int
    let totalSightings: Int           // distinct plates; a sync duplicate counts once (#77)
    let dayCount: Int                 // inclusive days from first to last sighting; 0 if none
    let rareCatches: [String]          // location NAMES of rare regions caught
    let observationCount: Int
    let observationsWithPhoto: Int

    /// Region codes considered "rare" (remote / low-population).
    static let rareCodes: Set<String> = ["AK", "HI", "NL", "PE", "NT", "NU", "YT"]

    /// True when there is genuinely nothing to recap.
    var isEmpty: Bool { totalSightings == 0 && observationCount == 0 }

    init(trip: Trip) {
        let sightings = trip.plateSightingsArray
        let observations = trip.observationEntriesArray

        let usCodes = Set(Location.usStates.map(\.code))
        let caCodes = Set(Location.canadaLocations.map(\.code))

        usTotalCount = usCodes.count
        caTotalCount = caCodes.count

        // One sighting per plate: a sync duplicate would otherwise count twice, here and in
        // the AI narrative, and disagree with the trip list (#77).
        let firstSightings = trip.firstSightingByCode
        let codes = Set(firstSightings.keys)
        usSeenCount = codes.intersection(usCodes).count
        caSeenCount = codes.intersection(caCodes).count
        totalSightings = codes.count

        // Day span (inclusive). plateSightingsArray is sorted ascending by seenDate.
        let dates = sightings.compactMap(\.seenDate)
        if let first = dates.first, let last = dates.last {
            let cal = Calendar.current
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: first), to: cal.startOfDay(for: last)).day ?? 0
            dayCount = days + 1
        } else {
            dayCount = 0
        }

        // Rare catches (unique region names, ordered by the canonical list).
        let seenRareCodes = codes.intersection(Self.rareCodes)
        rareCatches = Location.allLocations
            .filter { seenRareCodes.contains($0.code) }
            .map(\.name)

        observationCount = observations.count
        observationsWithPhoto = observations.count(where: \.hasPhoto)
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
        if !rareCatches.isEmpty { lines.append("Rare catches: \(rareCatches.joined(separator: ", "))") }
        lines.append("Observations recorded: \(observationCount) (\(observationsWithPhoto) with photos)")
        return lines.joined(separator: "\n")
    }
}
