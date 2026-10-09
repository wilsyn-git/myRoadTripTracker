import AppIntents
import SwiftUI

/// "We saw Maine in TripSpotter." The only intent that writes. Runs locked
/// (spec, "Decisions"): plate names are low-stakes.
struct MarkPlateIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark a Plate"
    static let description = IntentDescription("Ticks off a state or province on your current trip.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Plate", requestValueDialog: "Which plate did you see?")
    var region: PlateRegion

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let target = try IntentTrips.resolve(trip)
        let location = region.location
        let outcome = try await IntentTrips.markPlate(region, on: target)
        let line: String
        let number: Int?
        switch outcome {
        case .added(let n):
            line = IntentAnswers.marked(location, number: n, tripName: target.name)
            number = n
        case .alreadySeen(let sighting):
            line = IntentAnswers.alreadySeen(location, sighting: sighting)
            number = nil
        }
        return .result(dialog: IntentDialog(stringLiteral: line),
                       view: MarkCard(location: location, number: number, trip: IntentTrips.snapshot(of: target)))
    }
}
