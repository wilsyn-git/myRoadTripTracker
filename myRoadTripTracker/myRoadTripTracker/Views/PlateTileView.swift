import SwiftUI

/// Equatable on what the tile draws, so the grid can skip unchanged tiles with
/// `.equatable()` (#38). Without it, the tap closures (which SwiftUI can't compare) made
/// every grid render redraw all 64 tiles. The closures are deliberately left out of `==`;
/// `PlateSightingsGrid` keeps whatever they read current.
struct PlateTileView: View, Equatable {
    let location: Location
    let isSeen: Bool
    let isRevealing: Bool
    let onTapUnseen: () -> Void
    let onTapSeen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tileScale: CGFloat = 1.0
    @State private var grayscaleAmount: Double = 1.0
    @State private var showCheckmark = false
    @State private var showBurst = false

    static func == (lhs: PlateTileView, rhs: PlateTileView) -> Bool {
        lhs.location == rhs.location && lhs.isSeen == rhs.isSeen && lhs.isRevealing == rhs.isRevealing
    }

    var body: some View {
        Button(action: handleTap) {
            tileContent
        }
        .buttonStyle(.plain)
        .scaleEffect(tileScale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(location.name), \(isSeen ? "seen" : "not seen")")
        .accessibilityHint("Double-tap to \(isSeen ? "view details" : "mark as seen")")
        .sensoryFeedback(.success, trigger: isRevealing) { _, revealing in revealing }
        .onChange(of: isRevealing) { _, revealing in
            if revealing {
                playRevealAnimation()
            }
        }
        .onAppear {
            if isSeen {
                grayscaleAmount = 0
                showCheckmark = true
            }
        }
        .onChange(of: isSeen) { _, seen in
            if seen {
                // Marked elsewhere (Siri, a collaborator) while this tile was on screen. No
                // local reveal plays, so show the seen state directly (#41).
                guard !isRevealing else { return }
                grayscaleAmount = 0
                withAnimation(.easeIn(duration: 0.15)) {
                    showCheckmark = true
                }
            } else {
                showCheckmark = false
                grayscaleAmount = 1.0
                tileScale = 1.0
            }
        }
    }

    private var tileContent: some View {
        VStack(spacing: 2) {
            Image(location.flagImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 28)
                .clipShape(.rect(cornerRadius: 3))
                .grayscale(isSeen && !isRevealing ? 0 : grayscaleAmount)

            Text(location.code)
                .font(.system(.caption, design: .monospaced))
                .bold()

            Text(location.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        // Fill the grid column at the content's own height. A fixed aspect ratio here got
        // no height from the grid, so it sized the tile from its content and left it
        // narrower than its column (#72).
        .frame(maxWidth: .infinity)
        .background(.background)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
        }
        .opacity(isSeen || isRevealing ? 1.0 : 0.45)
        .shadow(color: isSeen ? .black.opacity(0.06) : .clear, radius: 1, y: 1)
        .overlay(alignment: .topTrailing) {
            if showCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .offset(x: 3, y: -3)
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
                grayscaleAmount = 0
                showCheckmark = true
                tileScale = 1.0
            }
            return
        }

        withAnimation(.easeOut(duration: 0.25)) {
            grayscaleAmount = 0
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
