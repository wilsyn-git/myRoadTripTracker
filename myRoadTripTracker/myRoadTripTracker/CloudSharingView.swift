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
struct CloudSharingView: UIViewControllerRepresentable {
    let trip: Trip
    let persistenceController: PersistenceController
    let onError: (String) -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(tripName: trip.name, onError: onError, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        // Check for existing share
        if let existingShare = persistenceController.fetchShare(for: trip) {
            let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
            let controller = UICloudSharingController(share: existingShare, container: ckContainer)
            controller.availablePermissions = [.allowReadWrite]
            controller.delegate = context.coordinator
            return controller
        }

        // No existing share — use preparation handler to create one
        let controller = UICloudSharingController { sharingController, preparationCompletion in
            Task { @MainActor in
                do {
                    let (share, container) = try await self.persistenceController.shareTrip(self.trip)
                    preparationCompletion(share, container, nil)
                } catch {
                    preparationCompletion(nil, nil, error)
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
struct CloudSharingSheet: ViewModifier {
    let trip: Trip
    let persistenceController: PersistenceController
    @Binding var isPresented: Bool
    @State private var sharingError: String?
    @State private var showingError = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                CloudSharingView(
                    trip: trip,
                    persistenceController: persistenceController,
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
