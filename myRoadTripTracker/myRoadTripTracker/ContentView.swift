//
//  ContentView.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.createdDate, order: .reverse) private var trips: [Trip]
    @State private var navigationPath = NavigationPath()
    @State private var newlyCreatedTrip: Trip?
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                ForEach(trips) { trip in
                    NavigationLink(value: trip) {
                        TripRowView(trip: trip)
                    }
                }
                .onDelete(perform: deleteTrips)
            }
            .navigationTitle("Road Trips")
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip, isNewTrip: trip.persistentModelID == newlyCreatedTrip?.persistentModelID)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addTrip) {
                        Label("Add Trip", systemImage: "plus")
                    }
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
        }
    }
    
    private func addTrip() {
        let newTrip = Trip()
        modelContext.insert(newTrip)
        newlyCreatedTrip = newTrip
        navigationPath.append(newTrip)
    }
    
    private func deleteTrips(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(trips[index])
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Trip.self, inMemory: true)
}
