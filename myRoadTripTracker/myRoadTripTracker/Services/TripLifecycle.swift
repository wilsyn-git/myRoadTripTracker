import CoreData

/// Closing, reopening and deleting a trip, shared by the trip list and the trip screen so
/// every entry point behaves the same (#65). Closing always produces the recap. Callers
/// offer these actions to the trip's owner only.
enum TripLifecycle {
    /// Trips whose recap is being written, so closing from two places can't start a second.
    private static var generatingRecap: Set<NSManagedObjectID> = []

    static func setClosed(_ closed: Bool, for trip: Trip, in context: NSManagedObjectContext) {
        guard trip.isClosed != closed else { return }
        trip.isClosed = closed
        context.save(contextInfo: closed ? "closeTrip" : "reopenTrip")
        if closed {
            Task { await generateRecap(for: trip, in: context) }
        }
    }

    static func delete(_ trip: Trip, in context: NSManagedObjectContext) {
        context.delete(trip)
        context.save(contextInfo: "deleteTrip")
    }

    /// Moved from `TripDetailView`. `recapGeneratedDate` is stamped even when the model is
    /// unavailable (narrative == nil), so the "recap ready" badge appears for everyone;
    /// `TripRecapView` falls back to the template narrative.
    private static func generateRecap(for trip: Trip, in context: NSManagedObjectContext) async {
        guard !trip.isDeleted, trip.managedObjectContext != nil else { return }
        let id = trip.objectID
        guard !generatingRecap.contains(id) else { return }
        let stats = RecapStats(trip: trip)
        guard !stats.isEmpty else { return }
        generatingRecap.insert(id)
        defer { generatingRecap.remove(id) }
        let narrative = await RecapNarrativeGenerator.generate(from: stats, tripName: trip.name)
        // The trip may have been deleted, or reopened, while the model ran. A reopened trip
        // must not get a recap stamp, or every participant sees a false "new recap".
        guard !trip.isDeleted, trip.managedObjectContext != nil, trip.isClosed else { return }
        if let narrative { trip.recapNarrative = narrative }
        trip.recapGeneratedDate = Date()
        context.save(contextInfo: "generateRecap")
    }
}
