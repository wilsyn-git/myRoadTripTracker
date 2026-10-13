import SwiftUI

/// Plates this trip hasn't seen that your other trips usually did, so you know what to look
/// out for (#78; spec §4). A tap marks the plate, like its tile in the grid.
struct WatchForStrip: View {
    let plates: [PlateCount]
    /// Other trips with plates: the "of M" in each caption.
    let pastTripCount: Int
    let onMark: (Location) -> Void

    @ScaledMetric(relativeTo: .caption) private var cardWidth: CGFloat = 96
    @State private var marks = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // At accessibility sizes the two labels stack, so neither wraps word by word.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            layout {
                Text("Watch for")
                    .font(.headline)
                if !typeSize.isAccessibilitySize {
                    Spacer()
                }
                Text("seen on most past trips")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(plates) { plate in
                        Button {
                            marks += 1
                            onMark(plate.location)
                        } label: {
                            card(plate)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(plate.location.name), not seen")
                        .accessibilityValue("Seen on \(plate.trips) of \(pastTripCount) past trips")
                        .accessibilityHint("Double-tap to mark as seen")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .animation(.default, value: plates.map(\.id))
        }
        // The grid tile that plays the reveal may be off screen, so the strip gives its own.
        .sensoryFeedback(.success, trigger: marks)
    }

    private func card(_ plate: PlateCount) -> some View {
        VStack(spacing: 2) {
            Image(plate.location.flagImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 28)
                .clipShape(.rect(cornerRadius: 3))
                .grayscale(1)
                .opacity(0.5)
            Text(plate.location.code)
                .font(.system(.caption, design: .monospaced))
                .bold()
            Text(plate.location.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("\(plate.trips) of \(pastTripCount) trips")
                .font(.caption)
                .bold()
                .foregroundStyle(Theme.greenText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(width: cardWidth)
        .background(.background)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
        }
    }
}
