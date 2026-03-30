import Foundation
import SwiftData

@Model
final class TripParticipant {
    var displayName: String
    var cloudKitUserID: String
    var joinedDate: Date
    var trip: Trip?

    init(displayName: String, cloudKitUserID: String, joinedDate: Date = .now) {
        self.displayName = displayName
        self.cloudKitUserID = cloudKitUserID
        self.joinedDate = joinedDate
    }
}
