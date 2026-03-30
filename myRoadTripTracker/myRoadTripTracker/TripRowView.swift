//
//  TripRowView.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import SwiftUI

struct TripRowView: View {
    let trip: Trip

    private var seenCount: Int { trip.plateSightings.count }
    private var totalCount: Int { Location.allLocations.count }
    private var percentage: Int {
        totalCount > 0 ? (seenCount * 100) / totalCount : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.name)
                .font(.headline)
            HStack(spacing: 0) {
                Text(trip.createdDate, style: .date)
                Text("  —  \(seenCount)/\(totalCount): \(percentage)%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
