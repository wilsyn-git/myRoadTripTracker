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
