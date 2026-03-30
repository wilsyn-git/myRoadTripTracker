//
//  PlateSightingsSection.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import SwiftUI
import SwiftData
import CoreLocation

struct PlateSightingsSection: View {
    @Bindable var trip: Trip
    var locationManager: LocationManager
    @Environment(\.modelContext) private var modelContext
    
    private var seenCount: Int {
        trip.plateSightings.count
    }
    
    private var totalCount: Int {
        Location.allLocations.count
    }
    
    var body: some View {
        Section {
            ForEach(Location.allLocations) { location in
                PlateRow(
                    location: location,
                    isSeen: isSeen(location),
                    onTap: { markAsSeen(location) },
                    onRemove: { unmarkAsSeen(location) }
                )
                .disabled(trip.isClosed)
            }
        } header: {
            HStack {
                Text("License Plates")
                Spacer()
                Text("\(seenCount)/\(totalCount)")
                    .fontWeight(.semibold)
            }
        }
    }
    
    private func isSeen(_ location: Location) -> Bool {
        trip.plateSightings.contains { $0.locationCode == location.code }
    }
    
    private func markAsSeen(_ location: Location) {
        guard !isSeen(location) else { return }

        Task {
            let loc = await locationManager.requestCurrentLocation()
            let latitude = loc?.coordinate.latitude ?? 0.0
            let longitude = loc?.coordinate.longitude ?? 0.0

            let sighting = PlateSighting(
                locationCode: location.code,
                locationName: location.name,
                latitude: latitude,
                longitude: longitude
            )
            sighting.trip = trip
            trip.plateSightings.append(sighting)
            modelContext.insert(sighting)
        }
    }
    
    private func unmarkAsSeen(_ location: Location) {
        guard let sighting = trip.plateSightings.first(where: { $0.locationCode == location.code }) else { return }
        
        if let index = trip.plateSightings.firstIndex(of: sighting) {
            trip.plateSightings.remove(at: index)
        }
        modelContext.delete(sighting)
    }
}

struct PlateRow: View {
    let location: Location
    let isSeen: Bool
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(location.code)
                    .font(.system(.body, design: .monospaced))
                    .bold()
                    .frame(width: 50, alignment: .leading)

                Text(location.name)

                Spacer()

                if isSeen {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
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
