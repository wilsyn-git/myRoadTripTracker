//
//  TripObservation.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import Foundation
import SwiftData

@Model
final class TripObservation {
    var category: String
    var response: String
    var trip: Trip?
    
    init(category: String, response: String = "") {
        self.category = category
        self.response = response
    }
}
