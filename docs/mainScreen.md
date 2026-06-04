# Main Screen (Trip List)

The app's main screen is a grid of trip "tiles." It is implemented across two files:

- `ContentView.swift` — the host screen: navigation, grid layout, `+` button, empty state, and delete confirmation.
- `TripCardView.swift` — the individual tile rendered for each trip.

The user-visible navigation title is **Road Trips**.

## Layout

`ContentView` is wrapped in a `NavigationStack` and renders a `LazyVGrid` of `TripCardView` tiles. The grid uses an adaptive column (`minimum: 160, maximum: 200`, spacing 16), so it reflows from one column on small phones up to multiple columns on larger devices and iPad.

Trips come from a single `@FetchRequest` ordered by:
1. `isClosed` ascending — open trips appear before closed/locked trips.
2. `createdDate` descending — newest first within each group.

Because the app uses two Core Data stores (private + shared) backed by `NSPersistentCloudKitContainer`, the fetch spans both. Trips you own and trips shared with you appear together in this same grid.

Tapping a tile pushes `TripDetailView` for that trip via `NavigationLink(value: trip.objectID)`. A long-press (context menu) on a tile reveals **Delete Trip**, which prompts an "Are you sure?" alert before deleting. Deletion goes through `viewContext.delete(...)` and saves immediately.

## The "+" Button

The `+` button lives in the navigation bar's primary toolbar slot. It calls `addTrip()` in `ContentView`, which:

