import AppIntents
import SwiftUI

/// "We saw Maine in TripSpotter." The only intent that writes. Runs locked
/// (spec, "Decisions"): plate names are low-stakes.
struct MarkPlateIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Plate"
    static let description = IntentDescription("Adds a license plate you spotted, from a US state or Canadian province, to your current road trip.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "State or Province", requestValueDialog: "Oh! Which one?")
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
