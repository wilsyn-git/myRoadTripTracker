import UIKit
import CloudKit

class AppDelegate: NSObject, UIApplicationDelegate {
    weak var persistenceController: PersistenceController?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    /// Called when the app is running or suspended and user taps a share URL.
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task {
            await acceptShare(cloudKitShareMetadata)
        }
    }

    /// Called when the app is launched by tapping a share URL (app was not running).
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shareMetadata = connectionOptions.cloudKitShareMetadata {
            Task {
                await acceptShare(shareMetadata)
            }
        }
    }

    @MainActor
    private func acceptShare(_ metadata: CKShare.Metadata) async {
        let container = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        // Only accept if we're a pending participant (not the owner)
        if metadata.participantRole != .owner && metadata.participantStatus == .pending {
            do {
                try await container.accept(metadata)
                print("[SceneDelegate] Share accepted successfully")
            } catch {
                print("[SceneDelegate] Failed to accept share: \(error)")
            }
        }
    }
}
