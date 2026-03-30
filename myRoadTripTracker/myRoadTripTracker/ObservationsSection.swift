//
//  ObservationsSection.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import SwiftUI
import SwiftData

struct ObservationsSection: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    
    private let predefinedCategories = [
        "Weirdest thing we've seen",
        "Coolest car",
        "Funniest billboard",
        "Weirdest billboard",
        "Best roadside attraction",
        "Most interesting license plate",
    ]
    
    var body: some View {
        Section {
            ForEach(allCategories, id: \.self) { category in
                ObservationRow(trip: trip, category: category)
            }
            
            Button {
                showingAddCategory = true
            } label: {
                Label("Add Custom Category", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Road Trip Observations")
        }
        .alert("Add Custom Category", isPresented: $showingAddCategory) {
            TextField("Category name", text: $newCategoryName)
            Button("Cancel", role: .cancel) {
                newCategoryName = ""
            }
            Button("Add") {
                addCustomCategory()
            }
        }
    }
    
    private var allCategories: [String] {
        let existingCategories = trip.observations.map { $0.category }
        var categories = predefinedCategories
        
        // Add custom categories that aren't in predefined list
        let customCategories = existingCategories.filter { !predefinedCategories.contains($0) }
        categories.append(contentsOf: customCategories)
        
        return categories
    }
    
    private func addCustomCategory() {
        guard !newCategoryName.isEmpty else { return }
        
        let observation = TripObservation(category: newCategoryName, response: "")
        observation.trip = trip
        trip.observations.append(observation)
        modelContext.insert(observation)
        
        newCategoryName = ""
    }
}