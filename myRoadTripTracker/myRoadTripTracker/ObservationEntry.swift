//
//  ObservationEntry.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import Foundation
import SwiftData

@Model
final class ObservationEntry {
    var category: String
    var authorName: String
    var text: String
    var createdDate: Date
    var trip: Trip?

    init(category: String, authorName: String, text: String, createdDate: Date = .now) {
        self.category = category
        self.authorName = authorName
        self.text = text
        self.createdDate = createdDate
    }
}
