import SwiftUI

/// The app's brand colors, kept in one place so screens stay consistent.
enum Theme {
    /// Open trip cards, the recap card, Siri cards and what's-new accents.
    static let green = Color(red: 0.2, green: 0.65, blue: 0.35)
    /// A closed trip's card.
    static let closedGray = Color(white: 0.38)
    /// The two ends of the plate progress bars; also the reveal confetti.
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let gold = Color(red: 0.98, green: 0.75, blue: 0.15)
}
