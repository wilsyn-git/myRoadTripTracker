import SwiftUI
import CoreData

@main
struct myRoadTripTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var persistenceController = PersistenceController.shared

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
        .environment(\.managedObjectContext, persistenceController.viewContext)
        .environment(persistenceController)
    }
}
