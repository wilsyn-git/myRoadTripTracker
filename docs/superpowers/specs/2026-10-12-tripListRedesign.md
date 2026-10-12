# Trips Screen Redesign — Design

Issue: #65 · Branch: `tripListRedesign` · Date: 2026-10-12

## Goal

When someone opens TripSpotter, the trip they're on now is front and centre, and their past trips are tidy, scannable history rather than a growing wall of identical cards. Every action on a trip is discoverable, and the screen meets Apple's contrast and color guidance.

## Background: review findings

A review against the Human Interface Guidelines (Collections, Lists and Tables, Context Menus, Color, Accessibility, Searching) and the swiftui-pro checklist found:

| # | Finding | Reference |
|---|---|---|
| 1 | One flat grid; closed trips sort last (`isClosed` ascending) but have no section, so the active trip gets lost among old ones. | HIG Lists: grouped style with headers |
| 2 | Grid sorts by `createdDate`; Siri's current trip is the open trip with the latest **activity** (`IntentTrips.currentTrip`). They can disagree. | Consistency |
| 3 | Closed trips are mostly text but each gets a large 0.85-aspect card. | HIG Collections: "Consider using a table instead of a collection for text" |
| 4 | Delete Trip exists only in the long-press menu; Close/Reopen only in the trip screen. | HIG Context Menus: "Always make context menu items available in the main interface, too" |
| 5 | White on `Theme.green` is 3.1:1 at the base color; `.gradient` lightens the top to about (99,197,131), roughly 2:1. | HIG Accessibility: 4.5:1 minimum |
| 6 | Ring color is red ≤15 / yellow ≤30 / green, so every new trip starts red. Red/green is the hardest pair for color-blind users. | HIG Color: don't redefine semantic colors; don't rely on color alone |
| 7 | Ring and "US 7/51" text duplicate each other; five clusters on a 160pt card. | Clutter |
| 8 | Owned and joined trips look the same, yet long-press offers Delete vs Leave. | Predictability |
| 9 | Closed trips show only a created date, not the span of the trip. | Content |

## Decisions

- **Closed = past.** No separate archive state. Closing a trip moves it to Past Trips for every participant. No data model change and no CloudKit production schema deploy.
- **Layout A (hero + list)** was chosen over yearly card shelves and a separate Past Trips screen.
- **Scope includes:** swipe and context-menu actions, Delete Trip in the trip screen, a darker `Theme.green` app-wide, and progress bars replacing `DualProgressRingView` everywhere (including the Siri card).

## Design

### 1. Screen structure (`ContentView`)

The `ScrollView` + `LazyVGrid` becomes a `List` with `.listStyle(.insetGrouped)`. A `List` is required for swipe actions.

- **Current** section
  - The **hero card**: the open trip with the most recent activity (see §2). Rendered as a custom row with `.listRowBackground(Color.clear)` and zero row insets so it reads as a card, not a cell.
  - Every other open trip as a compact row (§4), newest activity first.
  - If there are no open trips but there are past ones: a single row, "No trip in progress", with a **Start a Trip** button that calls the existing `addTrip()`.
- **Past Trips** — closed trips, one `Section` per calendar year of last activity, years descending, rows newest activity first. Each header shows the year (e.g. "2026"); the first past section's header is a two-line custom header with "Past Trips" above its year, matching the "Current" header's style.
- **Empty state** (no trips at all): the existing `ContentUnavailableView` overlay, unchanged.
- **Search**: `.searchable(text:prompt: "Search trips")` filtering both sections by name (case- and diacritic-insensitive `localizedStandardContains`), attached only when there are more than 5 past trips. Empty results use `ContentUnavailableView.search`.
- Title "Road Trips", the + toolbar button and its pulse, the what's-new sheet, the Siri route handling, the left-trip toast and all alerts are kept as they are.
- Navigation keeps `NavigationLink(value: trip.objectID)`; the whole row and the whole hero card are tappable.

The `@FetchRequest` stays a single fetch of all trips. Grouping and ordering happen in a small pure value type (e.g. `TripListSections`, in `Services/`) built from the fetched trips: `hero: Trip?`, `otherOpen: [Trip]`, `pastByYear: [(year: Int, trips: [Trip])]`. That keeps the view body simple and the logic in one readable place. Last-activity dates are computed once per trip per rebuild, not inside sort comparators.

### 2. One "last activity" rule

Move `IntentTrips.lastActivity(_:)` to a `nonisolated` `Trip` extension (`Models/Trip+Activity.swift` or alongside the convenience accessors):

- `lastActivity`: latest `seenDate` among sightings, else `createdDate`, else `.distantPast` — unchanged from today.
- `activitySpan`: `(start: Date, end: Date)?` — first and last sighting `seenDate`; `nil` when there are no sightings (callers fall back to `createdDate`).

`IntentTrips.currentTrip` and the hero both use `lastActivity`. Ties break toward the more recently created trip, so the result is deterministic. That resolves #14; close it from the PR.

### 3. Hero card (`TripHeroCard`, replaces `TripCardView`)

