import CoreData
import SwiftUI

/// Plate Passport: what every trip on this phone adds up to (#78; spec §2). Read-only.
struct PlatePassportView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Trip.createdDate, ascending: false)])
    private var trips: FetchedResults<Trip>
    /// Bumped when a trip or sighting changes, so the numbers follow a sync while open. The
    /// fetch alone only republishes trip inserts and deletes (#65).
    @State private var revision = 0
    @State private var showsAllPlates = false

    private static let usualSuspectsShown = 6

    var body: some View {
        content
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Plate Passport")
            .onReceive(NotificationCenter.default.publisher(
                for: .NSManagedObjectContextObjectsDidChange, object: viewContext
            )) { note in
                if note.touchesTripsOrSightings { revision &+= 1 }
            }
    }

    private var content: some View {
        _ = revision // Read so a bump re-runs this body.
        let history = PlateHistory(trips: trips)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                collectionPanel(history)
                statTiles(history)
                if history.hasComparisons {
                    usualSuspects(history)
                }
                let never = history.neverSeen
                if !never.isEmpty {
                    section("Still hunting \u{00B7} \(never.count)") {
                        PlateChips(locations: never, isSeen: false)
                    }
                }
                let once = history.seenOnce
                if history.hasComparisons, !once.isEmpty {
                    section("Seen only once \u{00B7} \(once.count)") {
                        PlateChips(locations: once, isSeen: true)
                    }
                }
                if !history.trips.isEmpty {
                    tripsByPlates(history)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: Collection

    private func collectionPanel(_ history: PlateHistory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All-time collection")
                .font(.subheadline)
                .bold()
                .textCase(.uppercase)
                .foregroundStyle(Theme.panelSecondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(history.collected.count)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text("of \(Location.allLocations.count)")
                    .font(.title3)
                    .bold()
                    .foregroundStyle(Theme.panelSecondaryText)
            }
            RegionProgressBars(
                usSeen: history.usCollected,
                caSeen: history.caCollected,
                axis: dynamicTypeSize.isAccessibilitySize ? .vertical : .horizontal
            )
            if let since = history.since {
                let count = history.trips.count
                Text("\(count) \(count == 1 ? "trip" : "trips") since \(since.formatted(.dateTime.month(.wide).year()))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.panelSecondaryText)
            }
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel(), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    // MARK: Stat tiles

    private func statTiles(_ history: PlateHistory) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return layout {
            if let typical = history.typicalPlateCount {
                statTile("\(typical)", "plates on a typical trip")
            }
            if let record = history.record {
                statTile("\(record.plateCount)", "record: \(record.name)")
            }
            statTile("\(history.neverSeen.count)", "plates never seen")
        }
        // Equal-height tiles: each fills the row's height, which the tallest tile sets.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    // MARK: Usual suspects

    private func usualSuspects(_ history: PlateHistory) -> some View {
        let all = history.byTripCount
        let shown = showsAllPlates ? all : Array(all.prefix(Self.usualSuspectsShown))
        let tripCount = history.trips.count
        return section("Usual suspects") {
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, plate in
                    if index > 0 { Divider().padding(.leading, 52) }
                    suspectRow(plate, of: tripCount)
                }
                if all.count > Self.usualSuspectsShown {
                    Divider()
                    Button(showsAllPlates ? "Show fewer" : "Show all \(all.count) plates") {
                        withAnimation { showsAllPlates.toggle() }
                    }
                    .foregroundStyle(Theme.greenText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private func suspectRow(_ plate: PlateCount, of tripCount: Int) -> some View {
        let isLarge = dynamicTypeSize.isAccessibilitySize
        // At accessibility sizes the count drops under the name, so a long name wraps whole
        // words instead of hyphenating in a narrow column.
        let layout = isLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 10))
        return HStack(spacing: 10) {
            Image(plate.location.flagImageName)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 20)
                .clipShape(.rect(cornerRadius: 3))
            layout {
                Text(plate.location.name)
                    .lineLimit(isLarge ? nil : 1)
                if !isLarge {
                    Spacer(minLength: 8)
                    Capsule()
                        .fill(.fill)
                        .frame(width: 54, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.amber, Theme.gold],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: 54 * Double(plate.trips) / Double(max(tripCount, 1)))
                        }
                }
                Text("\(plate.trips) of \(tripCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plate.location.name)
        .accessibilityValue("Seen on \(plate.trips) of \(tripCount) trips")
    }

    // MARK: Trips by plates

    private func tripsByPlates(_ history: PlateHistory) -> some View {
        let most = max(history.record?.plateCount ?? 1, 1)
        return section("Trips by plates") {
            VStack(spacing: 0) {
                ForEach(Array(history.trips.enumerated()), id: \.element.id) { index, total in
                    if index > 0 { Divider().padding(.leading, 12) }
                    // Opens the trip through the trip list's destination for object IDs.
                    NavigationLink(value: total.id) {
                        tripBar(total, most: most)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private func tripBar(_ total: TripPlateTotal, most: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(total.name)
                    .lineLimit(2)
                if total.isOpen {
                    Text("in progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(total.plateCount)")
                    .bold()
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Capsule()
                .fill(.fill)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(total.isOpen
                                  ? AnyShapeStyle(LinearGradient(colors: [Theme.amber, Theme.gold],
                                                                 startPoint: .leading, endPoint: .trailing))
                                  : AnyShapeStyle(Theme.greenText))
                            .frame(width: proxy.size.width * Double(total.plateCount) / Double(most))
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(total.name)
        .accessibilityValue("\(total.plateCount) plates\(total.isOpen ? ", in progress" : "")")
    }

    // MARK: Layout

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .bold()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            content()
        }
    }
}
