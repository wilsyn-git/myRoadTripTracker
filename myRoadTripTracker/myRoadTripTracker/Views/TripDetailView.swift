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
    @State private var showingRecap = false
    @State private var isGeneratingRecap = false
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
                .onChange(of: isNameFieldFocused) { _, focused in
                    // Commit once when the user finishes editing, rather than on every
                    // keystroke — avoids syncing partial names to collaborators.
                    if !focused { viewContext.save(contextInfo: "tripNameChange") }
                }
                .onDisappear {
                    // Safety net: if the view tears down while the field is still focused
                    // (e.g. navigating back without dismissing the keyboard).
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
                PlateSightingsGrid(trip: trip, locationManager: locationManager, plateFilter: plateFilter, currentUserName: resolvedDisplayName ?? currentUserName)
            case .notes:
                NotesTabView(trip: trip, currentUserName: resolvedDisplayName ?? currentUserName)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if selectedTab == .plates {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        // A Picker inside a Menu renders the options with a native
                        // checkmark on the selection — no empty-SF-Symbol hack needed.
                        Picker("Filter", selection: $plateFilter) {
                            ForEach(PlateFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                    } label: {
                        // Label (not bare Image) gives VoiceOver a spoken name while the
                        // toolbar still renders it icon-only.
                        Label("Filter Plates", systemImage: plateFilter == .all
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
                    showingRecap = true
                } label: {
                    Label("Trip Recap", systemImage: "sparkles")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    let wasClosed = trip.isClosed
                    trip.isClosed.toggle()
                    viewContext.save(contextInfo: "toggleClosed")
                    if !wasClosed {
                        Task { await generateRecap() }
                    }
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
        .sheet(isPresented: $showingRecap) {
            TripRecapView(trip: trip)
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

    @MainActor
    private func generateRecap() async {
        guard isOwner, !isGeneratingRecap else { return }
        let stats = RecapStats(trip: trip)
        guard !stats.isEmpty else { return }
        isGeneratingRecap = true
        defer { isGeneratingRecap = false }
        let narrative = await RecapNarrativeGenerator.generate(from: stats, tripName: trip.name)
        // Back on the main actor after the await. recapGeneratedDate is stamped even when
        // the model is unavailable (narrative == nil) so the "recap ready" badge appears
        // for everyone; TripRecapView falls back to the template narrative.
        if let narrative { trip.recapNarrative = narrative }
        trip.recapGeneratedDate = Date()
        viewContext.save(contextInfo: "generateRecap")
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
