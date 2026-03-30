//
//  ObservationRow.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import SwiftUI
import SwiftData

struct ObservationEntryRow: View {
    let entry: ObservationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.authorName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(entry.createdDate, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.text)
                .font(.body)
        }
        .padding(.vertical, 2)
    }
}
