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
    @State private var showingSharingSheet = false
    @AppStorage("defaultDisplayName") private var currentUserName = "Me"
    let isNewTrip: Bool
    @State private var showingNamePrompt = false
    @State private var resolvedDisplayName: String?
    @State private var cloudKitUserID: String = ""
    @State private var showingParticipants = false
    
    var body: some View {
        List {
            Section {
                // Editable trip name at the top
                TextField("Trip Name", text: $trip.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .focused($isNameFieldFocused)
                    .disabled(trip.isClosed)
                    .task {
                        if isNewTrip {
                            try? await Task.sleep(for: .milliseconds(100))
                            isNameFieldFocused = true
                        }
                    }
            }
            
            PlateSightingsSection(trip: trip, locationManager: locationManager)
            
            ObservationsSection(trip: trip, currentUserName: resolvedDisplayName ?? currentUserName)
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
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingSharingSheet = true
                } label: {
                    Label("Share Trip", systemImage: "square.and.arrow.up")
                }
                .disabled(trip.isClosed)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingParticipants = true
                } label: {
                    Label("Participants", systemImage: "person.2")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    trip.isClosed.toggle()
                } label: {
                    Label(
                        trip.isClosed ? "Reopen Trip" : "Close Trip",
                        systemImage: trip.isClosed ? "lock.open" : "lock"
                    )
                }
            }
        }
        .task {
            cloudKitUserID = await CloudKitUserHelper.currentUserID()
            // For local/new trips, auto-create a participant record silently
            if trip.participants.isEmpty {
                let participant = TripParticipant(
                    displayName: currentUserName,
                    cloudKitUserID: cloudKitUserID
                )
                participant.trip = trip
                trip.participants.append(participant)
                modelContext.insert(participant)
                resolvedDisplayName = currentUserName
            } else if trip.participants.contains(where: { $0.cloudKitUserID == cloudKitUserID }) {
                // User already has a participant record
                resolvedDisplayName = trip.participants.first { $0.cloudKitUserID == cloudKitUserID }?.displayName ?? currentUserName
            } else {
                // This is a shared trip and user doesn't have a record - prompt
                showingNamePrompt = true
            }
        }
        .sheet(isPresented: $showingMapView) {
            PlateSightingsMapView(sightings: trip.plateSightings)
        }
        .sheet(isPresented: $showingSharingSheet) {
            CloudSharingView(trip: trip, modelContainer: modelContext.container)
        }
        .sheet(isPresented: $showingParticipants) {
            ParticipantsView(
                trip: trip,
                isOwner: true,  // For now, assume owner. Real ownership check needs CloudKit share inspection.
                currentUserID: cloudKitUserID
            )
        }
        .sheet(isPresented: $showingNamePrompt) {
            JoinTripNameView(trip: trip) { name in
                let participant = TripParticipant(
                    displayName: name,
                    cloudKitUserID: cloudKitUserID
                )
                participant.trip = trip
                trip.participants.append(participant)
                modelContext.insert(participant)
                resolvedDisplayName = name
                showingNamePrompt = false
            }
        }
    }
}
