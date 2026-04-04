import SwiftUI
import CoreData

struct ParticipantsView: View {
    @ObservedObject var trip: Trip
    let isOwner: Bool
    let currentUserID: String
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(trip.participantsArray) { participant in
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
                            Text("Joined \(participant.joinedDate ?? Date(), style: .date)")
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
                if trip.participantsArray.isEmpty {
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
        viewContext.delete(participant)
        viewContext.save(contextInfo: "removeParticipant")
    }

    private func leaveTrip(_ participant: TripParticipant) {
        removeParticipant(participant)
        dismiss()
    }
}
