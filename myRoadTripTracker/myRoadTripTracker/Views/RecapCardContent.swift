import SwiftUI

/// The visual recap card. Pure layout over precomputed inputs so it can be both
/// displayed and rasterized for sharing.
struct RecapCardContent: View {
    let tripName: String
    let stats: RecapStats
    let narrative: String
    let mapImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tripName)
                .font(.largeTitle).bold()

            Text(narrative)
                .font(.body)

            if let mapImage {
                Image(uiImage: mapImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 12))
            }

            HStack(spacing: 24) {
                statBlock(value: "\(stats.usSeenCount)/\(stats.usTotalCount)", label: "US")
                statBlock(value: "\(stats.caSeenCount)/\(stats.caTotalCount)", label: "Canada")
                if stats.dayCount > 0 {
                    statBlock(value: "\(stats.dayCount)", label: stats.dayCount == 1 ? "Day" : "Days")
                }
            }

            if let mvp = stats.mvp {
                Label("MVP: \(mvp.name) (\(mvp.count))", systemImage: "trophy.fill")
                    .font(.headline)
            }
            if !stats.rareCatches.isEmpty {
                Label("Rare: \(stats.rareCatches.joined(separator: ", "))", systemImage: "star.fill")
                    .font(.subheadline)
            }
            if stats.observationCount > 0 {
                Label("\(stats.observationCount) note\(stats.observationCount == 1 ? "" : "s"), \(stats.observationsWithPhoto) with photos",
                      systemImage: "text.bubble.fill")
                    .font(.subheadline)
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel(), in: RoundedRectangle(cornerRadius: 20))
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2).bold()
            Text(label).font(.caption).foregroundStyle(Theme.panelSecondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}
