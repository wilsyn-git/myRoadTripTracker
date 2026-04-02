import UIKit
import CloudKit

class AppDelegate: NSObject, UIApplicationDelegate {
    var persistenceController: PersistenceController?

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
        Task { @MainActor in
            await getPersistenceController()?.acceptShareAndImport(metadata: cloudKitShareMetadata)
        }
    }

    /// Called when the app is launched by tapping a share URL (app was not running).
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shareMetadata = connectionOptions.cloudKitShareMetadata {
            Task { @MainActor in
                await getPersistenceController()?.acceptShareAndImport(metadata: shareMetadata)
            }
        }
    }

    @MainActor
    private func getPersistenceController() -> PersistenceController? {
        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        return appDelegate?.persistenceController
    }
}
