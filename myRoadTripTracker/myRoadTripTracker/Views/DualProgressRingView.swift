import SwiftUI

struct DualProgressRingView: View {
    let usProgress: Double
    let usSeenCount: Int
    let usTotalCount: Int
    let caProgress: Double
    let caSeenCount: Int
    let caTotalCount: Int

    // Sized for the default text size and scaled with Dynamic Type, so larger text grows
    // the ring instead of leaving tiny fixed-size labels (#43). The trip card makes room
    // at accessibility sizes (#32).
    @ScaledMetric(relativeTo: .caption2) private var ringSize: CGFloat = 68
    @ScaledMetric(relativeTo: .caption2) private var ringGap: CGFloat = 8
    @ScaledMetric(relativeTo: .caption2) private var regionLabelSize: CGFloat = 7
    @ScaledMetric(relativeTo: .caption2) private var usCountSize: CGFloat = 10
    @ScaledMetric(relativeTo: .caption2) private var caCountSize: CGFloat = 9

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
        ZStack {
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 5)
            Circle()
                .trim(from: 0, to: usProgress)
                .stroke(usRingColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 4)
                .padding(ringGap)
            Circle()
                .trim(from: 0, to: caProgress)
                .stroke(caRingColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(ringGap)

            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Text("US")
                        .font(.system(size: regionLabelSize, weight: .medium, design: .rounded))
                        .opacity(0.7)
                    Text("\(usSeenCount)/\(usTotalCount)")
                        .font(.system(size: usCountSize, weight: .bold, design: .rounded))
                }
                HStack(spacing: 2) {
                    Text("CA")
                        .font(.system(size: regionLabelSize, weight: .medium, design: .rounded))
                        .opacity(0.7)
                    Text("\(caSeenCount)/\(caTotalCount)")
                        .font(.system(size: caCountSize, weight: .semibold, design: .rounded))
                        .opacity(0.85)
                }
            }
        }
        .frame(width: ringSize, height: ringSize)
    }
}
