import AppIntents
import CoreData

/// "Open my trip in TripSpotter." Opens the app, which needs the phone unlocked;
/// iOS asks for that itself.
struct OpenTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Trip"
    static let description = IntentDescription("Opens a road trip in TripSpotter: your current trip, unless you name one.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target = try IntentTrips.resolve(trip)
        IntentRoute.shared.open(target.objectID)
        // Spoken, never a bare "Done.": when Siri can't match a phrase it guesses an
        // intent, and a guess that lands here must not sound like a plate was added.
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.opening(tripName: target.name)))
    }
}
