//
//  PlateSighting.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import Foundation
import SwiftData
import CoreLocation

@Model
final class PlateSighting {
    var locationCode: String = ""
    var locationName: String = ""
    var latitude: Double = 0.0
    var longitude: Double = 0.0
    var seenDate: Date = Date.now
    var trip: Trip?

    init(locationCode: String, locationName: String, latitude: Double, longitude: Double, seenDate: Date = .now) {
        self.locationCode = locationCode
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.seenDate = seenDate
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
