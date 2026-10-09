import SwiftUI

/// A what's-new card as a medium-height sheet over the trip list. Closing it
/// any way (Got it, swipe down) marks it seen.
struct WhatsNewSheet: View {
    let announcement: Announcement
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let green = Color(red: 0.2, green: 0.65, blue: 0.35)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: announcement.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Self.green.gradient, in: .circle)
                        .accessibilityHidden(true)
                    Text("NEW")
                        .font(.caption2.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(Self.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Self.green.opacity(0.15), in: .capsule)
                        .accessibilityHidden(true)
                }
                Text(announcement.title)
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                ForEach(announcement.lines.indices, id: \.self) { index in
                    let line = announcement.lines[index]
                    Text(line.text)
                        .font(line.isKey ? .body.weight(.semibold) : .body)
                        .foregroundStyle(line.isKey ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // At accessibility sizes the text scrolls under a pinned bar and the
                // hard edge effect leaves a blurred trace, so the button scrolls with it.
                if dynamicTypeSize.isAccessibilitySize {
                    gotItButton
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .scrollEdgeEffectStyle(.hard, for: .bottom)
        .safeAreaBar(edge: .bottom) {
            if !dynamicTypeSize.isAccessibilitySize {
                gotItButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            WhatsNewStore.markSeen(announcement.id)
        }
    }

    private var gotItButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Got it")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Self.green)
        .controlSize(.large)
    }
}
