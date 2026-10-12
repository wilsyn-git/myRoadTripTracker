import SwiftUI

/// The line under a trip's name in the trip list (#65). A closed trip shows when it ran,
/// from its first plate to its last; an open trip shows how recently it saw a plate.
struct TripActivityLine: View {
    enum Style { case hero, row }

    @ObservedObject var trip: Trip
    var style: Style = .row

    var body: some View {
        let text = Self.text(for: trip, style: style)
        if !text.isEmpty {
            Text(text)
        }
    }

    static func text(for trip: Trip, style: Style) -> String {
        let span = trip.activitySpan
        if trip.isClosed {
            if let span { return range(span) }
            // No year: the row already sits under its year header.
            return trip.createdDate?.formatted(.dateTime.month(.abbreviated).day()) ?? ""
        }
        let started = trip.createdDate?.formatted(.dateTime.month(.abbreviated).day())
        guard let last = span?.upperBound else {
            return started.map { "Started \($0)" } ?? ""
        }
        let ago = last.formatted(.relative(presentation: .named))
        switch style {
        case .hero: return started.map { "Since \($0) · last plate \(ago)" } ?? "Last plate \(ago)"
        case .row: return "Last plate \(ago)"
        }
    }

    /// "Aug 30 – Sep 2". A one-day trip is just "Feb 7"; a trip across New Year names both years.
    static func range(_ span: ClosedRange<Date>, calendar: Calendar = .current) -> String {
        if calendar.isDate(span.lowerBound, inSameDayAs: span.upperBound) {
            return span.lowerBound.formatted(.dateTime.month(.abbreviated).day())
        }
        let interval = span.lowerBound..<span.upperBound
        let crossesYears = !calendar.isDate(span.lowerBound, equalTo: span.upperBound, toGranularity: .year)
        return crossesYears
            ? interval.formatted(.interval.month(.abbreviated).day().year())
            : interval.formatted(.interval.month(.abbreviated).day())
    }
}
