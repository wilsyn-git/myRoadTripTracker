import SwiftUI

struct TripRowView: View {
    @ObservedObject var trip: Trip

    private var sightings: [PlateSighting] { trip.plateSightingsArray }
    private static let usCodes = Set(Location.usStates.map(\.code))
    private var seenCount: Int { sightings.filter { Self.usCodes.contains($0.locationCode) }.count }
    private var totalCount: Int { Location.usStates.count }
    private var percentage: Int {
        totalCount > 0 ? (seenCount * 100) / totalCount : 0
    }
    private var isShared: Bool { trip.participantsArray.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trip.name)
                    .font(.headline)
                if trip.isClosed {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                if isShared {
                    HStack(spacing: 2) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text("\(trip.participantsArray.count)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("^[\(trip.participantsArray.count) participant](inflect: true)")
                }
            }
            HStack(spacing: 0) {
                Text(trip.createdDate ?? Date(), style: .date)
                Text("  —  \(seenCount)/\(totalCount): \(percentage)%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
