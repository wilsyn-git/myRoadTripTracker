import SwiftUI

/// The gold "1ST" capsule on a plate this trip saw before any other trip did (#78).
struct FirstEverBadge: View {
    var body: some View {
        Text("1ST")
            .font(.system(.caption, design: .rounded, weight: .heavy))
            // Dark brown on gold, about 9:1; white on gold is under 2:1.
            .foregroundStyle(Color(red: 0.23, green: 0.15, blue: 0))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                LinearGradient(colors: [Theme.gold, Theme.amber], startPoint: .top, endPoint: .bottom),
                in: .capsule
            )
            .accessibilityHidden(true)
    }
}
