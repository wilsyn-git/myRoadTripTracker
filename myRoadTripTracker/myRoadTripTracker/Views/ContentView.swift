//
//  ContentView.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import SwiftUI
import AppIntents
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(PersistenceController.self) private var persistenceController

    /// Every trip. `TripListSections` groups and orders them by activity (#65); this sort
    /// only keeps the fetch stable.
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Trip.createdDate, ascending: false)],
        animation: .default
    )
    private var trips: FetchedResults<Trip>

    /// Bumped whenever a trip or sighting changes in the view context, so the list regroups
    /// right away: closing or reopening, a plate marked here, or one merged in from a
    /// collaborator or Siri. Reading managed objects in `body` doesn't subscribe to them, and
    /// the fetch only republishes inserts, deletes and moves (#65).
    @State private var listRevision = 0

    @State private var navigationPath = NavigationPath()
    @State private var newlyCreatedTrip: Trip?
    @State private var isPulsing = false
    @State private var tripToDelete: Trip?
    @State private var showingDeleteAlert = false
    @State private var tripToLeave: Trip?
    @State private var showingLeaveAlert = false
    @State private var leaveError: String?
    @State private var leftTripName: String?
    @State private var whatsNewCard: Announcement?
    @State private var searchText = ""

    /// Search appears once there's enough history to need it. Counted over all trips, not
    /// the search results, so the field can't vanish while you type (#65).
    private var showsSearch: Bool { trips.lazy.filter(\.isClosed).count > 5 }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            tripList
                .alert("Delete Trip", isPresented: $showingDeleteAlert, presenting: tripToDelete) { trip in
                    Button("Delete", role: .destructive) {
                        TripLifecycle.delete(trip, in: viewContext)
                        tripToDelete = nil
                    }
                    Button("Cancel", role: .cancel) {
                        tripToDelete = nil
                    }
                } message: { _ in
                    Text("Are you sure you want to delete this trip? This cannot be undone.")
                }
                .alert("Leave Trip", isPresented: $showingLeaveAlert, presenting: tripToLeave) { trip in
                    Button("Leave", role: .destructive) {
                        let name = trip.name
                        Task {
                            do {
                                try await persistenceController.leaveSharedTrip(trip)
                                confirmLeft(name)
                            } catch {
                                leaveError = "Couldn't leave the trip: \(error.localizedDescription)"
                            }
                            tripToLeave = nil
                        }
                    }
                    Button("Cancel", role: .cancel) { tripToLeave = nil }
                } message: { _ in
                    Text("You'll be removed from this shared trip. It stays available for everyone else.")
                }
                .alert(
                    "Couldn't Leave",
                    isPresented: Binding(
                        get: { leaveError != nil },
                        set: { if !$0 { leaveError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { leaveError = nil }
                } message: {
                    if let leaveError {
                        Text(leaveError)
                    }
                }
                .alert(
                    "Share Error",
                    isPresented: Binding(
                        get: { persistenceController.shareAcceptanceError != nil },
                        set: { if !$0 { persistenceController.shareAcceptanceError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) {
                        persistenceController.shareAcceptanceError = nil
                    }
                } message: {
                    if let error = persistenceController.shareAcceptanceError {
                        Text(error)
                    }
                }
        }
    }

    private var tripList: some View {
        _ = listRevision // Read so a bump re-runs this body; see `listRevision`.
        let sections = TripListSections(trips: trips, matching: searchText)
        return List {
            if !searchText.isEmpty {
                // A search result isn't "current": show every matching open trip as a plain
                // row rather than promoting the first match to the hero card.
                let openMatches = (sections.hero.map { [$0] } ?? []) + sections.otherOpen
                if !openMatches.isEmpty {
                    Section {
                        ForEach(openMatches) { trip in tripRow(trip) }
                    }
                }
            } else if let hero = sections.hero {
                Section {
                    // A plain button rather than a NavigationLink: in a List, a link adds a
                    // disclosure chevron, which doesn't belong on a card.
                    Button {
                        navigationPath.append(hero.objectID)
                    } label: {
                        TripHeroCard(trip: hero, isShared: isShared(hero))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .contextMenu { tripMenu(hero) }
                } header: {
                    Text("Current").bold()
                }
            } else if !trips.isEmpty {
                Section {
                    noTripInProgressRow
                } header: {
                    Text("Current").bold()
                }
            }
            if searchText.isEmpty, !sections.otherOpen.isEmpty {
                Section {
                    ForEach(sections.otherOpen) { trip in tripRow(trip) }
                }
            }
            ForEach(Array(sections.pastYears.enumerated()), id: \.element.id) { index, pastYear in
                Section {
                    ForEach(pastYear.trips) { trip in tripRow(trip) }
                } header: {
                    pastHeader(year: pastYear.year, isFirst: index == 0)
                }
            }
        }
        .listStyle(.insetGrouped)
        .tripSearch(text: $searchText, enabled: showsSearch)
        .onChange(of: showsSearch) { _, enabled in
            if !enabled { searchText = "" }
        }
        .navigationTitle("Road Trips")
        .navigationDestination(for: NSManagedObjectID.self) { objectID in
            if let trip = viewContext.object(with: objectID) as? Trip {
                TripDetailView(
                    trip: trip,
                    isNewTrip: objectID == newlyCreatedTrip?.objectID,
                    onLeave: { name in
                        navigationPath = NavigationPath()
                        confirmLeft(name)
                    },
                    onDelete: deleteAfterPop
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addTrip) {
                    Label("Add Trip", systemImage: "plus")
                }
                .symbolEffect(.pulse, isActive: isPulsing)
            }
        }
        .overlay {
            if trips.isEmpty {
                ContentUnavailableView {
                    Label("No Trips", systemImage: "car.fill")
                } description: {
                    Text("Start tracking your road trip games by creating your first trip.")
                } actions: {
                    Button("Create Trip", action: addTrip)
                }
            } else if !searchText.isEmpty, sections.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .overlay(alignment: .bottom) {
            if let leftTripName {
                Text("You left \(leftTripName)")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: leftTripName) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { self.leftTripName = nil }
                    }
            }
        }
        .animation(.spring, value: leftTripName)
        .onAppear {
            isPulsing = trips.isEmpty
            presentWhatsNewIfDue()
        }
        .sheet(item: $whatsNewCard) { card in
            WhatsNewSheet(announcement: card)
        }
        .onChange(of: trips.count) { _, newCount in
            isPulsing = newCount == 0
        }
        .onChange(of: IntentRoute.shared.pendingTrip, initial: true) { _, _ in
            guard let objectID = IntentRoute.shared.take() else { return }
            navigationPath = NavigationPath()
            navigationPath.append(objectID)
        }
        .task(id: trips.map(\.name)) {
            // Keeps trip-name phrases ("Who's winning Utah…") current; debounced so a rename doesn't refresh per keystroke.
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            TripSpotterShortcuts.updateAppShortcutParameters()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)
        ) { note in
            if changesTripOrSighting(note) { listRevision &+= 1 }
        }
    }

    /// Whether the change touched what the list ranks by: a trip itself or its plate sightings (#65).
    private func changesTripOrSighting(_ note: Notification) -> Bool {
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]
        return keys.contains { key in
            guard let objects = note.userInfo?[key] as? Set<NSManagedObject> else { return false }
            return objects.contains { $0 is Trip || $0 is PlateSighting }
        }
    }

    private func tripRow(_ trip: Trip) -> some View {
        NavigationLink(value: trip.objectID) {
            TripRow(trip: trip, isShared: isShared(trip))
        }
        // No full swipe: closing ends marking for everyone, so it takes a deliberate tap,
        // not a swipe that overshoots in a moving car.
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if persistenceController.isOwner(of: trip) {
                closeButton(trip)
                    .tint(trip.isClosed ? Theme.green : .gray)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Red by tint, not `role: .destructive`: a destructive swipe makes List animate
            // the row away at once, before the confirmation alert is answered.
            if persistenceController.isOwner(of: trip) {
                Button { confirmDelete(trip) } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            } else {
                Button { confirmLeave(trip) } label: {
                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .tint(.red)
            }
        }
        .contextMenu { tripMenu(trip) }
    }

    /// Close or reopen, shared by the leading swipe and the long-press menu (#65).
    private func closeButton(_ trip: Trip) -> some View {
        Button {
            withAnimation {
                TripLifecycle.setClosed(!trip.isClosed, for: trip, in: viewContext)
            }
        } label: {
            Label(
                trip.isClosed ? "Reopen Trip" : "Close Trip",
                systemImage: trip.isClosed ? "lock.open" : "lock"
            )
        }
    }

    /// The same actions as the swipes and the trip screen; destructive last (HIG) (#65).
    @ViewBuilder
    private func tripMenu(_ trip: Trip) -> some View {
        if persistenceController.isOwner(of: trip) {
            closeButton(trip)
            Divider()
            Button(role: .destructive) { confirmDelete(trip) } label: {
                Label("Delete Trip", systemImage: "trash")
            }
        } else {
            Button(role: .destructive) { confirmLeave(trip) } label: {
                Label("Leave Trip", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    private func confirmDelete(_ trip: Trip) {
        tripToDelete = trip
        showingDeleteAlert = true
    }

    private func confirmLeave(_ trip: Trip) {
        tripToLeave = trip
        showingLeaveAlert = true
    }

    /// Shared when someone else is on it, or when it's someone else's trip you joined.
    private func isShared(_ trip: Trip) -> Bool {
        trip.participantCount > 1 || !persistenceController.isOwner(of: trip)
    }

    private var noTripInProgressRow: some View {
        HStack {
            Text("No trip in progress")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Start a Trip", action: addTrip)
                .bold()
        }
    }

    /// The first past year carries the "Past Trips" title above its year.
    @ViewBuilder
    private func pastHeader(year: Int, isFirst: Bool) -> some View {
        let yearText = Text(year, format: .number.grouping(.never))
        if isFirst {
            VStack(alignment: .leading, spacing: 6) {
                Text("Past Trips").bold()
                yearText
            }
        } else {
            yearText
        }
    }

    private func addTrip() {
        let newTrip = Trip(context: viewContext, name: "New Trip")
        if let store = persistenceController.privatePersistentStore {
            viewContext.assign(newTrip, to: store)
        }
        viewContext.save(contextInfo: "addTrip")
        newlyCreatedTrip = newTrip
        navigationPath.append(newTrip.objectID)
    }

    private func confirmLeft(_ name: String) {
        withAnimation { leftTripName = name }
    }

    /// Deletes a trip its own screen asked to delete, once that screen is gone (#65).
    private func deleteAfterPop(_ objectID: NSManagedObjectID) {
        navigationPath = NavigationPath()
        Task {
            // Lets the pop animation finish before the trip disappears under it.
            try? await Task.sleep(for: .milliseconds(600))
            guard let trip = try? viewContext.existingObject(with: objectID) as? Trip else { return }
            TripLifecycle.delete(trip, in: viewContext)
        }
    }

    /// Shows the next what's-new card when the trip list is on screen with nothing
    /// else over it; otherwise it waits for the list's next appearance.
    private func presentWhatsNewIfDue() {
        guard whatsNewCard == nil, navigationPath.isEmpty,
              IntentRoute.shared.pendingTrip == nil,
              !showingDeleteAlert, !showingLeaveAlert, leaveError == nil,
              persistenceController.shareAcceptanceError == nil else { return }
        whatsNewCard = WhatsNew.next(seen: WhatsNewStore.seen, hasTrips: !trips.isEmpty)
    }

}

private extension View {
    /// Search only once there's enough history to need it (#65).
    @ViewBuilder
    func tripSearch(text: Binding<String>, enabled: Bool) -> some View {
        if enabled {
            searchable(text: text, prompt: "Search trips")
        } else {
            self
        }
    }
}
