import Foundation

/// One participant's plate count, for the recap leaderboard.
struct SpotterTally: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}
