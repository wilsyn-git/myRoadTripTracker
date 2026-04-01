//
//  TripDetailView.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import SwiftUI
import SwiftData

enum TripTab: String, CaseIterable {
    case plates = "Plates"
    case notes = "Notes"
}

struct TripDetailView: View {
    @Bindable var trip: Trip
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PersistenceController.self) private var persistenceController
    @FocusState private var isNameFieldFocused: Bool
    @State private var locationManager = LocationManager()
    @State private var selectedTab: TripTab = .plates
    @State private var showingSharingSheet = false
    @AppStorage("defaultDisplayName") private var currentUserName = "Me"
    let isNewTrip: Bool
    @State private var showingNamePrompt = false
    @State private var resolvedDisplayName: String?
    @State private var cloudKitUserID: String = ""
    @State private var showingParticipants = false

    var body: some View {
        VStack(spacing: 0) {
            // Sticky header: trip name
            TextField("Trip Name", text: $trip.name)
                .font(.title2)
                .fontWeight(.bold)
                .focused($isNameFieldFocused)
                .disabled(trip.isClosed)
                .padding(.horizontal)
                .padding(.top, 8)
                .task {
                    if isNewTrip {
                        try? await Task.sleep(for: .milliseconds(100))
                        isNameFieldFocused = true
                    }
                }

            // Tab picker
            Picker("Tab", selection: $selectedTab) {
                ForEach(TripTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Tab content
            switch selectedTab {
            case .plates:
                PlatesTabView(trip: trip, locationManager: locationManager)
            case .notes:
                NotesTabView(trip: trip, currentUserName: resolvedDisplayName ?? currentUserName)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
                resolvedDisplayName = trip.participants.first { $0.cloudKitUserID == cloudKitUserID }?.displayName ?? currentUserName
            } else {
                showingNamePrompt = true
            }
        }
        .cloudSharingSheet(for: trip, persistenceController: persistenceController, isPresented: $showingSharingSheet)
        .sheet(isPresented: $showingParticipants) {
            ParticipantsView(
                trip: trip,
                isOwner: persistenceController.isOwner(of: trip),
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

// MARK: - Plates Tab

struct PlatesTabView: View {
    @Bindable var trip: Trip
    var locationManager: LocationManager
    @State private var showingMapView = false

    var body: some View {
        List {
            PlateSightingsSection(trip: trip, locationManager: locationManager)

            Section {
                Button {
                    showingMapView = true
                } label: {
                    Label("View Sightings Map", systemImage: "map")
                }
                .disabled(trip.plateSightings.isEmpty)
            }
        }
        .sheet(isPresented: $showingMapView) {
            PlateSightingsMapView(sightings: trip.plateSightings)
        }
    }
}

// MARK: - Notes Tab

struct NotesTabView: View {
    @Bindable var trip: Trip
    let currentUserName: String

    var body: some View {
        List {
            ObservationsSection(trip: trip, currentUserName: currentUserName)
        }
    }
}
