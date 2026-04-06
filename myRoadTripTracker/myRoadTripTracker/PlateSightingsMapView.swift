import CoreData
import SwiftUI
import MapKit

struct PlateSightingsMapView: View {
    let sightings: [PlateSighting]
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedSighting: PlateSighting?

    /// Sightings that have a real coordinate or can be interpolated from neighbors.
    private var mappableSightings: [(sighting: PlateSighting, coordinate: CLLocationCoordinate2D, isInterpolated: Bool)] {
        let sorted = sightings.sorted { ($0.seenDate ?? .distantPast) < ($1.seenDate ?? .distantPast) }
        let validCoords = sorted.filter(\.hasValidCoordinate)

        return sorted.compactMap { sighting in
            if sighting.hasValidCoordinate {
                return (sighting, sighting.coordinate, false)
            }
            // Interpolate from nearest neighbors with valid coordinates
            let date = sighting.seenDate ?? .distantPast
            let before = validCoords.last { ($0.seenDate ?? .distantPast) <= date }
            let after = validCoords.first { ($0.seenDate ?? .distantPast) >= date }

            if let before, let after, before.objectID != after.objectID {
                let lat = (before.latitude + after.latitude) / 2
                let lon = (before.longitude + after.longitude) / 2
                return (sighting, CLLocationCoordinate2D(latitude: lat, longitude: lon), true)
            } else if let nearest = before ?? after {
                return (sighting, nearest.coordinate, true)
            }
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    ForEach(mappableSightings, id: \.sighting.objectID) { item in
                        Annotation(item.sighting.locationCode, coordinate: item.coordinate) {
                            Image(item.sighting.flagImageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 20)
                                .clipShape(.rect(cornerRadius: 2))
                                .shadow(radius: 2)
                                .opacity(item.isInterpolated ? 0.6 : 1.0)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(selectedSighting?.objectID == item.sighting.objectID ? Color.accentColor : Color.white, lineWidth: 1.5)
                                )
                                .onTapGesture {
                                    withAnimation {
                                        selectedSighting = item.sighting
                                    }
                                }
                                .accessibilityLabel("\(item.sighting.locationName) plate sighting\(item.isInterpolated ? ", approximate location" : "")")
                                .accessibilityHint("Tap for details")
                        }
                    }
                }
                .mapStyle(.standard)
                .onTapGesture {
                    withAnimation {
                        selectedSighting = nil
                    }
                }

                if let sighting = selectedSighting {
                    let isInterpolated = mappableSightings.first(where: { $0.sighting.objectID == sighting.objectID })?.isInterpolated ?? false
                    SightingDetailCard(sighting: sighting, isInterpolated: isInterpolated)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding()
                }
            }
            .navigationTitle("Plate Sightings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SightingDetailCard: View {
    let sighting: PlateSighting
    var isInterpolated: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(sighting.flagImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 30)
                .clipShape(.rect(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 2) {
                Text(sighting.locationName)
                    .font(.headline)
                if let date = sighting.seenDate {
                    Text(date, format: .dateTime.month(.wide).day().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isInterpolated {
                    Text("Approximate location")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
