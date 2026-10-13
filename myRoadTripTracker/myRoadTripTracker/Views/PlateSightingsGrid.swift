import SwiftUI
import CoreData
import CoreLocation

struct PlateSightingsGrid: View {
    @ObservedObject var trip: Trip
    var locationManager: LocationManager
    var plateFilter: PlateFilter = .all
    var currentUserName: String
    @Environment(\.managedObjectContext) private var viewContext
    @State private var revealingCodes: Set<String> = []
    @State private var sightingToInspect: PlateSighting?
    /// `currentUserName`, mirrored into state for the tile tap closures. Unchanged tiles
    /// skip redraws (`.equatable()`) and keep closures from an earlier render, so reading
    /// a stored property there would credit a stale name (e.g. from before the join
    /// prompt). State reads stay current.
    @State private var spotterName = ""

    /// Each seen region's sighting, keyed by code; the earliest wins with duplicates.
    private var sightingsByCode: [String: PlateSighting] { trip.firstSightingByCode }

    private func filtered(_ locations: [Location], seenCodes: Set<String>) -> [Location] {
        switch plateFilter {
        case .all:
            return locations
        case .notSeen:
            return locations.filter { !seenCodes.contains($0.code) }
        }
    }

    private func isSeen(_ location: Location) -> Bool {
        sighting(for: location) != nil
    }

    private func sighting(for location: Location) -> PlateSighting? {
        sightingsByCode[location.code]
    }

    var body: some View {
        // Build the seen-code lookup once per render so each tile does an O(1) membership
        // check instead of scanning every sighting.
        let seenCodes = Set(sightingsByCode.keys)

        ScrollView {
            VStack(spacing: 16) {
                if trip.isClosed {
                    closedTripBanner
                }
                sectionView(title: "US States & DC", locations: Location.usStates, seenCodes: seenCodes)
                sectionView(title: "Canada", locations: Location.canadaLocations, seenCodes: seenCodes)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .sheet(item: $sightingToInspect) { sighting in
            PlateSightingDetailSheet(sighting: sighting, trip: trip)
        }
        .onChange(of: currentUserName, initial: true) { _, name in
            spotterName = name
        }
    }

    private var closedTripBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
            Text("Trip closed \u{2014} read only")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.fill, in: .capsule)
    }

    @ViewBuilder
    private func sectionView(title: String, locations: [Location], seenCodes: Set<String>) -> some View {
        if trip.isClosed {
            closedSectionView(title: title, locations: locations, seenCodes: seenCodes)
        } else {
            openSectionView(title: title, locations: locations, seenCodes: seenCodes)
        }
    }

    private func openSectionView(title: String, locations: [Location], seenCodes: Set<String>) -> some View {
        let visible = filtered(locations, seenCodes: seenCodes)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: title, locations: locations, seenCodes: seenCodes)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(visible) { location in
                    tile(for: location, seenCodes: seenCodes)
                        .contextMenu {
                            if seenCodes.contains(location.code) {
                                Button("Remove sighting", role: .destructive) {
                                    unmarkAsSeen(location)
                                }
                            }
                        }
                }
            }
        }
    }

    /// A closed trip can't change, so it reads as a result: the plates seen, then the ones
    /// missed, both as compact chips (#70, #74). The filter doesn't apply here.
    private func closedSectionView(title: String, locations: [Location], seenCodes: Set<String>) -> some View {
        let seen = locations.filter { seenCodes.contains($0.code) }
        let missed = locations.filter { !seenCodes.contains($0.code) }

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: title, locations: locations, seenCodes: seenCodes)

            if !seen.isEmpty {
                groupLabel("Seen \u{00B7} \(seen.count)")
                PlateChips(locations: seen, isSeen: true) { location in
                    sightingToInspect = sighting(for: location)
                }
            }
            if !missed.isEmpty {
                groupLabel("Not seen \u{00B7} \(missed.count)")
                PlateChips(locations: missed, isSeen: false)
            }
        }
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func tile(for location: Location, seenCodes: Set<String>) -> some View {
        PlateTileView(
            location: location,
            isSeen: seenCodes.contains(location.code),
            isRevealing: revealingCodes.contains(location.code),
            onTapUnseen: { markAsSeen(location) },
            onTapSeen: { sightingToInspect = sighting(for: location) }
        )
        .equatable()
    }

    private func sectionHeader(title: String, locations: [Location], seenCodes: Set<String>) -> some View {
        let seen = locations.filter { seenCodes.contains($0.code) }.count
        let total = locations.count
        let progress = total > 0 ? Double(seen) / Double(total) : 0

        return VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(seen)/\(total)")
                    .fontWeight(.semibold)
            }
            // The count above carries the meaning; the bar is decoration.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.fill)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(LinearGradient(colors: [Theme.amber, Theme.gold],
                                             startPoint: .leading, endPoint: .trailing))
                        .scaleEffect(x: progress, anchor: .leading)
                }
                .frame(height: 3)
                .accessibilityHidden(true)
        }
    }

    /// Saves the plate at once, so the tap counts immediately, then pins it on the map when
    /// a fix arrives. A recent last-known location pins it straight away.
    private func markAsSeen(_ location: Location) {
        // A Siri mark or a sync may already have added it, or the trip may have been
        // closed or deleted.
        guard !trip.isDeleted, trip.managedObjectContext != nil,
              !trip.isClosed, !isSeen(location) else { return }

        let recent = locationManager.recentLocation(maxAge: 60, maxAccuracy: 100)
        revealingCodes.insert(location.code)

        let sighting = PlateSighting(
            context: viewContext,
            locationCode: location.code,
            locationName: location.name,
            latitude: recent?.coordinate.latitude ?? 0.0,
            longitude: recent?.coordinate.longitude ?? 0.0,
            spottedByName: spotterName
        )
        sighting.trip = trip
        viewContext.save(contextInfo: "markAsSeen")

        if recent == nil {
            let sightingID = sighting.objectID
            Task { await attachLocation(to: sightingID) }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            revealingCodes.remove(location.code)
        }
    }

    /// Pins a just-saved sighting once a fix arrives, unless it was removed or got a
    /// location some other way while we waited. With no fix in time, `PinBackfill` tries
    /// again the next time the app is opened.
    private func attachLocation(to sightingID: NSManagedObjectID) async {
        let fix = await locationManager.requestFix(timeout: .seconds(10))
        guard let sighting = try? viewContext.existingObject(with: sightingID) as? PlateSighting,
              !sighting.isDeleted, !sighting.hasValidCoordinate else { return }
        guard let fix else {
            if locationManager.isAuthorized { PinBackfill.remember(sighting) }
            return
        }
        sighting.latitude = fix.coordinate.latitude
        sighting.longitude = fix.coordinate.longitude
        viewContext.save(contextInfo: "attachSightingLocation")
    }

    private func unmarkAsSeen(_ location: Location) {
        guard let sighting = sighting(for: location) else { return }
        viewContext.delete(sighting)
        viewContext.save(contextInfo: "unmarkAsSeen")
    }
}
