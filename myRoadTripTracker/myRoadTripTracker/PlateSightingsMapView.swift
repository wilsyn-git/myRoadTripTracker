import CoreData
import SwiftUI
import MapKit

struct PlateSightingsMapView: View {
    let sightings: [PlateSighting]
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedSighting: PlateSighting?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    ForEach(sightings) { sighting in
                        Annotation(sighting.locationCode, coordinate: sighting.coordinate) {
                            Image(sighting.locationName.lowercased().replacing(" ", with: "_"))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 20)
                                .clipShape(.rect(cornerRadius: 2))
                                .shadow(radius: 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(selectedSighting?.objectID == sighting.objectID ? Color.accentColor : Color.white, lineWidth: 1.5)
                                )
                                .onTapGesture {
                                    withAnimation {
                                        selectedSighting = sighting
                                    }
                                }
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
                    SightingDetailCard(sighting: sighting)
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

    var body: some View {
        HStack(spacing: 12) {
            Image(sighting.locationName.lowercased().replacing(" ", with: "_"))
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
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
