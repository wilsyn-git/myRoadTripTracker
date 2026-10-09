import AppIntents

// The read-only trip questions. Each answers in the background, locked or not
// (spec, "Decisions": locked phone).

struct TripCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Trip Count"
    static let description = IntentDescription("How many states and Canadian plates you've seen on a trip.")

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = try IntentTrips.snapshot(of: IntentTrips.resolve(trip))
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.count(snapshot)))
    }
}

struct HaveWeSeenIntent: AppIntent {
    static let title: LocalizedStringResource = "Have We Seen a Plate"
    static let description = IntentDescription("Whether a state or province is already ticked off, and who spotted it.")

    @Parameter(title: "Plate", requestValueDialog: "Which plate?")
    var region: PlateRegion

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = try IntentTrips.snapshot(of: IntentTrips.resolve(trip))
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.haveWeSeen(region.location, in: snapshot)))
    }
}

struct PlatesLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Plates Left"
    static let description = IntentDescription("The states and provinces you haven't spotted yet.")

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = try IntentTrips.snapshot(of: IntentTrips.resolve(trip))
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.left(snapshot)))
    }
}

struct TopSpotterIntent: AppIntent {
    static let title: LocalizedStringResource = "Top Spotter"
    static let description = IntentDescription("Who has spotted the most plates on a trip.")

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = try IntentTrips.snapshot(of: IntentTrips.resolve(trip))
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.topSpotter(snapshot)))
    }
}
