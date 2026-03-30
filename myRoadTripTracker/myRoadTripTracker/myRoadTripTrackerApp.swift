import SwiftUI
import SwiftData

@main
struct myRoadTripTrackerApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            Trip.self,
            PlateSighting.self,
            ObservationEntry.self,
            TripParticipant.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView()
            }
        }
        .modelContainer(modelContainer)
    }
}
