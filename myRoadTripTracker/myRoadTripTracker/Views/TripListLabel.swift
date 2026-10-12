import Foundation

/// What VoiceOver reads for a trip in the trip list, hero card or row (#65).
enum TripListLabel {
    static func spoken(_ trip: Trip, isShared: Bool, style: TripActivityLine.Style) -> String {
        let counts = trip.regionCounts
        var parts = [
            trip.name,
            TripActivityLine.text(for: trip, style: style),
            "\(counts.us) of \(RegionProgressBars.usTotal) US plates",
            "\(counts.ca) of \(RegionProgressBars.caTotal) Canadian plates",
        ]
        if isShared { parts.append("shared") }
        let unseenNotes = trip.unseenNoteCount
        if unseenNotes > 0 { parts.append(unseenNotes == 1 ? "1 new note" : "\(unseenNotes) new notes") }
        if trip.hasUnseenRecap { parts.append("new recap available") }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
