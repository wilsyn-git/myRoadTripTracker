import Foundation

/// A trip as the intents read it: plain values, no Core Data.
struct TripSnapshot {
    struct Sighting {
        let code: String
        let name: String
        let spottedBy: String?
        let seenDate: Date?
    }

    let name: String
    let isClosed: Bool
    /// Oldest first.
    let sightings: [Sighting]
}

/// One row of the "who's spotted the most" tally.
struct Spotter: Equatable {
    let name: String
    let count: Int
    /// Sightings with no `spottedByName`. Shown last, never leads the spoken line.
    let isUnknown: Bool
}

extension TripSnapshot {
    static let usCodes = Set(Location.usStates.map(\.code))
    static let caCodes = Set(Location.canadaLocations.map(\.code))

    var seenCodes: Set<String> { Set(sightings.map(\.code)) }
    var usSeen: Int { seenCodes.intersection(Self.usCodes).count }
    var caSeen: Int { seenCodes.intersection(Self.caCodes).count }

    /// Unseen plates in the grid's order: US then Canada.
    var unseen: [Location] {
        let seen = seenCodes
        return Location.allLocations.filter { !seen.contains($0.code) }
    }

    func sighting(of code: String) -> Sighting? {
        sightings.first { $0.code == code }
    }

    /// Spotters by count (then name), with an "Unknown" row last for uncredited sightings.
    var tally: [Spotter] {
        var counts: [String: Int] = [:]
        var unknown = 0
        for sighting in sightings {
            if let name = IntentAnswers.cleanName(sighting.spottedBy) {
                counts[name, default: 0] += 1
            } else {
                unknown += 1
            }
        }
        var ranked = counts
            .map { Spotter(name: $0.key, count: $0.value, isUnknown: false) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCompare($1.name) == .orderedAscending }
        if unknown > 0 {
            ranked.append(Spotter(name: "Unknown", count: unknown, isUnknown: true))
        }
        return ranked
    }
}

/// What Siri says. Values in, sentence out. Copy is the spec's
/// (`docs/superpowers/specs/2026-10-09-appIntentsDesign.md`, "The six intents").
enum IntentAnswers {

    static func count(_ trip: TripSnapshot) -> String {
        switch (trip.usSeen, trip.caSeen) {
        case (0, 0): "Nothing spotted on \(trip.name) yet."
        case (let us, 0): "On \(trip.name) you've seen \(states(us))."
        case (0, let ca): "On \(trip.name) you've seen \(ca) from Canada."
        case (let us, let ca): "On \(trip.name) you've seen \(states(us)) and \(ca) from Canada."
        }
    }

    // MARK: Helpers shared by every answer

    /// "today", "yesterday", "on Tuesday" (2–6 days ago), else "on Sep 30".
    static func spokenDay(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? .max
        if (2...6).contains(days) { return "on " + date.formatted(.dateTime.weekday(.wide)) }
        return "on " + date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func states(_ count: Int) -> String {
        count == 1 ? "1 state" : "\(count) states"
    }

    /// "A", "A and B", "A, B, and C".
    static func list(_ items: [String]) -> String {
        ListFormatter.localizedString(byJoining: items)
    }

    /// A display name worth saying aloud, or nil for nil / empty / whitespace.
    static func cleanName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Trip-name matching for `TripQuery`: "the Utah trip" finds "Utah 2026".
    static func tripName(_ name: String, matches query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if name.localizedStandardContains(trimmed) { return true }
        var stripped = trimmed.lowercased()
        if stripped.hasPrefix("the ") { stripped.removeFirst(4) }
        if stripped.hasSuffix(" trip") { stripped.removeLast(5) }
        return !stripped.isEmpty && name.localizedStandardContains(stripped)
    }
}
