import SwiftUI

/// Two concentric progress rings: US plates outside, Canadian plates inside. Callers draw the
/// counts next to the ring, so the ring itself carries no text (#57).
struct DualProgressRingView: View {
    let usProgress: Double
    let usSeenCount: Int
    let caProgress: Double
    let caSeenCount: Int
    /// Width at the default text size. The ring scales with Dynamic Type from here, so it
    /// keeps pace with the counts beside it (#43).
    var diameter: CGFloat = 44

    @ScaledMetric(relativeTo: .subheadline) private var scale: CGFloat = 1

    private var usRingColor: Color {
        if usSeenCount <= 15 { return .red }
        else if usSeenCount <= 30 { return .yellow }
        else { return .green }
    }

    private var caRingColor: Color {
        if caSeenCount <= 4 { return .red }
        else if caSeenCount <= 8 { return .yellow }
        else { return .green }
    }

    var body: some View {
        let size = diameter * scale
        let outerWidth = size * 0.12
        let innerWidth = size * 0.1
        // Both strokes are inset to stay inside the frame, so a scaled-up ring never
        // spills onto the row above it.
        let outerInset = outerWidth / 2
        let innerInset = outerWidth + size * 0.04 + innerWidth / 2

        ZStack {
            Circle()
                .inset(by: outerInset)
                .stroke(.white.opacity(0.25), lineWidth: outerWidth)
            Circle()
                .inset(by: outerInset)
                .trim(from: 0, to: usProgress)
                .stroke(usRingColor, style: StrokeStyle(lineWidth: outerWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .inset(by: innerInset)
                .stroke(.white.opacity(0.25), lineWidth: innerWidth)
            Circle()
                .inset(by: innerInset)
                .trim(from: 0, to: caProgress)
                .stroke(caRingColor, style: StrokeStyle(lineWidth: innerWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
