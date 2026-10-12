import SwiftUI

/// US and Canada progress as two labelled bars ("US 7/51"). One hue, drawn in the current
/// foreground style, so it reads on a green panel and on a plain background. Replaces the
/// red/yellow/green ring, where every new trip started out red (#65).
struct RegionProgressBars: View {
    let usSeen: Int
    let caSeen: Int
    /// Side by side on the trip list's hero card; stacked in narrow Siri cards and at
    /// accessibility text sizes.
    var axis: Axis = .horizontal

    static let usTotal = Location.usStates.count
    static let caTotal = Location.canadaLocations.count

    var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        layout {
            RegionBar(region: "US", spokenRegion: "US plates", seen: usSeen, total: Self.usTotal)
            RegionBar(region: "CA", spokenRegion: "Canadian plates", seen: caSeen, total: Self.caTotal)
        }
    }
}

/// One labelled bar. The track and fill use hierarchical styles, so they follow whatever
/// foreground style the bars sit in.
private struct RegionBar: View {
    let region: String
    let spokenRegion: String
    let seen: Int
    let total: Int
    @ScaledMetric(relativeTo: .subheadline) private var barHeight: CGFloat = 6

    private var fraction: Double {
        total > 0 ? min(Double(seen) / Double(total), 1) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(region).font(.subheadline).bold()
                Text("\(seen)/\(total)").font(.subheadline).monospacedDigit()
            }
            Capsule()
                .fill(.quaternary)
                .frame(height: barHeight)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        // A started trip always shows a sliver, so one plate doesn't look like none.
                        let width = seen > 0 ? max(proxy.size.width * fraction, barHeight) : 0
                        Capsule().fill(.primary).frame(width: width)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenRegion)
        .accessibilityValue("\(seen) of \(total)")
    }
}
