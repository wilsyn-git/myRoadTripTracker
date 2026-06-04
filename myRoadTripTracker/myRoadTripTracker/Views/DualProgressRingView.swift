import SwiftUI

struct DualProgressRingView: View {
    let usProgress: Double
    let usSeenCount: Int
    let usTotalCount: Int
    let caProgress: Double
    let caSeenCount: Int
    let caTotalCount: Int

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
                .padding(8)
            Circle()
                .trim(from: 0, to: caProgress)
                .stroke(caRingColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(8)

            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Text("US")
                        .font(.system(size: 7, weight: .medium, design: .rounded))
                        .opacity(0.7)
                    Text("\(usSeenCount)/\(usTotalCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                HStack(spacing: 2) {
                    Text("CA")
                        .font(.system(size: 7, weight: .medium, design: .rounded))
                        .opacity(0.7)
                    Text("\(caSeenCount)/\(caTotalCount)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .opacity(0.85)
                }
            }
        }
        .frame(width: 68, height: 68)
    }
}
