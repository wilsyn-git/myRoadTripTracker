//
//  Trip.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import Foundation
import SwiftData

@Model
final class Trip {
    var name: String
    var createdDate: Date
    
    @Relationship(deleteRule: .cascade, inverse: \PlateSighting.trip)
    var plateSightings: [PlateSighting] = []
    
    @Relationship(deleteRule: .cascade, inverse: \ObservationEntry.trip)
    var observationEntries: [ObservationEntry] = []

    var isClosed: Bool

    init(name: String = "New Trip", createdDate: Date = .now) {
        self.name = name
        self.createdDate = createdDate
        self.isClosed = false
    }
}
