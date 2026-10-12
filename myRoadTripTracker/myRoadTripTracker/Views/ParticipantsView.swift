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
    @State private var removeError: String?
    /// Participants whose access is being revoked; their rows show a spinner meanwhile.
    @State private var removingIDs: Set<NSManagedObjectID> = []

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
                            // No fallback to `Date()`: an unknown join date must not render as today.
                            if let joined = participant.joinedDate {
                                Text("Joined \(joined, style: .date)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if removingIDs.contains(participant.objectID) {
                            ProgressView()
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if isOwner && participant.cloudKitUserID != currentUserID
                            && !removingIDs.contains(participant.objectID) {
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
            .alert(
                "Couldn't Remove",
                isPresented: Binding(
                    get: { removeError != nil },
                    set: { if !$0 { removeError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { removeError = nil }
            } message: {
                if let removeError {
                    Text(removeError)
                }
            }
        }
    }

    /// Takes the person off the trip's CloudKit share first, so they lose access (#30), then
    /// deletes their row. If the revoke fails, the row stays, so the list never shows someone
    /// as gone while they can still open the trip.
    private func removeParticipant(_ participant: TripParticipant) {
        let objectID = participant.objectID
        let userID = participant.cloudKitUserID
        removingIDs.insert(objectID)
        Task {
            defer { removingIDs.remove(objectID) }
            do {
                try await persistenceController.revokeAccess(to: trip, forUserID: userID)
            } catch {
                removeError = "Couldn't remove \(participant.displayName): \(error.localizedDescription)"
                return
            }
            guard !participant.isDeleted, participant.managedObjectContext != nil else { return }
            viewContext.delete(participant)
            viewContext.save(contextInfo: "removeParticipant")
        }
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
