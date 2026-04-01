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
/// Handles both new shares (invitation flow) and existing shares (management flow).
struct CloudSharingView: UIViewControllerRepresentable {
    enum Mode {
        /// Existing share — show management UI
        case manage(share: CKShare, container: CKContainer)
        /// New share — show invitation UI, create share when user picks contacts
        case invite(persistenceController: PersistenceController, trip: Trip)
    }

    let mode: Mode
    let tripName: String
    let onError: (String) -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(tripName: tripName, onError: onError, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller: UICloudSharingController

        switch mode {
        case .manage(let share, let container):
            controller = UICloudSharingController(share: share, container: container)

        case .invite(let persistenceController, let trip):
            // The preparation handler is deprecated in iOS 17, but Apple provides
            // no replacement for CloudKit/Core Data sharing. This is still the
            // correct API for presenting the invitation flow.
            controller = UICloudSharingController { _, preparationCompletion in
                Task { @MainActor in
                    do {
                        let (share, ckContainer) = try await persistenceController.shareTrip(trip)
                        preparationCompletion(share, ckContainer, nil)
                    } catch {
                        preparationCompletion(nil, nil, error)
                    }
                }
            }
        }

        controller.availablePermissions = [.allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

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

/// ViewModifier that presents the CloudKit sharing sheet.
/// New shares get the invitation flow; existing shares get the management flow.
struct CloudSharingSheet: ViewModifier {
    let trip: Trip
    let persistenceController: PersistenceController
    @Binding var isPresented: Bool
    @State private var sharingError: String?
    @State private var showingError = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                let existingShare = persistenceController.fetchShare(for: trip)
                let mode: CloudSharingView.Mode = if let existingShare {
                    .manage(
                        share: existingShare,
                        container: CKContainer(identifier: PersistenceController.cloudKitContainerID)
                    )
                } else {
                    .invite(persistenceController: persistenceController, trip: trip)
                }

                CloudSharingView(
                    mode: mode,
                    tripName: trip.name,
                    onError: { error in
                        sharingError = error
                        isPresented = false
                        showingError = true
                    },
                    onDismiss: {
                        isPresented = false
                    }
                )
            }
            .alert("Sharing Unavailable", isPresented: $showingError) {
                Button("OK") { sharingError = nil }
            } message: {
                Text(sharingError ?? "Unable to share this trip. Please make sure you're signed into iCloud and try again.")
            }
    }
}

extension View {
    func cloudSharingSheet(for trip: Trip, persistenceController: PersistenceController, isPresented: Binding<Bool>) -> some View {
        modifier(CloudSharingSheet(trip: trip, persistenceController: persistenceController, isPresented: isPresented))
    }
}