- Name (`.title2`, bold, up to 2 lines; 4 at accessibility sizes).
- Subtitle: "Since Oct 11 · last plate 2h ago" (`createdDate` and `lastActivity`, relative date via `Text(_, style: .relative)` or `.formatted(.relative)`). With no sightings: "Started Oct 11".
- Shared indicator: `person.2.fill` + participant count when the trip is shared (participant count > 1, or the user isn't the owner), so joined trips are distinguishable.
- Unseen-notes dot and new-recap sparkle, using the existing `unseenObservationCount` / `hasUnseenRecap` logic, moved with the card.
- The five most recent flags (existing strip).
- `RegionProgressBars` (§6) for US and CA.
- Background: the shared panel gradient (§6). White foreground; secondary text uses `.secondary`-style hierarchy on white (e.g. `.white.opacity` replaced by `foregroundStyle(.white.secondary)`), never `.caption2`.
- Accessibility: one combined element with a label covering name, progress, shared state and unseen recap, as today.

### 4. Trip row (`TripRow`)

Used for other open trips and all past trips.

- Leading: name (`.body`, semibold) over a secondary line — past trips: date range from `activitySpan` ("Aug 30 – Sep 2", year included only when the span crosses years; falls back to the created date); open trips: "Last plate 2h ago" or "Started Oct 11".
- Trailing: "US 34 · CA 10" in `.subheadline`, monospaced digits, secondary color.
- Shared icon, unseen-notes dot and new-recap sparkle when they apply.
- No ring, no bars, no flags.
- At accessibility text sizes the score moves below the name (`ViewThatFits` or a `dynamicTypeSize.isAccessibilitySize` branch).
- Standard system row background, so light and dark mode come from the system.

### 5. Actions

The same action set is available from swipe, long-press and the trip screen.

| Action | Who | Swipe | Long-press | Trip screen |
|---|---|---|---|---|
| Close / Reopen | Owner | Leading, no confirmation (it's reversible) | Yes | Already in overflow |
| Delete Trip | Owner | Trailing, destructive, `allowsFullSwipe: false`, existing confirmation alert | Yes, last, destructive | **New** in overflow, last, destructive, same confirmation |
| Leave Trip | Participant | Trailing, destructive, `allowsFullSwipe: false`, existing confirmation alert | Yes, last, destructive | Already in Participants |

- Swipe actions are on rows. The hero card gets the long-press menu but no swipe (a swipe across a large card is unexpected).
- **Shared close logic.** Toggling closed and generating the recap move out of `TripDetailView` into one main-actor helper (e.g. `TripLifecycle.setClosed(_:to:context:)`) used by the list, the hero menu and the trip screen. On close it saves, then generates the recap exactly as `TripDetailView.generateRecap()` does today (owner-only, skip when `RecapStats` is empty, stamp `recapGeneratedDate` even when the model returns nil). An in-flight guard keyed by `NSManagedObjectID` replaces the per-view `isGeneratingRecap`, so two triggers can't generate twice.
- **Delete from the trip screen** pops back to the list before deleting (via a callback like the existing `onLeave`), so the detail view never shows a deleted object. Deletion itself uses the same code path as the list.
- Saves go through `viewContext.save(contextInfo:)` as today, so `transactionAuthor` stays `PersistenceController.appTransactionAuthor`.

### 6. Visual system (app-wide)

- **`Theme.green` darkens** so that white text meets **≥ 4.5:1 at every point of the panel gradient**. Candidate base: `Color(red: 0.11, green: 0.46, blue: 0.24)` (5.7:1). Final value is chosen by measuring rendered pixels, not by assumption.
- **Panel gradient.** Replace `Theme.green.gradient` and `Theme.closedGray.gradient` (SwiftUI's `.gradient` *lightens* the top) with a shared `Theme.panel(closed:)` that returns a `LinearGradient` from the base color down to a slightly darker shade. Used by the hero card, `RecapCardContent`, the Siri snippets (`SnippetStyle.panel`) and anything else that drew `Theme.green.gradient` with white text. `WhatsNewSheet`'s tint and icon backgrounds pick up the darker green automatically.
- **`RegionProgressBars`** (new view, `Views/`): two labelled bars, "US 7/51" and "CA 1/13", single-hue (white on the green panel). It takes counts and totals, and its color comes from the environment's foreground style so it works on panels and plain backgrounds. Replaces `DualProgressRingView` in the hero card and in `IntentSnippets.TripRing` (renamed to suit). `DualProgressRingView.swift` is deleted.
- Manual `.opacity(0.7/0.85)` for hierarchy becomes hierarchical styles; `.caption2` is removed from these views.
- `Theme.closedGray` stays for the closed Siri snippet panel only. Past trips in the list are system rows and don't use it.

### 7. Out of scope

- Data model changes, including a `closedDate` attribute.
- A separate per-user archive / hide.
- iPad-specific layout (the inset list adapts by itself).
- Sort or filter controls beyond search.
- Plate grid, notes, map, recap screens (other than the shared gradient and the Delete action).

## Constraints honored

- No `.xcdatamodeld` change → no CloudKit schema deploy.
- Swift 6 mode, `MainActor` default isolation, zero warnings. New `Trip` extensions are `nonisolated`. No `@unchecked Sendable` or `nonisolated(unsafe)`.
- No `ShareLink` moves (sharp edge 8). The trip screen's new Delete is a plain `Button` in the overflow menu, which is safe.
- No `project.pbxproj` edits; new files are picked up by the synchronized root group.
- Privacy invariants untouched.

## Verification

There are no test targets. The gate is a build plus a scripted simulator pass:

1. `xcodebuild … build` with **zero warnings**.
2. Seed a simulator (method in auto-memory "Simulator screenshot seeding") with about 8 trips: 2 open (one with recent sightings, one older), 1 shared/joined, 5 closed across 2026 and 2025, one with no sightings.
3. Screenshots: light and dark, at Large and AX3 text sizes — list, hero, rows, search visible.
4. `idb` taps: the hero card opens the trip; a row opens its trip; leading swipe closes a trip (it moves to Past Trips and gets a recap); trailing swipe shows the Delete alert; long-press shows the menu; Delete from the trip screen pops to the list and removes the trip.
5. Contrast: sample the lightest pixel of the hero panel and the recap card from screenshots and compute the white-text contrast (must be ≥ 4.5:1).
6. Siri snippet: build passes; on-device check of a "how many plates" snippet goes onto #61's device-check list.
