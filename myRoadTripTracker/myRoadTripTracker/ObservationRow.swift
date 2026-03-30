//
//  ObservationRow.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import SwiftUI
import SwiftData

struct ObservationRow: View {
    @Bindable var trip: Trip
    let category: String
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isFocused: Bool
    @State private var responseText = ""

    private var observation: TripObservation? {
        trip.observations.first { $0.category == category }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Enter your observation...", text: $responseText, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
        }
        .padding(.vertical, 4)
        .onAppear {
            responseText = observation?.response ?? ""
        }
        .onChange(of: responseText) { _, newValue in
            if let existing = observation {
                existing.response = newValue
            } else if !newValue.isEmpty {
                let newObservation = TripObservation(category: category, response: newValue)
                newObservation.trip = trip
                trip.observations.append(newObservation)
                modelContext.insert(newObservation)
            }
        }
    }
}
