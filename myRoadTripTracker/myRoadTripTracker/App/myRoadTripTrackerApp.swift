import CloudKit
import CoreData
import SwiftUI

@main
struct myRoadTripTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var persistenceController = PersistenceController.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        PlateRegion.assertMatchesLocations()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let error = persistenceController.setupError {
                    ContentUnavailableView {
                        Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                } else if hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .task {
                appDelegate.persistenceController = persistenceController
            }
            .task {
                // Keeps the cached iCloud user ID current, so opening a trip never waits on
                // CloudKit and a different iCloud account replaces the old ID (#36).
                await CloudKitUserHelper.refresh()
                for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                    CloudKitUserHelper.clearCache()
                    await CloudKitUserHelper.refresh()
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                // Pins for plates saved without a location fix (Siri marks, taps whose fix never came).
                guard phase == .active, persistenceController.setupError == nil else { return }
                Task { await PinBackfill.run(in: persistenceController.viewContext) }
            }
        }
        .environment(\.managedObjectContext, persistenceController.viewContext)
        .environment(persistenceController)
    }
}
