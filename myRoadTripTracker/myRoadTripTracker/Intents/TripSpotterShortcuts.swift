import AppIntents

/// Every phrase Siri knows. Order is the order Spotlight first shows them in.
nonisolated struct TripSpotterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
    }
}
