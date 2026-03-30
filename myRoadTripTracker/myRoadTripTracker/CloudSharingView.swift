//
//  CloudSharingView.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/30/26.
//

import CloudKit
import SwiftData
import SwiftUI

/// Presents the system CloudKit sharing UI for a Trip.
/// Falls back to an error message if CloudKit is not available.
struct CloudSharingSheet: ViewModifier {
    let trip: Trip
    @Binding var isPresented: Bool
    @State private var sharingError: String?
    @State private var showingError = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                CloudSharingAttemptView(
                    trip: trip,
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

/// Attempts to present UICloudSharingController, handling failures gracefully.
struct CloudSharingAttemptView: UIViewControllerRepresentable {
    let trip: Trip
    let onError: (String) -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let container = CKContainer(identifier: "iCloud.com.tentenbits.myRoadTripTracker")

        let controller = UICloudSharingController { sharingController, preparationCompletion in
            let privateDB = container.privateCloudDatabase

            // Create a new CKRecord zone for sharing
            let zone = CKRecordZone(zoneName: "com.apple.coredata.cloudkit.zone")
            let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zone.zoneID)
            let record = CKRecord(recordType: "CD_Trip", recordID: recordID)
            record["CD_name"] = self.trip.name as CKRecordValue

            let share = CKShare(rootRecord: record)
            share[CKShare.SystemFieldKey.title] = self.trip.name as CKRecordValue
            share.publicPermission = .none

            let operation = CKModifyRecordsOperation(
                recordsToSave: [record, share],
                recordIDsToDelete: nil
            )
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    preparationCompletion(share, container, nil)
                case .failure(let error):
                    preparationCompletion(nil, nil, error)
                }
            }
            privateDB.add(operation)
        }

        controller.availablePermissions = [.allowReadWrite]
        controller.delegate = context.coordinator

        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onError: (String) -> Void
        let onDismiss: () -> Void

        init(onError: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
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
            return "Road Trip"
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

extension View {
    func cloudSharingSheet(for trip: Trip, isPresented: Binding<Bool>) -> some View {
        modifier(CloudSharingSheet(trip: trip, isPresented: isPresented))
    }
}
