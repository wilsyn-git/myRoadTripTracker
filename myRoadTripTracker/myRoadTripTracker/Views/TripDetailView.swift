import SwiftUI
import CoreData

enum TripTab: String, CaseIterable {
    case plates = "Plates"
    case notes = "Notes"
}

struct TripDetailView: View {
    @ObservedObject var trip: Trip
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
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
    @State private var showingMapView = false
    @State private var isOwner = true
    @State private var isLoading = true
    @State private var plateFilter: PlateFilter = .all

    var body: some View {
        if isLoading {
            ProgressView("Loading trip\u{2026}")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    cloudKitUserID = await CloudKitUserHelper.currentUserID()
                    isOwner = persistenceController.isOwner(of: trip)
                    let participants = trip.participantsArray
                    if participants.isEmpty {
                        let participant = TripParticipant(
                            context: viewContext,
                            displayName: currentUserName,
                            cloudKitUserID: cloudKitUserID
                        )
                        participant.trip = trip
                        viewContext.save(contextInfo: "addInitialParticipant")
                        resolvedDisplayName = currentUserName
                    } else if let existing = participants.first(where: { $0.cloudKitUserID == cloudKitUserID }) {
                        resolvedDisplayName = existing.displayName
                    } else {
                        showingNamePrompt = true
                    }
                    isLoading = false
                }
        } else {
            tripContent
        }
    }

    private var tripContent: some View {
        VStack(spacing: 0) {
            TextField("Trip Name", text: $trip.name)
                .font(.title2)
                .fontWeight(.bold)
                .focused($isNameFieldFocused)
                .disabled(trip.isClosed)
                .padding(.horizontal)
                .padding(.top, 8)
                .onChange(of: trip.name) { _, _ in
                    viewContext.save(contextInfo: "tripNameChange")
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isNameFieldFocused = false
                        }
                    }
                }
                .task {
                    if isNewTrip {
                        try? await Task.sleep(for: .milliseconds(100))
                        isNameFieldFocused = true
                    }
                }

            Picker("Tab", selection: $selectedTab) {
                ForEach(TripTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch selectedTab {
            case .plates:
                PlatesTabView(trip: trip, locationManager: locationManager, plateFilter: plateFilter, currentUserName: resolvedDisplayName ?? currentUserName)
            case .notes:
                NotesTabView(trip: trip, currentUserName: resolvedDisplayName ?? currentUserName)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if selectedTab == .plates {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(PlateFilter.allCases, id: \.self) { filter in
                            Button {
                                plateFilter = filter
                            } label: {
                                Label(filter.rawValue, systemImage: plateFilter == filter ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Image(systemName: plateFilter == .all
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingSharingSheet = true
                } label: {
                    Label("Share Trip", systemImage: "square.and.arrow.up")
                }
                .disabled(!isOwner)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingParticipants = true
                } label: {
                    Label("Participants", systemImage: "person.2")
                }
            }
            if selectedTab == .plates {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showingMapView = true
                    } label: {
                        Label("View Sightings Map", systemImage: "map")
                    }
                    .disabled(trip.plateSightingsArray.isEmpty)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    trip.isClosed.toggle()
                    viewContext.save(contextInfo: "toggleClosed")
                } label: {
                    Label(
                        trip.isClosed ? "Reopen Trip" : "Close Trip",
                        systemImage: trip.isClosed ? "lock.open" : "lock"
                    )
                }
                .disabled(!isOwner)
            }
        }
        .cloudSharingSheet(for: trip, persistenceController: persistenceController, isPresented: $showingSharingSheet)
        .sheet(isPresented: $showingParticipants) {
            ParticipantsView(
                trip: trip,
                isOwner: isOwner,
                currentUserID: cloudKitUserID
            )
        }
        .sheet(isPresented: $showingMapView) {
            PlateSightingsMapView(sightings: trip.plateSightingsArray)
        }
        .sheet(isPresented: $showingNamePrompt) {
            JoinTripNameView(trip: trip) { name in
                let participant = TripParticipant(
                    context: viewContext,
                    displayName: name,
                    cloudKitUserID: cloudKitUserID
                )
                participant.trip = trip
                viewContext.save(contextInfo: "joinTrip")
                resolvedDisplayName = name
                showingNamePrompt = false
            }
        }
    }
}

// MARK: - Plates Tab

struct PlatesTabView: View {
    @ObservedObject var trip: Trip
    var locationManager: LocationManager
    var plateFilter: PlateFilter = .all
    var currentUserName: String

    var body: some View {
        PlateSightingsGrid(trip: trip, locationManager: locationManager, plateFilter: plateFilter, currentUserName: currentUserName)
    }
}

// MARK: - Notes Tab

struct NotesTabView: View {
    @ObservedObject var trip: Trip
    let currentUserName: String

    var body: some View {
        List {
            ObservationsSection(trip: trip, currentUserName: currentUserName)
        }
        .onAppear { markObservationsViewed() }
        .onDisappear { markObservationsViewed() }
    }

    private func markObservationsViewed() {
        guard let tripID = trip.tripID?.uuidString else { return }
        UserDefaults.standard.set(Date(), forKey: "lastViewedObservations_\(tripID)")
    }
}
