import SwiftUI
import CoreData

struct TripCardView: View {
    @ObservedObject var trip: Trip

    private var sightings: [PlateSighting] { trip.plateSightingsArray }

    private static let usCodes = Set(Location.usStates.map(\.code))
    private var usSeenCount: Int { sightings.filter { Self.usCodes.contains($0.locationCode) }.count }
    private var usTotalCount: Int { Location.usStates.count }
    private var usProgress: Double {
        usTotalCount > 0 ? Double(usSeenCount) / Double(usTotalCount) : 0
    }

    private static let caCodes = Set(Location.canadaLocations.map(\.code))
    private var caSeenCount: Int { sightings.filter { Self.caCodes.contains($0.locationCode) }.count }
    private var caTotalCount: Int { Location.canadaLocations.count }
    private var caProgress: Double {
        caTotalCount > 0 ? Double(caSeenCount) / Double(caTotalCount) : 0
    }

    private var isShared: Bool { trip.participantsArray.count > 1 }

    private var observations: [ObservationEntry] { trip.observationEntriesArray }
    private var totalObservationCount: Int { observations.count }
    private var newObservationCount: Int {
        guard let tripID = trip.tripID?.uuidString else { return totalObservationCount }
        let key = "lastViewedObservations_\(tripID)"
        guard let lastViewed = UserDefaults.standard.object(forKey: key) as? Date else {
            return totalObservationCount
        }
        return observations.filter { ($0.createdDate ?? .distantPast) > lastViewed }.count
    }

    private var hasUnseenRecap: Bool {
        guard let generated = trip.recapGeneratedDate else { return false }
        guard let tripID = trip.tripID?.uuidString else { return true }
        let key = "lastViewedRecap_\(tripID)"
        guard let lastViewed = UserDefaults.standard.object(forKey: key) as? Date else {
            return true
        }
        return generated > lastViewed
    }

    private var recentSightings: [PlateSighting] {
        Array(sightings.suffix(5).reversed())
    }

    private var cardColor: Color {
        trip.isClosed ? Color(white: 0.38) : Color(red: 0.2, green: 0.65, blue: 0.35)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(trip.name)
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 6) {
                    if trip.isClosed {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .accessibilityHidden(true)
                    }
                    Text(trip.createdDate ?? Date(), style: .date)
                        .font(.caption)

                    Spacer()

                    if totalObservationCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "text.bubble.fill")
                                .font(.caption2)
                            Text("\(totalObservationCount)")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .overlay(alignment: .topTrailing) {
                            if newObservationCount > 0 {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }

                    if hasUnseenRecap {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("New recap available")
                    }

                    if isShared {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text("\(trip.participantsArray.count)")
                            .font(.caption2)
                    }
                }
                .opacity(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            if !recentSightings.isEmpty {
                HStack(spacing: -4) {
                    ForEach(recentSightings, id: \.objectID) { sighting in
                        Image(sighting.flagImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 18)
                            .clipShape(.rect(cornerRadius: 2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(.white.opacity(0.6), lineWidth: 1)
                            )
                    }
                    Spacer()
                }
                .accessibilityHidden(true)
            }

            Spacer()

            DualProgressRingView(
                usProgress: usProgress,
                usSeenCount: usSeenCount,
                usTotalCount: usTotalCount,
                caProgress: caProgress,
                caSeenCount: caSeenCount,
                caTotalCount: caTotalCount
            )
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity)
        .aspectRatio(0.85, contentMode: .fit)
        .background(cardColor.gradient, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trip.name), \(usSeenCount) of \(usTotalCount) US plates, \(caSeenCount) of \(caTotalCount) Canadian plates\(trip.isClosed ? ", closed" : "")\(hasUnseenRecap ? ", new recap available" : "")")
    }
}
