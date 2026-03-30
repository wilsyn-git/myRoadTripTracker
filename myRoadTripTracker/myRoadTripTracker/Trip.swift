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
    var name: String = "New Trip"
    var createdDate: Date = Date.now
    var isClosed: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \PlateSighting.trip)
    var _plateSightings: [PlateSighting]? = []

    @Relationship(deleteRule: .cascade, inverse: \ObservationEntry.trip)
    var _observationEntries: [ObservationEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \TripParticipant.trip)
    var _participants: [TripParticipant]? = []

    var plateSightings: [PlateSighting] {
        get { _plateSightings ?? [] }
        set { _plateSightings = newValue }
    }

    var observationEntries: [ObservationEntry] {
        get { _observationEntries ?? [] }
        set { _observationEntries = newValue }
    }

    var participants: [TripParticipant] {
        get { _participants ?? [] }
        set { _participants = newValue }
    }

    init(name: String = "New Trip", createdDate: Date = .now) {
        self.name = name
        self.createdDate = createdDate
        self.isClosed = false
    }
}
