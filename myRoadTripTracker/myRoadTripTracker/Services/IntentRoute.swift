import CoreData
import Observation

/// The trip a Siri or Spotlight request asked the app to open.
///
/// `OpenTripIntent` posts here and `ContentView` follows, so navigation stays in
/// one place. A request that arrives before `ContentView` exists (cold launch,
/// onboarding) waits until it appears.
@Observable @MainActor
final class IntentRoute {
    static let shared = IntentRoute()

    private(set) var pendingTrip: NSManagedObjectID?

    func open(_ trip: NSManagedObjectID) {
        pendingTrip = trip
    }

    /// The pending trip, cleared as it is handed over.
    func take() -> NSManagedObjectID? {
        defer { pendingTrip = nil }
        return pendingTrip
    }
}
