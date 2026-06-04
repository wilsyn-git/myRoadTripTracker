import CoreData
import SwiftUI
import MapKit

/// A sighting paired with the coordinate to plot it at — either its own GPS fix or one
/// interpolated from neighboring sightings when it has none.
struct MappableSighting: Identifiable {
    let sighting: PlateSighting
    let coordinate: CLLocationCoordinate2D
    let isInterpolated: Bool
    var id: NSManagedObjectID { sighting.objectID }
}

struct PlateSightingsMapView: View {
    let sightings: [PlateSighting]
    var embedded: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedSighting: PlateSighting?

    /// Sightings that have a real coordinate or can be interpolated from neighbors.
    /// Computed once at init — `sightings` is immutable for this view's lifetime, so there's
    /// no point recomputing on every tap-driven `body` pass.
    private let mappableSightings: [MappableSighting]

    init(sightings: [PlateSighting], embedded: Bool = false) {
        self.sightings = sightings
        self.embedded = embedded
        self.mappableSightings = Self.computeMappable(from: sightings)
    }

    private static func computeMappable(from sightings: [PlateSighting]) -> [MappableSighting] {
        let sorted = sightings.sorted { ($0.seenDate ?? .distantPast) < ($1.seenDate ?? .distantPast) }
        let validCoords = sorted.filter(\.hasValidCoordinate)

        return sorted.compactMap { sighting in
            if sighting.hasValidCoordinate {
                return MappableSighting(sighting: sighting, coordinate: sighting.coordinate, isInterpolated: false)
            }
            // Interpolate from nearest neighbors with valid coordinates
            let date = sighting.seenDate ?? .distantPast
            let before = validCoords.last { ($0.seenDate ?? .distantPast) <= date }
            let after = validCoords.first { ($0.seenDate ?? .distantPast) >= date }

            if let before, let after, before.objectID != after.objectID {
                let lat = (before.latitude + after.latitude) / 2
                let lon = (before.longitude + after.longitude) / 2
                return MappableSighting(sighting: sighting, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), isInterpolated: true)
            } else if let nearest = before ?? after {
                return MappableSighting(sighting: sighting, coordinate: nearest.coordinate, isInterpolated: true)
            }
            return nil
        }
    }

    private var mapContent: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                ForEach(mappableSightings) { item in
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
                            // Kept as a tap gesture (a Button can fight the Map's own
                            // gestures inside an Annotation), so add the button trait
                            // manually for VoiceOver/Voice Control.
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .mapStyle(.standard)
            // Intentionally a bare tap gesture: this is a "tap empty map to deselect"
            // affordance, not a navigable control. VoiceOver users dismiss via the
            // detail card itself rather than the map background.
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
    }

    var body: some View {
        if embedded {
            mapContent
                .navigationTitle("Plate Sightings")
                .navigationBarTitleDisplayMode(.inline)
        } else {
            NavigationStack {
                mapContent
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
}
