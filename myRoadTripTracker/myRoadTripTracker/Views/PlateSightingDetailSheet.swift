import SwiftUI
import CoreData

struct PlateSightingDetailSheet: View {
    let sighting: PlateSighting
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingRemoveAlert = false
    @State private var showingMap = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(sighting.flagImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 52)
                    .clipShape(.rect(cornerRadius: 4))

                Text("\(sighting.locationCode) — \(sighting.locationName)")
                    .font(.title3.bold())

                VStack(spacing: 4) {
                    if let date = sighting.seenDate {
                        Text("Spotted \(Text(date, style: .relative)) ago")
                            .font(.subheadline)
                    } else {
                        Text("Spotted recently")
                            .font(.subheadline)
                    }

                    if let name = sighting.spottedByName, !name.isEmpty {
                        Text("by \(name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if sighting.hasValidCoordinate {
                        Text(String(format: "%.4f, %.4f", sighting.latitude, sighting.longitude))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No location recorded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    if sighting.hasValidCoordinate {
                        Button {
                            showingMap = true
                        } label: {
                            Text("View on map")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if !trip.isClosed {
                        Button(role: .destructive) {
                            showingRemoveAlert = true
                        } label: {
                            Text("Remove")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(.top, 4)

                Spacer()
            }
            .padding()
            .navigationDestination(isPresented: $showingMap) {
                PlateSightingsMapView(sightings: [sighting], embedded: true)
            }
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.visible)
            .alert("Remove Sighting", isPresented: $showingRemoveAlert) {
                Button("Remove", role: .destructive) {
                    viewContext.delete(sighting)
                    viewContext.save(contextInfo: "removeSighting")
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Remove the \(sighting.locationName) plate sighting? This deletes the location data.")
            }
        }
    }
}
