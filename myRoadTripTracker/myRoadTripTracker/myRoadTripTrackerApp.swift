//
//  myRoadTripTrackerApp.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import SwiftUI
import SwiftData

@main
struct myRoadTripTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Trip.self, PlateSighting.self, ObservationEntry.self])
    }
}
