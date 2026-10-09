import AppIntents

/// Every phrase Siri knows. Order is the order Spotlight first shows them in.
///
/// `\(.applicationName)` also matches the second names in Info.plist's
/// `INAlternativeAppNames` ("Spotter", "Trip Spotter"). A trip parameter matches
/// the trip's name or its synonyms ("the Miami trip"; `TripEntity`), and the
/// "the … trip" phrase variants cover Siri splitting the words around it.
nonisolated struct TripSpotterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkPlateIntent(),
            phrases: [
                "We saw \(\.$region) in \(.applicationName)",
                "We just saw \(\.$region) in \(.applicationName)",
                "We got \(\.$region) in \(.applicationName)",
                "We spotted \(\.$region) in \(.applicationName)",
                "Spotted \(\.$region) in \(.applicationName)",
                // No "Mark …" or "Tick off …": Siri reads them as task commands and
                // answers itself without trying TripSpotter (seen on device, build 63).
                "Add \(\.$region) in \(.applicationName)",
                "Add \(\.$region) to \(.applicationName)",
                // Two-step: Siri answers "Oh! Which one?" and takes the plate on its own,
                // which it hears far more reliably than a plate mid-sentence.
                "Add a plate to \(.applicationName)",
                "Add a plate in \(.applicationName)",
                "We saw a plate in \(.applicationName)",
                "We spotted a plate in \(.applicationName)",
            ],
            shortTitle: "Mark a Plate",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: TripCountIntent(),
            phrases: [
                "How many states have we seen in \(.applicationName)",
                "How many plates have we seen in \(.applicationName)",
                "How are we doing in \(.applicationName)",
                "What's our count in \(.applicationName)",
                "How many states on \(\.$trip) in \(.applicationName)",
                "How many plates on \(\.$trip) in \(.applicationName)",
                "How many states on the \(\.$trip) trip in \(.applicationName)",
            ],
            shortTitle: "Trip Count",
            systemImageName: "number"
        )
        AppShortcut(
            intent: PlatesSeenIntent(),
            phrases: [
                "What have we seen in \(.applicationName)",
                "What did we see in \(.applicationName)",
                "What plates have we seen in \(.applicationName)",
                "What have we seen on \(\.$trip) in \(.applicationName)",
                "What did we see on \(\.$trip) in \(.applicationName)",
                "What did we see on the \(\.$trip) trip in \(.applicationName)",
            ],
            shortTitle: "Plates Seen",
            systemImageName: "eye"
        )
        AppShortcut(
            intent: HaveWeSeenIntent(),
            phrases: [
                "Have we seen \(\.$region) in \(.applicationName)",
                "Did we see \(\.$region) in \(.applicationName)",
                "Have we got \(\.$region) in \(.applicationName)",
                "Did we get \(\.$region) in \(.applicationName)",
            ],
            shortTitle: "Have We Seen…",
            systemImageName: "questionmark.circle"
        )
        AppShortcut(
            intent: PlatesLeftIntent(),
            phrases: [
                "Which states are left in \(.applicationName)",
                "What plates are left in \(.applicationName)",
                "What's left in \(.applicationName)",
                "What's left on \(\.$trip) in \(.applicationName)",
                "What's left on the \(\.$trip) trip in \(.applicationName)",
                "What plates are left on \(\.$trip) in \(.applicationName)",
            ],
            shortTitle: "Plates Left",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: TopSpotterIntent(),
            phrases: [
                "Who's spotted the most in \(.applicationName)",
                "Who's winning in \(.applicationName)",
                "Who's ahead in \(.applicationName)",
                "Who's winning \(\.$trip) in \(.applicationName)",
                "Who's winning the \(\.$trip) trip in \(.applicationName)",
                "Who's ahead on \(\.$trip) in \(.applicationName)",
            ],
            shortTitle: "Top Spotter",
            systemImageName: "crown"
        )
        AppShortcut(
            intent: OpenTripIntent(),
            phrases: [
                "Open my trip in \(.applicationName)",
                "Open \(\.$trip) in \(.applicationName)",
                "Open the \(\.$trip) trip in \(.applicationName)",
            ],
            shortTitle: "Open Trip",
            systemImageName: "car"
        )
    }
}
