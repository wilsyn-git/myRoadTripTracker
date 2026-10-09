import SwiftUI
import CoreData

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
            .onChange(of: scenePhase, initial: true) { _, phase in
                // Pins for voice marks Siri saved without a location fix.
                guard phase == .active, persistenceController.setupError == nil else { return }
                Task { await PinBackfill.run(in: persistenceController.viewContext) }
            }
        }
        .environment(\.managedObjectContext, persistenceController.viewContext)
        .environment(persistenceController)
    }
}
