import UIKit
import CloudKit

class AppDelegate: NSObject, UIApplicationDelegate {
    weak var persistenceController: PersistenceController?

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        guard let controller = persistenceController else {
            print("PersistenceController not available for share acceptance")
            return
        }
        controller.acceptShare(metadata: cloudKitShareMetadata)
    }
}
