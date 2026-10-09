import SwiftUI

// The cards Siri shows under its spoken line. They use the trip cards' green
// panel with white text (`TripCardView`), so they read as TripSpotter on Siri's
// light and dark panels alike. Spec: docs/superpowers/specs/2026-10-09-appIntentsDesign.md.

private enum SnippetStyle {
    static func panel(closed: Bool) -> Color {
        closed ? Color(white: 0.38) : Color(red: 0.2, green: 0.65, blue: 0.35)
    }
}

/// The frame every card shares: trip name on the left, a short fact on the right.
private struct SnippetShell<Content: View>: View {
    let title: String
    var trailing: String = ""
    var isClosed = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if isClosed {
                    Image(systemName: "lock.fill").font(.caption).accessibilityHidden(true)
                }
                Text(title).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                Text(trailing).font(.subheadline.weight(.semibold)).opacity(0.85).fixedSize()
            }
            content
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SnippetStyle.panel(closed: isClosed).gradient, in: .rect(cornerRadius: 16))
    }
}

/// A flag the way `TripCardView` draws its recent-sightings row.
private struct Flag: View {
    let assetName: String
    var width: CGFloat = 28

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: width * 0.64)
            .clipShape(.rect(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.6), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

private struct TripRing: View {
    let trip: TripSnapshot

    var body: some View {
        let usTotal = TripSnapshot.usCodes.count
        let caTotal = TripSnapshot.caCodes.count
        DualProgressRingView(
            usProgress: Double(trip.usSeen) / Double(usTotal),
            usSeenCount: trip.usSeen,
            usTotalCount: usTotal,
            caProgress: Double(trip.caSeen) / Double(caTotal),
            caSeenCount: trip.caSeen,
            caTotalCount: caTotal
        )
    }
}

struct CountCard: View {
    let trip: TripSnapshot

    /// The five newest plates, newest first, one per code: sync can leave two
    /// sightings of the same plate, and `ForEach` needs unique ids.
    private var recentFlags: [TripSnapshot.Sighting] {
        var seen = Set<String>()
        return Array(trip.sightings.reversed().filter { seen.insert($0.code).inserted }.prefix(5))
    }

    var body: some View {
        SnippetShell(title: trip.name, isClosed: trip.isClosed) {
            HStack(spacing: 16) {
                TripRing(trip: trip)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(trip.usSeen) of \(TripSnapshot.usCodes.count) US").font(.title3.weight(.bold))
                    Text("\(trip.caSeen) of \(TripSnapshot.caCodes.count) Canada").font(.subheadline.weight(.semibold)).opacity(0.85)
                    HStack(spacing: -4) {
                        ForEach(recentFlags, id: \.code) { sighting in
                            if let location = Location.byCode[sighting.code] {
                                Flag(assetName: location.flagImageName)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

struct MarkCard: View {
    let location: Location
    let trip: TripSnapshot

    var body: some View {
        let sighting = trip.sighting(of: location.code)
        SnippetShell(title: trip.name, trailing: "No. \(trip.seenCodes.count)", isClosed: trip.isClosed) {
            HStack(spacing: 14) {
                Flag(assetName: location.flagImageName, width: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name).font(.title3.weight(.bold)).lineLimit(2).minimumScaleFactor(0.8)
                    if let who = IntentAnswers.cleanName(sighting?.spottedBy) {
                        Text("by \(who)").font(.subheadline).opacity(0.85)
                    }
                }
                Spacer(minLength: 0)
                TripRing(trip: trip)
            }
        }
    }
}

struct SeenCard: View {
    let location: Location
    let trip: TripSnapshot

    var body: some View {
        let sighting = trip.sighting(of: location.code)
        SnippetShell(title: trip.name, isClosed: trip.isClosed) {
            HStack(spacing: 14) {
                Flag(assetName: location.flagImageName, width: 64)
                    .saturation(sighting == nil ? 0 : 1)
                    .opacity(sighting == nil ? 0.6 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name).font(.title3.weight(.bold)).lineLimit(2).minimumScaleFactor(0.8)
                    Text(status(sighting)).font(.subheadline).opacity(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: sighting == nil ? "circle.dashed" : "checkmark.circle.fill")
                    .font(.title2)
                    .accessibilityHidden(true)
            }
        }
    }

    private func status(_ sighting: TripSnapshot.Sighting?) -> String {
        guard let sighting else { return "Not yet" }
        let who = IntentAnswers.cleanName(sighting.spottedBy).map { "Spotted by \($0)" } ?? "Spotted"
        guard let date = sighting.seenDate else { return who }
        return "\(who) · \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

struct PlatesLeftCard: View {
    let trip: TripSnapshot

    private let columns = [GridItem(.adaptive(minimum: 38), spacing: 6)]

    var body: some View {
        let unseen = trip.unseen
        SnippetShell(title: trip.name, trailing: unseen.isEmpty ? "" : "\(unseen.count) left", isClosed: trip.isClosed) {
            if unseen.isEmpty {
                Label("Every plate spotted!", systemImage: "party.popper.fill").font(.title3.weight(.bold))
            } else {
                section("US", unseen.filter { TripSnapshot.usCodes.contains($0.code) })
                section("Canada", unseen.filter { TripSnapshot.caCodes.contains($0.code) })
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ locations: [Location]) -> some View {
        if !locations.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption.weight(.bold)).opacity(0.85)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(locations) { location in
                        Text(location.code)
                            .font(.caption.weight(.bold).monospaced())
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(.white.opacity(0.18), in: .rect(cornerRadius: 6))
                            .accessibilityLabel(location.name)
                    }
                }
            }
        }
    }
}

struct TopSpotterCard: View {
    let trip: TripSnapshot

    var body: some View {
        let tally = Array(trip.tally.prefix(6))
        let topCount = tally.first(where: { !$0.isUnknown })?.count
        SnippetShell(title: trip.name, trailing: "\(trip.sightings.count) plates", isClosed: trip.isClosed) {
            if tally.isEmpty {
                Text("No plates yet").font(.title3.weight(.bold))
            } else {
                VStack(spacing: 8) {
                    ForEach(tally, id: \.name) { spotter in
                        HStack(spacing: 8) {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .opacity(!spotter.isUnknown && spotter.count == topCount ? 1 : 0)
                                .accessibilityHidden(true)
                            Text(spotter.name).font(.body.weight(.semibold)).lineLimit(1)
                                .opacity(spotter.isUnknown ? 0.7 : 1)
                            Spacer(minLength: 8)
                            Text("\(spotter.count)").font(.body.weight(.bold).monospacedDigit())
                        }
                    }
                }
            }
        }
    }
}
