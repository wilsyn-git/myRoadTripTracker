import SwiftUI

/// The trip screen's Notes tab. Opening or leaving it marks the trip's notes as read,
/// which clears the new-notes dot on its trip card.
struct NotesTabView: View {
    @ObservedObject var trip: Trip
    let currentUserName: String

    var body: some View {
        List {
            ObservationsSection(trip: trip, currentUserName: currentUserName)
        }
        .onAppear { markObservationsViewed() }
        .onDisappear { markObservationsViewed() }
    }

    private func markObservationsViewed() {
        guard let tripID = trip.tripID?.uuidString else { return }
        UserDefaults.standard.set(Date.now, forKey: "lastViewedObservations_\(tripID)")
    }
}
