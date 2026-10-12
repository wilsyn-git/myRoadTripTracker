import CloudKit
import SwiftUI
import CoreData

struct TripDetailView: View {
    @ObservedObject var trip: Trip
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(PersistenceController.self) private var persistenceController
    @State private var locationManager = LocationManager()
    @State private var selectedTab: TripTab = .plates
    /// The trip's CloudKit share when the screen opened, so the share sheet can show it as is.
    @State private var tripShare: CKShare?
    @AppStorage("defaultDisplayName") private var currentUserName = "Me"
    let isNewTrip: Bool
    let onLeave: (String) -> Void
    @State private var showingNamePrompt = false
    @State private var resolvedDisplayName: String?
    @State private var cloudKitUserID: String = ""
    @State private var showingParticipants = false
    @State private var showingMapView = false
    @State private var showingRecap = false
    @State private var isGeneratingRecap = false
    @State private var isOwner = true
    @State private var plateFilter: PlateFilter = .all

    var body: some View {
        tripContent
            .task { await resolveParticipant() }
    }

    /// Works out who you are on this trip without holding up the screen (#36). It finds your
    /// participant row, creates one for a new trip or a trip you own, or asks for a display
    /// name when you're joining someone else's. It's skipped while your ID can't be known
    /// (offline before it was ever fetched); the next open tries again.
    private func resolveParticipant() async {
        isOwner = persistenceController.isOwner(of: trip)
        // A local lookup, no network. Only owners can share.
        tripShare = isOwner ? persistenceController.existingShare(for: trip) : nil
        guard let userID = await CloudKitUserHelper.currentUserID(),
              !trip.isDeleted, trip.managedObjectContext != nil else { return }
        cloudKitUserID = userID
        let participants = trip.participantsArray
        if let existing = participants.first(where: { $0.cloudKitUserID == userID }) {
            resolvedDisplayName = existing.displayName
        } else if participants.isEmpty || isOwner {
            // Your own trip never asks you to join it.
            let participant = TripParticipant(
                context: viewContext,
                displayName: currentUserName,
                cloudKitUserID: userID
            )
            participant.trip = trip
            viewContext.save(contextInfo: "addInitialParticipant")
            resolvedDisplayName = currentUserName
        } else {
            showingNamePrompt = true
        }
    }

    private var tripContent: some View {
        VStack(spacing: 0) {
            TripNameField(trip: trip, focusOnAppear: isNewTrip)
                .padding(.horizontal)
                .padding(.top, 8)

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
            // Only owners share. `isOwner(of:)` needs no fetch, so asking it here (rather than
            // the `isOwner` state, which starts out true) keeps the button from flashing up
            // for a participant.
            if persistenceController.isOwner(of: trip) {
                // Its own bar button, not an item in the overflow menu: the share sheet
                // presents as a popover anchored to this button. From the menu it had no
                // anchor once the menu closed, and UIKit threw (#62).
                ToolbarItem(placement: .primaryAction) {
                    // The sheet opens at once; a new share is made after a destination is picked (#44).
                    ShareLink(
                        item: TripShareItem(tripID: trip.objectID, existingShare: tripShare),
                        preview: SharePreview(trip.name)
                    ) {
                        Label("Share Trip", systemImage: "square.and.arrow.up")
                    }
                }
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
                    // A count, not `plateSightingsArray`, which sorts every sighting.
                    .disabled((trip.plateSightings?.count ?? 0) == 0)
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
        .sheet(isPresented: $showingParticipants) {
            ParticipantsView(
                trip: trip,
                isOwner: isOwner,
                currentUserID: cloudKitUserID,
                onLeave: onLeave
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
