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
    private var isShared: Bool { trip.participants.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trip.name)
                    .font(.headline)
                if trip.isClosed {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                if isShared {
                    HStack(spacing: 2) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text("\(trip.participants.count)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("^[\(trip.participants.count) participant](inflect: true)")
                }
            }
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
