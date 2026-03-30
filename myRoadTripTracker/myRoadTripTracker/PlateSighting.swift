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
    var locationCode: String // e.g., "CA", "NY", "BC"
    var locationName: String // e.g., "California", "New York", "British Columbia"
    var latitude: Double
    var longitude: Double
    var seenDate: Date
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
