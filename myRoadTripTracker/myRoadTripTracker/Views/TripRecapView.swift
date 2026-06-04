import SwiftUI
import CoreData

/// The visual recap card. Pure layout over precomputed inputs so it can be both
/// displayed and rasterized for sharing.
struct RecapCardContent: View {
    let tripName: String
    let stats: RecapStats
    let narrative: String
    let mapImage: UIImage?

    private var cardColor: Color { Color(red: 0.2, green: 0.65, blue: 0.35) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tripName)
                .font(.largeTitle).fontWeight(.bold)

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
        .background(cardColor.gradient, in: RoundedRectangle(cornerRadius: 20))
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2).fontWeight(.bold)
            Text(label).font(.caption).opacity(0.85)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TripRecapView: View {
    @ObservedObject var trip: Trip
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var stats: RecapStats?
    @State private var narrative: String = ""
    @State private var mapImage: UIImage?
    @State private var shareImage: Image?
    @State private var shareText: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if let stats {
                    if stats.isEmpty {
                        ContentUnavailableView {
                            Label("Nothing to Recap Yet", systemImage: "sparkles")
                        } description: {
                            Text("Spot some plates or add notes, and your trip recap will appear here.")
                        }
                    } else {
                        ScrollView {
                            RecapCardContent(tripName: trip.name, stats: stats,
                                             narrative: narrative, mapImage: mapImage)
                                .padding()
                        }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Trip Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let shareImage {
                        ShareLink(item: shareImage,
                                  preview: SharePreview("Trip Recap", image: shareImage)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    } else if !shareText.isEmpty {
                        ShareLink(item: shareText) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task { await load() }
        }
    }

    @MainActor
    private func load() async {
        let computed = RecapStats(trip: trip)
        stats = computed
        guard !computed.isEmpty else { return }
        markRecapViewed()

        narrative = trip.recapNarrative ?? computed.templateNarrative(tripName: trip.name)
        shareText = "\(trip.name)\n\(narrative)"

        let snapshot = await RecapMapRenderer.snapshot(
            for: trip.plateSightingsArray,
            size: CGSize(width: 600, height: 360)
        )
        mapImage = snapshot
        renderShareImage(stats: computed)
    }

    @MainActor
    private func renderShareImage(stats: RecapStats) {
        let card = RecapCardContent(tripName: trip.name, stats: stats,
                                    narrative: narrative, mapImage: mapImage)
            .frame(width: 360)
        let renderer = ImageRenderer(content: card)
        renderer.scale = displayScale
        if let ui = renderer.uiImage {
            shareImage = Image(uiImage: ui)
        }
    }

    private func markRecapViewed() {
        guard let tripID = trip.tripID?.uuidString else { return }
        UserDefaults.standard.set(Date(), forKey: "lastViewedRecap_\(tripID)")
    }
}
