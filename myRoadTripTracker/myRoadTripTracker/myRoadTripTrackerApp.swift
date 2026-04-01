import SwiftUI
import SwiftData
import CloudKit

@main
struct myRoadTripTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var persistenceController = PersistenceController()

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .task {
                appDelegate.persistenceController = persistenceController
            }
        }
        .modelContainer(persistenceController.modelContainer)
        .environment(persistenceController)
    }
}
