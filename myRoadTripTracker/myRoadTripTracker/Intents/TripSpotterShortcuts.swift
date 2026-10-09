import AppIntents

/// Every phrase Siri knows. Order is the order Spotlight first shows them in.
nonisolated struct TripSpotterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkPlateIntent(),
            phrases: [
                "We saw \(\.$region) in \(.applicationName)",
                "We just saw \(\.$region) in \(.applicationName)",
                "Tick off \(\.$region) in \(.applicationName)",
                "Mark \(\.$region) in \(.applicationName)",
                "Mark a plate in \(.applicationName)",
            ],
            shortTitle: "Mark a Plate",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: TripCountIntent(),
            phrases: [
                "How many states have we seen in \(.applicationName)",
                "How many plates have we seen in \(.applicationName)",
                "How many states on \(\.$trip) in \(.applicationName)",
            ],
            shortTitle: "Trip Count",
            systemImageName: "number"
        )
        AppShortcut(
            intent: HaveWeSeenIntent(),
            phrases: [
                "Have we seen \(\.$region) in \(.applicationName)",
                "Did we see \(\.$region) in \(.applicationName)",
            ],
            shortTitle: "Have We Seen…",
            systemImageName: "questionmark.circle"
        )
        AppShortcut(
            intent: PlatesLeftIntent(),
            phrases: [
                "Which states are left in \(.applicationName)",
                "What plates are left in \(.applicationName)",
                "What's left on \(\.$trip) in \(.applicationName)",
            ],
            shortTitle: "Plates Left",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: TopSpotterIntent(),
            phrases: [
                "Who's spotted the most in \(.applicationName)",
                "Who's winning in \(.applicationName)",
                "Who's winning \(\.$trip) in \(.applicationName)",
            ],
            shortTitle: "Top Spotter",
            systemImageName: "crown"
        )
    }
}
