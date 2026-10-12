import SwiftUI

/// The small icons beside a trip's name: shared, unread notes, a new recap (#65). Hidden
/// from VoiceOver; `TripListLabel` reads the same facts as part of the trip's label.
struct TripBadgeIcons: View {
    @ObservedObject var trip: Trip
    let isShared: Bool
    /// The sparkle is gold on the green hero card and orange on a plain row, where gold
    /// would barely show against white.
    var onPanel = false

    var body: some View {
        HStack(spacing: 6) {
            if isShared {
                Image(systemName: "person.2.fill")
            }
            if trip.unseenNoteCount > 0 {
                Image(systemName: "text.bubble.fill")
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(.orange).frame(width: 7, height: 7).offset(x: 3, y: -3)
                    }
            }
            if trip.hasUnseenRecap {
                Image(systemName: "sparkles")
                    .foregroundStyle(onPanel ? Theme.gold : .orange)
            }
        }
        .font(.subheadline)
        .imageScale(.small)
        .accessibilityHidden(true)
    }
}
