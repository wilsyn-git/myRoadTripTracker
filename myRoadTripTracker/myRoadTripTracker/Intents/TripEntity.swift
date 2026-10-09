import AppIntents

/// A trip as Siri names it. Trips without a `tripID` (a joined trip the
/// backfill can't repair) have no entity; they're still reachable as the
/// current trip.
nonisolated struct TripEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Trip"
    static let defaultQuery = TripQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            synonyms: IntentAnswers.tripSynonyms(for: name).map { "\($0)" }
        )
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    @MainActor
    init?(_ trip: Trip) {
        guard let id = trip.tripID?.uuidString else { return nil }
        self.init(id: id, name: trip.name)
    }
}

/// Trips by name. None or several matches make Siri ask "Which trip?".
nonisolated struct TripQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [TripEntity] {
        try IntentTrips.allTrips().compactMap(TripEntity.init).filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [TripEntity] {
        try IntentTrips.allTrips().compactMap(TripEntity.init).filter { IntentAnswers.tripName($0.name, matches: string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TripEntity] {
        try IntentTrips.allTrips().compactMap(TripEntity.init)
    }
}
