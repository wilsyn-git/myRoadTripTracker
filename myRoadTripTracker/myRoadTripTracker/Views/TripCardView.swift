import SwiftUI
import CoreData

struct TripCardView: View {
    @ObservedObject var trip: Trip
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    var body: some View {
        let data = cardData
        let unseenRecap = hasUnseenRecap

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(trip.name)
                    .font(.title3)
                    .bold()
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
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
                                .font(.caption)
                            Text("\(data.totalObservationCount)")
                                .font(.caption)
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
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("New recap available")
                    }

                    if data.participantCount > 1 {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .accessibilityHidden(true)
                        Text("\(data.participantCount)")
                            .font(.caption)
                    }
                }
                .opacity(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            if !data.recentSightings.isEmpty {
                HStack(spacing: -4) {
                    ForEach(data.recentSightings, id: \.objectID) { sighting in
                        Image(sighting.flagImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 18)
                            .clipShape(.rect(cornerRadius: 2))
                            .overlay {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(.white.opacity(0.6), lineWidth: 1)
                            }
                    }
                    Spacer()
                }
                .accessibilityHidden(true)
            }

            Spacer(minLength: 8)

            // Stacked: two bars side by side don't fit a 160pt card.
            RegionProgressBars(usSeen: data.usSeenCount, caSeen: data.caSeenCount, axis: .vertical)
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity)
        .tripCardAspect(fixed: !dynamicTypeSize.isAccessibilitySize)
        .background(Theme.panel(closed: trip.isClosed), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trip.name), \(data.usSeenCount) of \(Self.usTotalCount) US plates, \(data.caSeenCount) of \(Self.caTotalCount) Canadian plates\(trip.isClosed ? ", closed" : "")\(unseenRecap ? ", new recap available" : "")")
    }
}

private extension View {
    /// Trip cards keep their fixed shape, except at accessibility text sizes. There they
    /// grow with their content instead of clipping it (#32).
    @ViewBuilder
    func tripCardAspect(fixed: Bool) -> some View {
        if fixed {
            aspectRatio(0.85, contentMode: .fit)
        } else {
            self
        }
    }
}
