import SwiftUI

/// The trip list's way into Plate Passport. It shows the headline numbers, so you see the
/// collection grow without opening it (#78).
struct PassportRow: View {
    let history: PlateHistory
    /// Grows with the text, so the globe isn't clipped at accessibility sizes.
    @ScaledMetric(relativeTo: .title2) private var tileSize = 40.0

    var body: some View {
        let trips = history.trips.count
        HStack(spacing: 12) {
            Image(systemName: "globe.americas.fill")
                .font(.title2)
                // Dark on amber: white on this amber is about 2:1.
                .foregroundStyle(Color(white: 0.12))
                .frame(width: tileSize, height: tileSize)
                .background(Theme.amber, in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Plate Passport")
                    .font(.headline)
                Text("\(history.collected.count) of \(Location.allLocations.count) plates \u{00B7} \(trips) \(trips == 1 ? "trip" : "trips")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
