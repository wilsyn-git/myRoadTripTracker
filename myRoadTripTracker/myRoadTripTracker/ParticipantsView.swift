//
//  ParticipantsView.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/30/26.
//

import SwiftUI
import SwiftData

struct ParticipantsView: View {
    @Bindable var trip: Trip
    let isOwner: Bool
    let currentUserID: String
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(trip.participants.sorted(by: { $0.joinedDate < $1.joinedDate })) { participant in
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(participant.displayName)
                                    .font(.body)
                                if participant.cloudKitUserID == currentUserID {
                                    Text("(you)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("Joined \(participant.joinedDate, style: .date)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        if isOwner && participant.cloudKitUserID != currentUserID {
                            Button("Remove", role: .destructive) {
                                removeParticipant(participant)
                            }
                        }
                        if !isOwner && participant.cloudKitUserID == currentUserID {
                            Button("Leave", role: .destructive) {
                                leaveTrip(participant)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Participants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if trip.participants.isEmpty {
                    ContentUnavailableView {
                        Label("No Participants", systemImage: "person.2")
                    } description: {
                        Text("Share this trip to add participants.")
                    }
                }
            }
        }
    }

    private func removeParticipant(_ participant: TripParticipant) {
        if let index = trip.participants.firstIndex(of: participant) {
            trip.participants.remove(at: index)
        }
        modelContext.delete(participant)
    }

    private func leaveTrip(_ participant: TripParticipant) {
        removeParticipant(participant)
        dismiss()
    }
}
