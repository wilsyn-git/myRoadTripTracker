//
//  TripDetailView.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import SwiftUI
import SwiftData

struct TripDetailView: View {
    @Bindable var trip: Trip
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isNameFieldFocused: Bool
    @State private var locationManager = LocationManager()
    @State private var showingMapView = false
    @AppStorage("defaultDisplayName") private var currentUserName = "Me"
    let isNewTrip: Bool
    
    var body: some View {
        List {
            Section {
                // Editable trip name at the top
                TextField("Trip Name", text: $trip.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .focused($isNameFieldFocused)
                    .task {
                        if isNewTrip {
                            try? await Task.sleep(for: .milliseconds(100))
                            isNameFieldFocused = true
                        }
                    }
            }
            
            PlateSightingsSection(trip: trip, locationManager: locationManager)
            
            ObservationsSection(trip: trip, currentUserName: currentUserName)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingMapView = true
                } label: {
                    Label("View Map", systemImage: "map")
                }
                .disabled(trip.plateSightings.isEmpty)
            }
        }
        .sheet(isPresented: $showingMapView) {
            PlateSightingsMapView(sightings: trip.plateSightings)
        }
    }
}
