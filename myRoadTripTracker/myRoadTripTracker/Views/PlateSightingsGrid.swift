import SwiftUI
import CoreData
import CoreLocation

enum PlateFilter: String, CaseIterable {
    case all = "All"
    case notSeen = "Not Seen"
}

struct PlateSightingsGrid: View {
    @ObservedObject var trip: Trip
    var locationManager: LocationManager
    var plateFilter: PlateFilter = .all
    var currentUserName: String
    @Environment(\.managedObjectContext) private var viewContext
    @State private var recordingCodes: Set<String> = []
    @State private var revealingCodes: Set<String> = []
    @State private var sightingToInspect: PlateSighting?

    private var sightings: [PlateSighting] {
        trip.plateSightingsArray
    }

    private func filtered(_ locations: [Location], seenCodes: Set<String>) -> [Location] {
        switch plateFilter {
        case .all:
            return locations
        case .notSeen:
            return locations.filter { !seenCodes.contains($0.code) }
        }
    }

    private func isSeen(_ location: Location) -> Bool {
        sightings.contains { $0.locationCode == location.code }
    }

    private func sighting(for location: Location) -> PlateSighting? {
        sightings.first { $0.locationCode == location.code }
    }

    var body: some View {
        // Build the seen-code lookup once per render so each tile does an O(1) membership
        // check instead of scanning every sighting.
        let seenCodes = Set(sightings.map(\.locationCode))

        ScrollView {
            VStack(spacing: 16) {
                if trip.isClosed {
                    closedTripBanner
                }
                sectionView(title: "US States & DC", locations: Location.usStates, seenCodes: seenCodes)
                sectionView(title: "Canada", locations: Location.canadaLocations, seenCodes: seenCodes)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .sheet(item: $sightingToInspect) { sighting in
            PlateSightingDetailSheet(sighting: sighting, trip: trip)
        }
    }

    private var closedTripBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
            Text("Trip closed \u{2014} read only")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray5), in: Capsule())
    }

    private func sectionView(title: String, locations: [Location], seenCodes: Set<String>) -> some View {
        let visible = filtered(locations, seenCodes: seenCodes)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: title, locations: locations, seenCodes: seenCodes)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(visible) { location in
                    PlateTileView(
                        location: location,
                        isSeen: seenCodes.contains(location.code),
                        isRecording: recordingCodes.contains(location.code),
                        isRevealing: revealingCodes.contains(location.code),
                        onTapUnseen: { markAsSeen(location) },
                        onTapSeen: { sightingToInspect = sighting(for: location) }
                    )
                    .contextMenu {
                        if seenCodes.contains(location.code), !trip.isClosed {
                            Button("Remove sighting", role: .destructive) {
                                unmarkAsSeen(location)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(title: String, locations: [Location], seenCodes: Set<String>) -> some View {
        let seen = locations.filter { seenCodes.contains($0.code) }.count
        let total = locations.count
        let progress = total > 0 ? Double(seen) / Double(total) : 0

        return VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(seen)/\(total)")
                    .fontWeight(.semibold)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.96, green: 0.62, blue: 0.04),
                                    Color(red: 0.98, green: 0.75, blue: 0.15)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 3)
        }
    }

    private func markAsSeen(_ location: Location) {
        guard !trip.isClosed, !isSeen(location), !recordingCodes.contains(location.code) else { return }

        recordingCodes.insert(location.code)

        Task {
            let loc = await locationManager.requestCurrentLocation()
            let latitude = loc?.coordinate.latitude ?? 0.0
            let longitude = loc?.coordinate.longitude ?? 0.0

            recordingCodes.remove(location.code)

            // A Siri mark or a sync may have added it, or the trip may have been
            // closed or deleted, while we waited on GPS.
            guard !trip.isDeleted, trip.managedObjectContext != nil,
                  !trip.isClosed, !isSeen(location) else { return }

            revealingCodes.insert(location.code)

            let sighting = PlateSighting(
                context: viewContext,
                locationCode: location.code,
                locationName: location.name,
                latitude: latitude,
                longitude: longitude,
                spottedByName: currentUserName
            )
            sighting.trip = trip
            viewContext.save(contextInfo: "markAsSeen")

            try? await Task.sleep(for: .milliseconds(800))
            revealingCodes.remove(location.code)
        }
    }

    private func unmarkAsSeen(_ location: Location) {
        guard let sighting = sightings.first(where: { $0.locationCode == location.code }) else { return }
        viewContext.delete(sighting)
        viewContext.save(contextInfo: "unmarkAsSeen")
    }
}
