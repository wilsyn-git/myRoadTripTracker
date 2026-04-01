import SwiftUI
import SwiftData
import CloudKit

@main
struct myRoadTripTrackerApp: App {
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
            .onOpenURL { url in
                // Handle incoming CloudKit share URLs
                // The system will deliver CKShare.Metadata via userDidAcceptCloudKitShareWith
            }
        }
        .modelContainer(persistenceController.modelContainer)
        .environment(persistenceController)
    }
}
