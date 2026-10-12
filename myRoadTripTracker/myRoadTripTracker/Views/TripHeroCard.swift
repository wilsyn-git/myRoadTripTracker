import CoreData
import SwiftUI

/// The trip list's lead card: the open trip with the latest activity (#65).
struct TripHeroCard: View {
    @ObservedObject var trip: Trip
    let isShared: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The five newest plates, newest first, one per region.
    private var recentFlags: [PlateSighting] {
        var seen = Set<String>()
        return Array(trip.plateSightingsArray.reversed().filter { seen.insert($0.locationCode).inserted }.prefix(5))
    }

    var body: some View {
        let counts = trip.regionCounts
        let flags = recentFlags
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(trip.name)
                        .font(.title2)
                        .bold()
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                    Spacer(minLength: 0)
                    TripBadgeIcons(trip: trip, isShared: isShared, onPanel: true)
                }
                TripActivityLine(trip: trip, style: .hero)
                    .font(.subheadline)
                    .foregroundStyle(Theme.panelSecondaryText)
            }
            if !flags.isEmpty {
                HStack(spacing: -4) {
                    ForEach(flags, id: \.objectID) { sighting in
                        Image(sighting.flagImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 18)
                            .clipShape(.rect(cornerRadius: 2))
                            .overlay {
                                RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.6), lineWidth: 1)
                            }
                    }
                }
                .accessibilityHidden(true)
            }
            RegionProgressBars(
                usSeen: counts.us,
                caSeen: counts.ca,
                axis: dynamicTypeSize.isAccessibilitySize ? .vertical : .horizontal
            )
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel(), in: .rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TripListLabel.spoken(trip, isShared: isShared, style: .hero))
    }
}
