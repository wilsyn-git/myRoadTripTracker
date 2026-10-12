import SwiftUI

/// The app's brand colors, kept in one place so screens stay consistent.
enum Theme {
    /// Open trip panels, the recap card, Siri cards and what's-new accents. Dark enough
    /// that white text on it is 5.7:1; the HIG minimum is 4.5:1 (#65).
    static let green = Color(red: 0.11, green: 0.46, blue: 0.24)
    /// A closed trip's Siri card.
    static let closedGray = Color(white: 0.38)
    /// Secondary text on a `panel`. Plain `.secondary` is too faint there: white at 0.6
    /// on `green` is 3.1:1, at 0.9 it's 5.1:1 (#65).
    static let panelSecondaryText = Color.white.opacity(0.9)
    /// The two ends of the plate progress bars; also the reveal confetti.
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let gold = Color(red: 0.98, green: 0.75, blue: 0.15)

    /// The background behind white text: the base color at the top, darkening toward the
    /// bottom. SwiftUI's `.gradient` lightens the top instead, which took white text on
    /// the old green down to about 2:1 (#65).
    static func panel(closed: Bool = false) -> LinearGradient {
        let base = closed ? closedGray : green
        return LinearGradient(
            colors: [base, base.mix(with: .black, by: 0.2)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
