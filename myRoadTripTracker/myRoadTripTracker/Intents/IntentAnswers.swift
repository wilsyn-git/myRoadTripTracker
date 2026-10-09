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

    /// Seen plates in the grid's order: US then Canada.
    var seen: [Location] {
        let seen = seenCodes
        return Location.allLocations.filter { seen.contains($0.code) }
    }

    /// Names of the most recently spotted distinct plates, newest first.
    func recentNames(_ limit: Int) -> [String] {
        var codes = Set<String>()
        return sightings.reversed().filter { codes.insert($0.code).inserted }.prefix(limit).map(\.name)
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
        guard let summary = seenSummary(trip) else { return "Nothing spotted on \(trip.name) yet." }
        return "On \(trip.name) you've seen \(summary)."
    }

    /// "What have we seen": names them when there are few, else the count and the latest three.
    static func seen(_ trip: TripSnapshot) -> String {
        guard let summary = seenSummary(trip) else { return "Nothing spotted on \(trip.name) yet." }
        let seen = trip.seen
        if seen.count <= 8 { return "On \(trip.name) you've seen \(list(seen.map(\.name)))." }
        return "On \(trip.name) you've seen \(summary) — most recently \(list(trip.recentNames(3)))."
    }

    /// "23 states and 4 from Canada", or nil when nothing has been seen.
    private static func seenSummary(_ trip: TripSnapshot) -> String? {
        switch (trip.usSeen, trip.caSeen) {
        case (0, 0): nil
        case (let us, 0): states(us)
        case (0, let ca): "\(ca) from Canada"
        case (let us, let ca): "\(states(us)) and \(ca) from Canada"
        }
    }

    /// Other ways people say a trip's name: "the Miami trip", "Miami trip", and
    /// "Miami" for a trip named "Miami Trip". Never includes the name itself.
    nonisolated static func tripSynonyms(for name: String) -> [String] {
        var base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.lowercased().hasSuffix(" trip") { base = String(base.dropLast(5)) }
        guard !base.isEmpty else { return [] }
        var seen = Set([name.lowercased()])
        return [base, "\(base) trip", "the \(base) trip", "the \(base)"].filter { seen.insert($0.lowercased()).inserted }
    }

    static func haveWeSeen(_ location: Location, in trip: TripSnapshot, now: Date = .now) -> String {
        guard let sighting = trip.sighting(of: location.code) else {
            return "Not yet. \(location.name)'s still out there."
        }
        let day = sighting.seenDate.map { " " + spokenDay($0, now: now) } ?? ""
        if let who = cleanName(sighting.spottedBy) {
            return "Yes — \(who) spotted \(location.name)\(day)."
        }
        return "Yes — \(location.name) was spotted\(day)."
    }

    static func left(_ trip: TripSnapshot) -> String {
        let unseen = trip.unseen
        if unseen.isEmpty { return "You've seen every plate on \(trip.name)!" }
        if trip.sightings.isEmpty { return "All \(Location.allLocations.count) to go." }
        if unseen.count <= 8 { return "Still missing: \(list(unseen.map(\.name)))." }
        let usLeft = unseen.filter { TripSnapshot.usCodes.contains($0.code) }.count
        let caLeft = unseen.count - usLeft
        let parts = [usLeft > 0 ? states(usLeft) : nil, caLeft > 0 ? "\(caLeft) from Canada" : nil].compactMap { $0 }
        return "\(list(parts)) to go — they're on the card."
    }

    static func topSpotter(_ trip: TripSnapshot) -> String {
        guard !trip.sightings.isEmpty else { return "Nobody's spotted a plate on \(trip.name) yet." }
        let named = trip.tally.filter { !$0.isUnknown }
        guard let top = named.first else { return "Nobody's been credited with a plate on \(trip.name) yet." }
        let leaders = named.filter { $0.count == top.count }
        if leaders.count > 1 {
            return "\(list(leaders.map(\.name))) are tied with \(top.count)."
        }
        if named.count == 1 {
            return top.count == trip.sightings.count
                ? "\(top.name) has spotted all \(top.count)."
                : "\(top.name) has spotted \(top.count)."
        }
        let second = named[1]
        return "\(top.name) leads \(trip.name) with \(top.count). \(second.name) has \(second.count)."
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

    static func opening(tripName: String) -> String {
        "Opening \(tripName)."
    }

    static func marked(_ location: Location, number: Int, tripName: String) -> String {
        "Got it — \(location.name) is number \(number) on \(tripName)."
    }

    static func alreadySeen(_ location: Location, sighting: TripSnapshot.Sighting, now: Date = .now) -> String {
        let day = sighting.seenDate.map { " " + spokenDay($0, now: now) } ?? ""
        if let who = cleanName(sighting.spottedBy) {
            return "\(location.name)'s already on the list — \(who) spotted it\(day)."
        }
        if !day.isEmpty {
            return "\(location.name)'s already on the list — spotted\(day)."
        }
        return "\(location.name)'s already on the list."
    }
}
