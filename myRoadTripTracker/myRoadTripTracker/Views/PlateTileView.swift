import SwiftUI

struct PlateTileView: View {
    let location: Location
    let isSeen: Bool
    let isRecording: Bool
    let isRevealing: Bool
    let onTapUnseen: () -> Void
    let onTapSeen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tileScale: CGFloat = 1.0
    @State private var grayscaleAmount: Double = 1.0
    @State private var showCheckmark = false
    @State private var showBurst = false
    @State private var trimEnd: CGFloat = 0

    var body: some View {
        Button {
            if isSeen {
                onTapSeen()
            } else if !isRecording && !isRevealing {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.easeInOut(duration: 0.08)) {
                    tileScale = 0.95
                }
                onTapUnseen()
            }
        } label: {
            tileContent
        }
        .buttonStyle(.plain)
        .scaleEffect(tileScale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(location.name), \(isSeen ? "seen" : "not seen")")
        .accessibilityHint("Double-tap to \(isSeen ? "view details" : "mark as seen")")
        .onChange(of: isRecording) { _, recording in
            if recording {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    trimEnd = 1
                }
            } else {
                withAnimation(.default) {
                    trimEnd = 0
                }
            }
        }
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
            if !seen {
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
        .padding(6)
        .frame(maxWidth: .infinity)
        .aspectRatio(1.0 / 1.1, contentMode: .fit)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .opacity(isSeen || isRecording || isRevealing ? 1.0 : 0.45)
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
            if isRecording {
                RoundedRectangle(cornerRadius: 8)
                    .trim(from: 0, to: trimEnd)
                    .stroke(Color.blue, lineWidth: 2)
            }
        }
        .overlay {
            if showBurst {
                ConfettiBurstView()
                    .accessibilityHidden(true)
            }
        }
    }

    private func playRevealAnimation() {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.3)) {
                grayscaleAmount = 0
                showCheckmark = true
                tileScale = 1.0
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }

        withAnimation(.easeOut(duration: 0.25)) {
            grayscaleAmount = 0
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
            tileScale = 1.0
        }

        showBurst = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeIn(duration: 0.15)) {
                showCheckmark = true
            }
            showBurst = false
        }
    }
}
