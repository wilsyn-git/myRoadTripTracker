import SwiftUI
import CoreData

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

        // Extract coordinates on the main actor (NSManagedObject reads) before handing
        // off to the off-actor snapshotter.
        let coords = trip.plateSightingsArray.filter(\.hasValidCoordinate).map(\.coordinate)
        let snapshot = await RecapMapRenderer.snapshot(
            for: coords,
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