1. Creates a new `Trip` entity in the view context.
2. Assigns it to the **private** persistent store (so it lives in the user's iCloud private database, not the shared one).
3. Saves the context.
4. Navigates immediately into `TripDetailView` for the new trip, with `isNewTrip: true` so the detail view can show first-run UI (such as prompting for a name).

When there are no trips at all, the screen instead shows a `ContentUnavailableView` with a "Create Trip" button that triggers the same `addTrip()` flow. The `+` button itself also pulses (`.symbolEffect(.pulse)`) while the trip list is empty, to draw attention.

## Share-Acceptance Errors

`ContentView` also surfaces CloudKit share-acceptance errors. If the user taps a share link and acceptance fails (for example, an expired or revoked share), `PersistenceController.shareAcceptanceError` is set and `ContentView` presents a "Share Error" alert with the message.

## The Tiles (`TripCardView`)

Each tile is a vertical card with a fixed aspect ratio (`0.85`), rounded corners (16 pt), white text on a colored gradient background, and four logical regions stacked top-to-bottom.

### 1. Card color
- **Open trip** → green (`Color(red: 0.2, green: 0.65, blue: 0.35)`).
- **Closed trip** → mid grey (`Color(white: 0.38)`).

### 2. Header
- **Trip name** — title3, bold, up to 2 lines, scales down to 0.8 if needed.
- **Lock icon** (`lock.fill`) — shown only when `trip.isClosed` is true.
- **Created date** — caption-styled date next to the lock.
- **Observation count badge** — shown only when there is at least one observation. Speech-bubble icon (`text.bubble.fill`) plus the total count. If there are observations created since the user last opened this trip's observations, a small **orange dot** is overlaid on the badge to signal "new." The "last viewed" timestamp is stored per-trip in `UserDefaults` under the key `lastViewedObservations_<tripID>`.
- **Participants badge** — a `person.2.fill` icon plus a count, shown only when the trip has more than one participant (i.e. it is being shared).

### 3. Recent flags strip
A horizontal row of up to **5 most-recent plate sightings** for the trip, rendered as small (28×18) flag thumbnails with a thin white border and slight overlap. Newest sighting is on the left. The image asset name is derived from `locationName` (lowercased, spaces replaced with underscores), with `flag` as the fallback. This whole row is hidden when there are no sightings yet.

### 4. Dual progress rings (`DualProgressRingView`)
A 68×68 composite ring in the bottom-leading area of the card, with two concentric arcs:

- **Outer ring (US)** — progress = `usSeenCount / 50`. Color thresholds: red ≤ 15 seen, yellow ≤ 30 seen, green > 30.
- **Inner ring (Canada)** — progress = `caSeenCount / 13` (10 provinces + 3 territories). Color thresholds: red ≤ 4 seen, yellow ≤ 8 seen, green > 8.

The center of the ring shows two lines of text: `US <seen>/<total>` and `CA <seen>/<total>`.

Counts are computed by intersecting `trip.plateSightings` against the canonical lists in `Location.usStates` and `Location.canadaLocations` (defined in `Services/Location.swift`).

### Accessibility
Tiles combine their children for VoiceOver and read out as: *"<name>, <usSeen> of <usTotal> US plates, <caSeen> of <caTotal> Canadian plates[, closed]"*. The flag strip and lock/people icons are marked `accessibilityHidden` so they don't add noise.

## What Data Lives in a Trip

A `Trip` (Core Data entity, see `Models/Trip+CoreDataProperties.swift`) owns the entire object graph for a road trip. The fields and relationships are:

### Trip
| Field | Type | Notes |
|---|---|---|
| `tripID` | `UUID?` | Stable identifier; used as the key for per-trip `UserDefaults` (e.g. last-viewed timestamps). |
| `name` | `String` | Display name shown in the tile header and detail view. |
| `createdDate` | `Date?` | Used for the tile date and for ordering in the grid. |
| `isClosed` | `Bool` | When true, the trip is locked: shown grey with a lock icon, and `TripDetailView` becomes read-only. |
| `plateSightings` | `NSSet?` → `[PlateSighting]` | License plates spotted on this trip. |
| `observationEntries` | `NSSet?` → `[ObservationEntry]` | Append-only notes/observations. |
| `participants` | `NSSet?` → `[TripParticipant]` | People sharing this trip via CloudKit. |

Convenience accessors `plateSightingsArray`, `observationEntriesArray`, and `participantsArray` return the relationships sorted by date (sightings by `seenDate`, observations by `createdDate`, participants by `joinedDate`).

### PlateSighting
A single tap-to-mark event for a US state or Canadian province/territory.

| Field | Type | Notes |
|---|---|---|
| `locationCode` | `String` | e.g. `"CA"`, `"ON"`. Matched against `Location.usStates` / `Location.canadaLocations` to drive ring counts. |
| `locationName` | `String` | e.g. `"California"`. Lowercased + underscored to look up the flag image asset (`flagImageName`). |
| `latitude` | `Double` | GPS latitude where the plate was seen. |
| `longitude` | `Double` | GPS longitude where the plate was seen. |
| `seenDate` | `Date?` | When the plate was marked. Drives "recent 5" on the tile and the sightings map. |
| `spottedByName` | `String?` | The display name of the participant who marked it. |
| `trip` | `Trip?` | Inverse relationship to the owning trip. |

`coordinate` returns a `CLLocationCoordinate2D`, and `hasValidCoordinate` is true when latitude/longitude are non-zero (so sightings without GPS aren't plotted on the map).

### ObservationEntry
Append-only notes attached to the trip. Surfaced on the tile via the bubble badge and the orange "new since last viewed" dot.

| Field | Type | Notes |
|---|---|---|
| `category` | `String` | The bucket the observation belongs to (e.g. weirdest thing, coolest car, funniest billboard). |
| `authorName` | `String` | Per-trip display name of whoever wrote it. |
| `text` | `String` | The note body. |
| `createdDate` | `Date?` | Used for ordering and for the "new since last viewed" comparison. |
| `imageData` | `Data?` | Optional full-size attached photo. |
| `thumbnailData` | `Data?` | Optional thumbnail used in lists. |
| `trip` | `Trip?` | Inverse relationship. |

### TripParticipant
One row per person who is part of the trip. Drives the `person.2.fill` badge on the tile (shown when count > 1).

| Field | Type | Notes |
|---|---|---|
| `displayName` | `String` | The per-trip name the participant chose for themselves. |
| `cloudKitUserID` | `String` | CloudKit user identifier used to resolve the participant. |
| `joinedDate` | `Date?` | When they joined the share. |
| `trip` | `Trip?` | Inverse relationship. |

## Related Files

- `Views/TripDetailView.swift` — destination when a tile is tapped.
- `Views/PlateSightingsGrid.swift` — the tap-to-mark grid inside the detail view.
- `Views/PlateSightingsMapView.swift` — sightings map.
- `Views/ObservationsSection.swift`, `ObservationRow.swift` — observations UI.
- `Views/ParticipantsView.swift`, `CloudSharingView.swift`, `JoinTripNameView.swift` — sharing and participant naming.
- `Services/Location.swift` — canonical list of US states and Canadian provinces/territories used for counts.
