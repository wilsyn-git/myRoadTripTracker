import SwiftUI

/// A closed trip's plates that were never seen, as small grey chips (flag and code) that
/// wrap across lines. They're read-only: a closed trip can't mark plates (#70).
struct MissedPlateChips: View {
    let locations: [Location]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(locations) { location in
                MissedPlateChip(location: location)
            }
        }
    }
}

private struct MissedPlateChip: View {
    let location: Location

    var body: some View {
        HStack(spacing: 5) {
            Image(location.flagImageName)
                .resizable()
                .scaledToFill()
                .frame(width: 20, height: 13)
                .clipShape(.rect(cornerRadius: 2))
                .grayscale(1)
                .opacity(0.6)
            Text(location.code)
                .font(.system(.caption, design: .monospaced))
                .bold()
        }
        .foregroundStyle(.secondary)
        .padding(.leading, 5)
        .padding(.trailing, 9)
        .padding(.vertical, 4)
        .background(.fill, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(location.name), not seen")
    }
}

/// Lays its subviews out left to right, starting a new line when the next one won't fit.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let widthWithItem = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if widthWithItem > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
