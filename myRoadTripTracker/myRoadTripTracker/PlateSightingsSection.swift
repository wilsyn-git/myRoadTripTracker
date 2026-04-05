import SwiftUI
import CoreData
import CoreLocation

struct PlateSightingsSection: View {
    @ObservedObject var trip: Trip
    var locationManager: LocationManager
    @Environment(\.managedObjectContext) private var viewContext
    @State private var locationToRemove: Location?

    private var sightings: [PlateSighting] {
        trip.plateSightingsArray
    }

    private func seenCount(in locations: [Location]) -> Int {
        let codes = Set(locations.map(\.code))
        return sightings.filter { codes.contains($0.locationCode) }.count
    }

    var body: some View {
        plateSection(title: "US States & DC", locations: Location.usStates)
        plateSection(title: "Canada", locations: Location.canadaLocations)
        .alert(
            "Remove Sighting",
            isPresented: Binding(
                get: { locationToRemove != nil },
                set: { if !$0 { locationToRemove = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let location = locationToRemove {
                    unmarkAsSeen(location)
                }
                locationToRemove = nil
            }
            Button("Cancel", role: .cancel) {
                locationToRemove = nil
            }
        } message: {
            if let location = locationToRemove {
                Text("Remove the \(location.name) plate sighting? This will delete the location data.")
            }
        }
    }

    private func plateSection(title: String, locations: [Location]) -> some View {
        Section {
            ForEach(locations) { location in
                PlateRow(
                    location: location,
                    isSeen: isSeen(location),
                    onTap: { markAsSeen(location) },
                    onRemove: { locationToRemove = location }
                )
                .disabled(trip.isClosed)
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Text("\(seenCount(in: locations))/\(locations.count)")
                    .fontWeight(.semibold)
            }
        }
    }

    private func isSeen(_ location: Location) -> Bool {
        sightings.contains { $0.locationCode == location.code }
    }

    private func markAsSeen(_ location: Location) {
        guard !isSeen(location) else { return }

        Task {
            let loc = await locationManager.requestCurrentLocation()
            let latitude = loc?.coordinate.latitude ?? 0.0
            let longitude = loc?.coordinate.longitude ?? 0.0

            let sighting = PlateSighting(
                context: viewContext,
                locationCode: location.code,
                locationName: location.name,
                latitude: latitude,
                longitude: longitude
            )
            sighting.trip = trip
            viewContext.save(contextInfo: "markAsSeen")
        }
    }

    private func unmarkAsSeen(_ location: Location) {
        guard let sighting = sightings.first(where: { $0.locationCode == location.code }) else { return }
        viewContext.delete(sighting)
        viewContext.save(contextInfo: "unmarkAsSeen")
    }
}

struct PlateRow: View {
    let location: Location
    let isSeen: Bool
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: { isSeen ? onRemove() : onTap() }) {
            HStack(spacing: 12) {
                Image(location.flagImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 20)
                    .clipShape(.rect(cornerRadius: 2))
                    .accessibilityHidden(true)

                Text(location.code)
                    .font(.system(.body, design: .monospaced))
                    .bold()
                    .frame(width: 36, alignment: .leading)

                Text(location.name)

                Spacer()

                if isSeen {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
            .background(isSeen ? Color.green.opacity(0.1) : Color.clear)
            .accessibilityLabel("\(location.name), \(isSeen ? "seen" : "not seen")")
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if isSeen {
                Button("Remove", role: .destructive, action: onRemove)
            }
        }
    }
}
