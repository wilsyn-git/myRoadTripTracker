//
//  CloudSharingView.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/30/26.
//

import CloudKit
import CoreData
import SwiftData
import SwiftUI

/// Wraps UICloudSharingController for SwiftUI presentation.
/// Requires a pre-created CKShare — use CloudSharingSheet modifier which handles creation.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let tripName: String
    let onError: (String) -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(tripName: tripName, onError: onError, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let tripName: String
        let onError: (String) -> Void
        let onDismiss: () -> Void

        init(tripName: String, onError: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
            self.tripName = tripName
            self.onError = onError
            self.onDismiss = onDismiss
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            print("Failed to save share: \(error)")
            onError("Failed to share trip: \(error.localizedDescription)")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            tripName
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            print("Share saved successfully")
            onDismiss()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            print("Sharing stopped")
            onDismiss()
        }
    }
}

/// ViewModifier that creates/fetches a CKShare then presents the sharing sheet.
struct CloudSharingSheet: ViewModifier {
    let trip: Trip
    let persistenceController: PersistenceController
    @Binding var isPresented: Bool
    @State private var activeShare: CKShare?
    @State private var sharingError: String?
    @State private var showingError = false
    @State private var showingSheet = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, shouldPresent in
                guard shouldPresent else { return }
                Task {
                    await prepareShare()
                }
            }
            .sheet(isPresented: $showingSheet, onDismiss: { isPresented = false }) {
                if let share = activeShare {
                    CloudSharingView(
                        share: share,
                        container: CKContainer(identifier: PersistenceController.cloudKitContainerID),
                        tripName: trip.name,
                        onError: { error in
                            sharingError = error
                            showingSheet = false
                            showingError = true
                        },
                        onDismiss: {
                            showingSheet = false
                        }
                    )
                }
            }
            .alert("Sharing Unavailable", isPresented: $showingError) {
                Button("OK") { sharingError = nil }
            } message: {
                Text(sharingError ?? "Unable to share this trip. Please make sure you're signed into iCloud and try again.")
            }
    }

    @MainActor
    private func prepareShare() async {
        // Check for existing share first
        if let existing = persistenceController.fetchShare(for: trip) {
            activeShare = existing
            showingSheet = true
            return
        }
        // Create a new share
        do {
            let (share, _) = try await persistenceController.shareTrip(trip)
            activeShare = share
            showingSheet = true
        } catch {
            isPresented = false
            sharingError = error.localizedDescription
            showingError = true
        }
    }
}

extension View {
    func cloudSharingSheet(for trip: Trip, persistenceController: PersistenceController, isPresented: Binding<Bool>) -> some View {
        modifier(CloudSharingSheet(trip: trip, persistenceController: persistenceController, isPresented: isPresented))
    }
}
