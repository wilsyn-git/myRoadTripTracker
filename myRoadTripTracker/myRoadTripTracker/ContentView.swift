//
//  ContentView.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(PersistenceController.self) private var persistenceController

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Trip.createdDate, ascending: false)],
        animation: .default
    )
    private var trips: FetchedResults<Trip>

    @State private var navigationPath = NavigationPath()
    @State private var newlyCreatedTrip: Trip?
    @State private var isPulsing = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                ForEach(trips) { trip in
                    NavigationLink(value: trip.objectID) {
                        TripRowView(trip: trip)
                    }
                }
                .onDelete(perform: deleteTrips)
            }
            .navigationTitle("Road Trips")
            .navigationDestination(for: NSManagedObjectID.self) { objectID in
                if let trip = viewContext.object(with: objectID) as? Trip {
                    TripDetailView(trip: trip, isNewTrip: objectID == newlyCreatedTrip?.objectID)
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
            .onAppear {
                isPulsing = trips.isEmpty
            }
            .onChange(of: trips.count) { _, newCount in
                isPulsing = newCount == 0
            }
        }
    }

    private func addTrip() {
        let newTrip = Trip(context: viewContext)
        if let store = persistenceController.privatePersistentStore {
            viewContext.assign(newTrip, to: store)
        }
        viewContext.save(contextInfo: "addTrip")
        newlyCreatedTrip = newTrip
        navigationPath.append(newTrip.objectID)
    }

    private func deleteTrips(at offsets: IndexSet) {
        for index in offsets {
            viewContext.delete(trips[index])
        }
        viewContext.save(contextInfo: "deleteTrips")
    }
}
