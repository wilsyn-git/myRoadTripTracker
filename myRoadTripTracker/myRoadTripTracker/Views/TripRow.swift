import SwiftUI

/// A trip in the trip list other than the hero: a later open trip or a past trip (#65).
struct TripRow: View {
    @ObservedObject var trip: Trip
    let isShared: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let counts = trip.regionCounts
        // At accessibility sizes the score moves under the name instead of squeezing it.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(trip.name)
                        .font(.headline)
                        .lineLimit(2)
                    TripBadgeIcons(trip: trip, isShared: isShared)
                        .foregroundStyle(.secondary)
                }
                TripActivityLine(trip: trip)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("US \(counts.us) · CA \(counts.ca)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TripListLabel.spoken(trip, isShared: isShared, style: .row))
    }
}
