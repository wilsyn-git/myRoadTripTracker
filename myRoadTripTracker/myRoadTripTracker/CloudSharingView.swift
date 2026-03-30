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

/// A SwiftUI wrapper around UICloudSharingController for sharing Trip objects
/// via CloudKit. Uses the underlying Core Data stack that SwiftData provides
/// when configured with `cloudKitDatabase: .automatic`.
struct CloudSharingView: UIViewControllerRepresentable {
    let trip: Trip
    let modelContainer: ModelContainer

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let container = CKContainer(identifier: "iCloud.com.tentenbits.myRoadTripTracker")

        // Try to get the existing CKShare for this trip via the Core Data stack
        let persistentContainer = findPersistentCloudKitContainer()
        let existingShare = fetchExistingShare(persistentContainer: persistentContainer)

        let controller: UICloudSharingController

        if let existingShare {
            controller = UICloudSharingController(share: existingShare, container: container)
        } else {
            controller = UICloudSharingController { sharingController, preparationCompletion in
                self.createShare(
                    persistentContainer: persistentContainer,
                    ckContainer: container,
                    completion: preparationCompletion
                )
            }
        }

        controller.availablePermissions = [.allowReadWrite]
        controller.delegate = context.coordinator

        return controller
    }

    func updateUIViewController(
        _ uiViewController: UICloudSharingController,
        context: Context
    ) {}

    // MARK: - Core Data / CloudKit bridge

    /// Finds the NSPersistentCloudKitContainer backing SwiftData's ModelContainer.
    /// SwiftData uses an NSPersistentCloudKitContainer under the hood when
    /// cloudKitDatabase is set to .automatic.
    private func findPersistentCloudKitContainer() -> NSPersistentCloudKitContainer? {
        // SwiftData doesn't expose the persistent container directly.
        // We create a mirror approach: set up an NSPersistentCloudKitContainer
        // that uses the same store URL as the SwiftData container.
        guard let storeURL = modelContainer.configurations.first?.url else {
            return nil
        }

        let container = NSPersistentCloudKitContainer(name: "myRoadTripTracker")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.tentenbits.myRoadTripTracker"
        )
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }

        if let loadError {
            print("Failed to load persistent stores: \(loadError)")
            return nil
        }

        return container
    }

    /// Fetches an existing CKShare for the trip if one has already been created.
    private func fetchExistingShare(
        persistentContainer: NSPersistentCloudKitContainer?
    ) -> CKShare? {
        guard let persistentContainer,
              let managedObject = fetchManagedObject(in: persistentContainer)
        else {
            return nil
        }

        do {
            let shares = try persistentContainer.fetchShares(matching: [managedObject.objectID])
            return shares[managedObject.objectID]
        } catch {
            print("Failed to fetch existing shares: \(error)")
            return nil
        }
    }

    /// Creates a new CKShare for the trip.
    private func createShare(
        persistentContainer: NSPersistentCloudKitContainer?,
        ckContainer: CKContainer,
        completion: @escaping (CKShare?, CKContainer?, Error?) -> Void
    ) {
        guard let persistentContainer,
              let managedObject = fetchManagedObject(in: persistentContainer)
        else {
            completion(nil, nil, ShareError.tripNotFound)
            return
        }

        persistentContainer.share(
            [managedObject],
            to: nil
        ) { objectIDs, share, container, error in
            if let error {
                completion(nil, nil, error)
                return
            }

            if let share {
                share[CKShare.SystemFieldKey.title] = self.trip.name as CKRecordValue
                completion(share, ckContainer, nil)
            } else {
                completion(nil, nil, ShareError.shareCreationFailed)
            }
        }
    }

    /// Finds the NSManagedObject corresponding to the Trip in the Core Data stack.
    private func fetchManagedObject(
        in container: NSPersistentCloudKitContainer
    ) -> NSManagedObject? {
        let context = container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Trip")
        fetchRequest.predicate = NSPredicate(
            format: "name == %@ AND createdDate == %@",
            trip.name as NSString,
            trip.createdDate as NSDate
        )
        fetchRequest.fetchLimit = 1

        do {
            return try context.fetch(fetchRequest).first
        } catch {
            print("Failed to fetch managed object: \(error)")
            return nil
        }
    }

    enum ShareError: LocalizedError {
        case tripNotFound
        case shareCreationFailed

        var errorDescription: String? {
            switch self {
            case .tripNotFound:
                return "Could not find the trip in the CloudKit store."
            case .shareCreationFailed:
                return "Failed to create a share for this trip."
            }
        }
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            print("Failed to save share: \(error)")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            return "Road Trip"
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            print("Share saved successfully")
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            print("Sharing stopped")
            dismiss()
        }
    }
}
