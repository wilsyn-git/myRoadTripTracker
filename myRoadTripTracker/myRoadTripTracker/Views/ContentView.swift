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

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Trip.isClosed, ascending: true),
            NSSortDescriptor(keyPath: \Trip.createdDate, ascending: false)
        ],
        animation: .default
    )
    private var trips: FetchedResults<Trip>

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

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            tripList
                .alert("Delete Trip", isPresented: $showingDeleteAlert, presenting: tripToDelete) { trip in
                    Button("Delete", role: .destructive) {
                        viewContext.delete(trip)
                        viewContext.save(contextInfo: "deleteTrip")
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
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(trips) { trip in
                    NavigationLink(value: trip.objectID) {
                        TripCardView(trip: trip)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if persistenceController.isOwner(of: trip) {
                            Button(role: .destructive) {
                                tripToDelete = trip
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete Trip", systemImage: "trash")
                            }
                        } else {
                            Button(role: .destructive) {
                                tripToLeave = trip
                                showingLeaveAlert = true
                            } label: {
                                Label("Leave Trip", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        }
                    }
                }
            }
            .padding()
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
                    }
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
