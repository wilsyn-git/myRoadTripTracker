import SwiftUI
import CoreData

struct ParticipantsView: View {
    @ObservedObject var trip: Trip
    let isOwner: Bool
    let currentUserID: String
    let onLeave: (String) -> Void
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PersistenceController.self) private var persistenceController
    @State private var leaveError: String?

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
                                leaveTrip()
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
        }
    }

    private func removeParticipant(_ participant: TripParticipant) {
        viewContext.delete(participant)
        viewContext.save(contextInfo: "removeParticipant")
    }

    private func leaveTrip() {
        let name = trip.name
        Task {
            do {
                try await persistenceController.leaveSharedTrip(trip)
                dismiss()
                onLeave(name)
            } catch {
                leaveError = "Couldn't leave the trip: \(error.localizedDescription)"
            }
        }
    }
}
