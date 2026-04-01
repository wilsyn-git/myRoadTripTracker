import SwiftUI
import SwiftData
import CloudKit

@main
struct myRoadTripTrackerApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @StateObject private var persistenceController = PersistenceController()

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView()
            }
        }
        .modelContainer(persistenceController.modelContainer)
        .environmentObject(persistenceController)
        .onOpenURL { url in
            // Handle incoming CloudKit share URLs
            // The system will deliver CKShare.Metadata via userDidAcceptCloudKitShareWith
        }
    }
}
