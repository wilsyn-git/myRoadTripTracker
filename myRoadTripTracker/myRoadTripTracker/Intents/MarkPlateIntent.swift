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
        let line = switch outcome {
        case .added(let number): IntentAnswers.marked(location, number: number, tripName: target.name)
        case .alreadySeen(let sighting): IntentAnswers.alreadySeen(location, sighting: sighting)
        }
        return .result(dialog: IntentDialog(stringLiteral: line),
                       view: MarkCard(location: location, trip: IntentTrips.snapshot(of: target)))
    }
}
