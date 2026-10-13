import Foundation

/// What a trip's entry in the trip list shows besides its name: plates by country, notes
/// you haven't read, a recap you haven't opened, and who's on it (#65).
extension Trip {
    private static let usCodes = Set(Location.usStates.map(\.code))
    private static let caCodes = Set(Location.canadaLocations.map(\.code))

    /// Distinct US and Canadian plates seen. Distinct, because sync can leave two sightings
    /// of one plate; `TripSnapshot` counts the same way, so Siri and the list agree.
    var regionCounts: (us: Int, ca: Int) {
        let codes = seenRegionCodes
        return (codes.intersection(Self.usCodes).count, codes.intersection(Self.caCodes).count)
    }

    var noteCount: Int { observationEntries?.count ?? 0 }

    var participantCount: Int { participants?.count ?? 0 }

    /// Notes added since you last opened the Notes tab, which stamps the key.
    var unseenNoteCount: Int {
        let notes = (observationEntries as? Set<ObservationEntry>) ?? []
        guard let tripID = tripID?.uuidString else { return notes.count }
        guard let lastViewed = UserDefaults.standard.object(forKey: "lastViewedObservations_\(tripID)") as? Date else {
            return notes.count
        }
        return notes.filter { ($0.createdDate ?? .distantPast) > lastViewed }.count
    }

    /// A recap generated since you last opened it; `TripRecapView` stamps the key.
    var hasUnseenRecap: Bool {
        guard let generated = recapGeneratedDate else { return false }
        guard let tripID = tripID?.uuidString else { return true }
        guard let lastViewed = UserDefaults.standard.object(forKey: "lastViewedRecap_\(tripID)") as? Date else {
            return true
        }
        return generated > lastViewed
    }
}
