import Foundation

/// One what's-new card: a feature and the words that introduce it.
struct Announcement: Identifiable, Equatable {
    enum ID: String {
        case siri
    }

    struct Line: Equatable {
        let text: String
        /// The one line a reader must not miss, drawn bold.
        var isKey = false
    }

    let id: ID
    let title: String
    let systemImage: String
    let lines: [Line]
}

/// Which feature cards to show, in order. Adding a card is one entry in `all`.
/// Spec: docs/superpowers/specs/2026-10-09-appIntentsDesign.md, "Ask Siri" what's-new card.
enum WhatsNew {
    // iOS gives an app no way to switch its own Siri shortcuts on: the first
    // request Siri recognises asks once. So the card teaches a phrase that is
    // sure to match and says what that first question will be. A "no" to that
    // question isn't asked again; the only way back is the Shortcuts app.
    static let all: [Announcement] = [
        Announcement(id: .siri, title: "Ask Siri", systemImage: "mic.fill", lines: [
            .init(text: "Log plates and check your trip without opening the app — handy from the passenger seat or on CarPlay."),
            .init(text: "Say \u{201C}We saw Maine in TripSpotter\u{201D}", isKey: true),
            .init(text: "Or ask \u{201C}How many states have we seen in TripSpotter?\u{201D} The first time, Siri asks to turn on TripSpotter\u{2019}s shortcuts. Say yes."),
            .init(text: "\u{201C}Spotter\u{201D} works too: \u{201C}What have we seen in Spotter?\u{201D}"),
            .init(text: "Missed it? In the Shortcuts app, open TripSpotter, tap \u{24D8} and turn Siri on."),
        ]),
    ]

    /// The next unseen card, or nil. Nothing until the user has a trip:
    /// Siri has nothing to answer about without one.
    static func next(seen: Set<String>, hasTrips: Bool) -> Announcement? {
        guard hasTrips else { return nil }
        return all.first { !seen.contains($0.id.rawValue) }
    }
}

/// The what's-new cards this phone has shown. One-way: nothing un-sees a card.
/// Raw strings, so an ID written by a newer build survives this build's writes.
enum WhatsNewStore {
    static let seenKey = "whatsNew.seen"

    static var seen: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
    }

    static func markSeen(_ id: Announcement.ID) {
        let updated = seen.union([id.rawValue])
        UserDefaults.standard.set(updated.sorted(), forKey: seenKey)
    }
}
