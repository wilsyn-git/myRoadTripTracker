import AppIntents
import SwiftUI

// The read-only trip questions. Each answers in the background, locked or not
// (spec, "Decisions": locked phone).

struct TripCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Trip Count"
    static let description = IntentDescription("Counts the US states and Canadian provinces whose license plates you've spotted on a road trip.")

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let snapshot = try IntentTrips.snapshot(of: IntentTrips.resolve(trip))
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.count(snapshot)),
                       view: CountCard(trip: snapshot))
    }
}

struct HaveWeSeenIntent: AppIntent {
    static let title: LocalizedStringResource = "Have We Seen a Plate"
    static let description = IntentDescription("Checks whether you've already spotted a license plate from a state or province on your road trip, and who spotted it.")

    @Parameter(title: "State or Province", requestValueDialog: "Which one?")
    var region: PlateRegion

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let snapshot = try IntentTrips.snapshot(of: IntentTrips.resolve(trip))
        let location = region.location
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.haveWeSeen(location, in: snapshot)),
                       view: SeenCard(location: location, trip: snapshot))
    }
}

struct PlatesSeenIntent: AppIntent {
    static let title: LocalizedStringResource = "Plates Seen"
    static let description = IntentDescription("Lists the states and provinces whose license plates you've spotted on a road trip.")

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let snapshot = try IntentTrips.snapshot(of: IntentTrips.resolve(trip))
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.seen(snapshot)),
                       view: PlatesSeenCard(trip: snapshot))
    }
}

struct PlatesLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Plates Left"
    static let description = IntentDescription("Lists the states and provinces whose license plates you haven't spotted yet on a road trip.")

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let snapshot = try IntentTrips.snapshot(of: IntentTrips.resolve(trip))
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.left(snapshot)),
                       view: PlatesLeftCard(trip: snapshot))
    }
}

struct TopSpotterIntent: AppIntent {
    static let title: LocalizedStringResource = "Top Spotter"
    static let description = IntentDescription("Tells you who has spotted the most license plates on a road trip.")

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let snapshot = try IntentTrips.snapshot(of: IntentTrips.resolve(trip))
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.topSpotter(snapshot)),
                       view: TopSpotterCard(trip: snapshot))
    }
}
