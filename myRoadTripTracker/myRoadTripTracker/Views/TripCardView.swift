import SwiftUI
import CoreData

struct TripCardView: View {
    @ObservedObject var trip: Trip

    private var sightings: [PlateSighting] { trip.plateSightingsArray }
    private static let usCodes = Set(Location.usStates.map(\.code))
    private var seenCount: Int { sightings.filter { Self.usCodes.contains($0.locationCode) }.count }
    private var totalCount: Int { Location.usStates.count }
    private var progress: Double {
        totalCount > 0 ? Double(seenCount) / Double(totalCount) : 0
    }
    private var isShared: Bool { trip.participantsArray.count > 1 }

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
                    if isShared {
                        Spacer()
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

            ProgressRingView(progress: progress, seenCount: seenCount, label: "\(seenCount)/\(totalCount)")
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity)
        .aspectRatio(0.85, contentMode: .fit)
        .background(cardColor.gradient, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trip.name), \(seenCount) of \(totalCount) plates\(trip.isClosed ? ", closed" : "")")
    }
}

struct ProgressRingView: View {
    let progress: Double
    let seenCount: Int
    let label: String

    private var ringColor: Color {
        if seenCount <= 15 {
            return .red
        } else if seenCount <= 30 {
            return .yellow
        } else {
            return .green
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
        }
        .frame(width: 60, height: 60)
    }
}
