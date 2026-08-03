import SwiftUI
import CoreData

struct TripCardView: View {
    @ObservedObject var trip: Trip

    private static let usCodes = Set(Location.usStates.map(\.code))
    private static let caCodes = Set(Location.canadaLocations.map(\.code))
    private static let usTotalCount = Location.usStates.count
    private static let caTotalCount = Location.canadaLocations.count

    private struct CardData {
        var usSeenCount = 0
        var caSeenCount = 0
        var totalObservationCount = 0
        var newObservationCount = 0
        var participantCount = 0
        var recentSightings: [PlateSighting] = []
    }

    /// Compute every derived value the card needs in a single pass, reading each Core Data set
    /// once. Counts read the sets directly (order is irrelevant); only `recentSightings` sorts.
    /// Bound once at the top of `body`, so a render does the sort work at most once.
    private var cardData: CardData {
        var data = CardData()

        let sightingsSet = (trip.plateSightings as? Set<PlateSighting>) ?? []
        for sighting in sightingsSet {
            let code = sighting.locationCode
            if Self.usCodes.contains(code) {
                data.usSeenCount += 1
            } else if Self.caCodes.contains(code) {
                data.caSeenCount += 1
            }
        }
        data.recentSightings = Array(
            sightingsSet
                .sorted { ($0.seenDate ?? .distantPast) < ($1.seenDate ?? .distantPast) }
                .suffix(5)
                .reversed()
        )

        let observationsSet = (trip.observationEntries as? Set<ObservationEntry>) ?? []
        data.totalObservationCount = observationsSet.count
        data.newObservationCount = unseenObservationCount(in: observationsSet)

        data.participantCount = (trip.participants as? Set<TripParticipant>)?.count ?? 0

        return data
    }

    private func unseenObservationCount(in observations: Set<ObservationEntry>) -> Int {
        guard let tripID = trip.tripID?.uuidString else { return observations.count }
        let key = "lastViewedObservations_\(tripID)"
        guard let lastViewed = UserDefaults.standard.object(forKey: key) as? Date else {
            return observations.count
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

    private var cardColor: Color {
        trip.isClosed ? Color(white: 0.38) : Color(red: 0.2, green: 0.65, blue: 0.35)
    }

    var body: some View {
        let data = cardData
        let unseenRecap = hasUnseenRecap

        return VStack(spacing: 0) {
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
                    // No fallback to `Date()` — an unknown date must not render as today.
                    if let createdDate = trip.createdDate {
                        Text(createdDate, style: .date)
                            .font(.caption)
                    }

                    Spacer()

                    if data.totalObservationCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "text.bubble.fill")
                                .font(.caption2)
                            Text("\(data.totalObservationCount)")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .overlay(alignment: .topTrailing) {
                            if data.newObservationCount > 0 {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }

                    if unseenRecap {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("New recap available")
                    }

                    if data.participantCount > 1 {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text("\(data.participantCount)")
                            .font(.caption2)
                    }
                }
                .opacity(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            if !data.recentSightings.isEmpty {
                HStack(spacing: -4) {
                    ForEach(data.recentSightings, id: \.objectID) { sighting in
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
                usProgress: Self.usTotalCount > 0 ? Double(data.usSeenCount) / Double(Self.usTotalCount) : 0,
                usSeenCount: data.usSeenCount,
                usTotalCount: Self.usTotalCount,
                caProgress: Self.caTotalCount > 0 ? Double(data.caSeenCount) / Double(Self.caTotalCount) : 0,
                caSeenCount: data.caSeenCount,
                caTotalCount: Self.caTotalCount
            )
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity)
        .aspectRatio(0.85, contentMode: .fit)
        .background(cardColor.gradient, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trip.name), \(data.usSeenCount) of \(Self.usTotalCount) US plates, \(data.caSeenCount) of \(Self.caTotalCount) Canadian plates\(trip.isClosed ? ", closed" : "")\(unseenRecap ? ", new recap available" : "")")
    }
}
