import SwiftUI

/// Equatable on what the tile draws, so the grid can skip unchanged tiles with
/// `.equatable()` (#38). Without it, the tap closures (which SwiftUI can't compare) made
/// every grid render redraw all 64 tiles. The closures are deliberately left out of `==`;
/// `PlateSightingsGrid` keeps whatever they read current.
struct PlateTileView: View, Equatable {
    let location: Location
    let isSeen: Bool
    let isRevealing: Bool
    /// This trip saw the plate before any other trip did; it wears a 1ST badge (#78).
    var isFirstEver = false
    let onTapUnseen: () -> Void
    let onTapSeen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tileScale: CGFloat = 1.0
    /// 0 draws the unseen tile, 1 the seen one; the reveal animates the green fill in.
    @State private var seenAmount: Double = 0
    @State private var showCheckmark = false
    @State private var showBurst = false

    static func == (lhs: PlateTileView, rhs: PlateTileView) -> Bool {
        lhs.location == rhs.location && lhs.isSeen == rhs.isSeen && lhs.isRevealing == rhs.isRevealing
            && lhs.isFirstEver == rhs.isFirstEver
    }

    var body: some View {
        Button(action: handleTap) {
            tileContent
        }
        .buttonStyle(.plain)
        .scaleEffect(tileScale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(location.name), \(isSeen ? "seen" : "not seen")\(isSeen && isFirstEver ? ", first time ever" : "")")
        .accessibilityHint("Double-tap to \(isSeen ? "view details" : "mark as seen")")
        .sensoryFeedback(.success, trigger: isRevealing) { _, revealing in revealing }
        .onChange(of: isRevealing) { _, revealing in
            if revealing {
                playRevealAnimation()
            }
        }
        .onAppear {
            if isSeen {
                seenAmount = 1
                showCheckmark = true
            }
        }
        .onChange(of: isSeen) { _, seen in
            if seen {
                // Marked elsewhere (Siri, a collaborator) while this tile was on screen. No
                // local reveal plays, so show the seen state directly (#41).
                guard !isRevealing else { return }
                seenAmount = 1
                withAnimation(.easeIn(duration: 0.15)) {
                    showCheckmark = true
                }
            } else {
                showCheckmark = false
                seenAmount = 0
                tileScale = 1.0
            }
        }
    }

    /// Every tile draws at full contrast so a plate's name is easy to find in a sunlit car;
    /// seen tiles are told apart by their green fill, border and check, not by dimming the
    /// unseen ones.
    private var tileContent: some View {
        let showsSeen = isSeen || isRevealing
        return VStack(spacing: 2) {
            Image(location.flagImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 28)
                .clipShape(.rect(cornerRadius: 3))

            Text(location.code)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(showsSeen ? AnyShapeStyle(Theme.seenTileText) : AnyShapeStyle(.secondary))

            // The name is what people scan for (the grid is alphabetical), so it's the
            // largest, darkest text on the tile.
            Text(location.name)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(showsSeen ? AnyShapeStyle(Theme.seenTileText) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        // Fill the grid column at the content's own height. A fixed aspect ratio here got
        // no height from the grid, so it sized the tile from its content and left it
        // narrower than its column (#72).
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Rectangle().fill(.background)
                Rectangle().fill(Theme.seenTileFill).opacity(seenAmount)
            }
        }
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
                .opacity(1 - seenAmount)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.greenText, lineWidth: 2)
                .opacity(seenAmount)
        }
        .overlay(alignment: .topTrailing) {
            if showCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color(.systemBackground), Theme.greenText)
                    .font(.body)
                    .offset(x: 5, y: -5)
            }
        }
        .overlay(alignment: .topLeading) {
            if isFirstEver && showCheckmark {
                FirstEverBadge()
                    .offset(x: 4, y: -7)
            }
        }
        .overlay {
            if showBurst {
                ConfettiBurstView()
                    .accessibilityHidden(true)
            }
        }
    }

    private func handleTap() {
        // Ignore taps while the reveal plays, so a quick double-tap doesn't open details.
        guard !isRevealing else { return }
        if isSeen {
            onTapSeen()
        } else {
            onTapUnseen()
        }
    }

    private func playRevealAnimation() {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.3)) {
                seenAmount = 1
                showCheckmark = true
                tileScale = 1.0
            }
            return
        }

        withAnimation(.easeOut(duration: 0.25)) {
            seenAmount = 1
        }

        // A quick press, then a springy release. The reveal now starts on the tap itself
        // (the save no longer waits for GPS), so it carries the press too.
        withAnimation(.easeInOut(duration: 0.08)) {
            tileScale = 0.95
        } completion: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                tileScale = 1.0
            }
        }

        showBurst = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeIn(duration: 0.15)) {
                showCheckmark = true
            }
            showBurst = false
        }
    }
}
