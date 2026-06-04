import SwiftUI

struct ConfettiBurstView: View {
    @State private var animate = false

    private let particleCount = 8
    private let colors: [Color] = [
        Color(red: 0.96, green: 0.62, blue: 0.04),
        Color(red: 0.98, green: 0.75, blue: 0.15)
    ]

    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { index in
                let angle = Double(index) * (2 * .pi / Double(particleCount))
                Circle()
                    .fill(colors[index % 2])
                    .frame(width: 6, height: 6)
                    .scaleEffect(animate ? 1 : 0)
                    .offset(
                        x: animate ? cos(angle) * 24 : 0,
                        y: animate ? sin(angle) * 24 : 0
                    )
                    .opacity(animate ? 0 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animate = true
            }
        }
    }
}
