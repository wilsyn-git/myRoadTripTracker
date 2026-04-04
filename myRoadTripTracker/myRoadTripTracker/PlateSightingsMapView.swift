import SwiftUI
import MapKit

struct PlateSightingsMapView: View {
    let sightings: [PlateSighting]
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                ForEach(sightings) { sighting in
                    Marker(sighting.locationCode, coordinate: sighting.coordinate)
                        .tint(.green)
                }
            }
            .mapStyle(.standard)
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
