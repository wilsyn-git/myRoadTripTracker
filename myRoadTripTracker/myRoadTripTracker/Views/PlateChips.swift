import SwiftUI

/// A closed trip's plates as small chips (flag and code) that wrap across lines (#70, #74).
/// Seen plates are in colour and, given `onTap`, open their sighting; missed ones are grey and
/// read-only, since a closed trip can't mark plates.
struct PlateChips: View {
    let locations: [Location]
    let isSeen: Bool
    /// Opens a seen plate's sighting. Without it, chips are display-only (Plate Passport, #78).
    var onTap: ((Location) -> Void)? = nil
    /// Plates this trip saw before any other trip did. Their chips carry the 1ST badge, as
    /// the open trip's tiles do, so the "N new" pill can be traced to plates (#79).
    var firstEverCodes: Set<String> = []

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(locations) { location in
                if isSeen, let onTap {
                    Button {
                        onTap(location)
                    } label: {
                        PlateChip(location: location, isSeen: true,
                                  isFirstEver: firstEverCodes.contains(location.code))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double-tap to view details")
                } else {
                    PlateChip(location: location, isSeen: isSeen,
                              isFirstEver: isSeen && firstEverCodes.contains(location.code))
                }
            }
        }
    }
}

private struct PlateChip: View {
    let location: Location
    let isSeen: Bool
    var isFirstEver = false

    var body: some View {
        HStack(spacing: 5) {
            Image(location.flagImageName)
                .resizable()
                .scaledToFill()
                .frame(width: 20, height: 13)
                .clipShape(.rect(cornerRadius: 2))
                .grayscale(isSeen ? 0 : 1)
                .opacity(isSeen ? 1 : 0.6)
            Text(location.code)
                .font(.system(.caption, design: .monospaced))
                .bold()
            if isFirstEver {
                FirstEverBadge()
            }
        }
        .foregroundStyle(isSeen ? .primary : .secondary)
        .padding(.leading, 5)
        .padding(.trailing, 9)
        .padding(.vertical, 6)
        .background(.fill, in: .capsule)
        .contentShape(.capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(location.name), \(isSeen ? "seen" : "not seen")\(isFirstEver ? ", first time ever" : "")")
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
