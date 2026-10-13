# Plate Passport (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Families who play on every trip can see what their trips add up to (Plate Passport), get a moment when they spot a plate for the first time ever, and get a hint about which plates to watch for on the current trip.

**Architecture:** One value type, `PlateHistory`, computed from all fetched trips. It holds distinct plates per trip, how many trips saw each plate, and which trip saw each plate first. The trip list, the new Passport screen and the plate grid each build it from their own `@FetchRequest`. There's no caching and no model change: a trip has at most 64 distinct plates. Task 1 adds the "distinct plates per trip" rule (`Trip.seenRegionCodes`, `Trip.firstSightingByCode`) and fixes the recap's counts with it (#77).

**Tech Stack:** SwiftUI (iOS 26.1 deployment target), Core Data + `NSPersistentCloudKitContainer`, Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

**Spec:** `docs/superpowers/specs/2026-10-13-platePassport.md` (issue #78, also #77). Read it before starting any task. Mockups: https://claude.ai/artifact/7MJSd11dtG1DDPNS1nHwcV (the chosen options are 1B, 2A, 3B, 4A).

## Global Constraints

- Swift 6 mode, default `MainActor` isolation, **zero warnings**. Never use `@unchecked Sendable` or `nonisolated(unsafe)`.
- Extensions of managed objects that only touch Core Data are `nonisolated` (#47). Code that uses `Location`, `UserDefaults` or views stays on the default (main actor).
- **No data model change.** Don't touch `.xcdatamodeld`.
- **Don't edit `project.pbxproj`.** New `.swift` files in `myRoadTripTracker/myRoadTripTracker/` are picked up automatically.
- Every save goes through `viewContext.save(contextInfo:)`.
- White text on a panel uses `Theme.panelSecondaryText` for secondary text, never `.secondary`.
- Avoid `.caption2`. Prefer `.bold()` over `.fontWeight(.bold)`.
- Fills behind content on the grouped background use `Color(.secondarySystemGroupedBackground)`, not `.background`, because `.background` is black on black in dark mode.
- One type per file. Doc comments explain *why* and cite the issue (`#78`, `#77`), in the style of the existing code.
- Commit messages: imperative subject, `(#78)` or `(#77)` in the subject. **No `Claude-Session:`, `Co-Authored-By` or any AI attribution lines.**
- There are **no test targets**. Don't create one. Each task's gate is the build plus the simulator check written in that task.
- Work on branch `platePassport`. Commit at the end of each task.

## Shared tooling (already in place; don't recreate)

`SCRATCH=/private/tmp/claude-501/-Users-sam-code-apple-myRoadTripTracker/282fb750-6d95-4319-9934-5bc0466a68cc/scratchpad`
`DEV=AA150836-B7E7-48C6-9CAE-4404B6DAB457` (iPhone 17, iOS 26.5)

- **Build** (from the repo root `/Users/sam/code/apple/myRoadTripTracker`, timeout 600000 ms):
  ```bash
  xcodebuild -project myRoadTripTracker/myRoadTripTracker.xcodeproj -scheme myRoadTripTracker \
    -destination 'platform=iOS Simulator,id=AA150836-B7E7-48C6-9CAE-4404B6DAB457' \
    -derivedDataPath $SCRATCH/dd build 2>&1 | grep -E "warning:|error:|BUILD (SUCCEEDED|FAILED)" | sort -u
  ```
  Expected: exactly `** BUILD SUCCEEDED **` and no `warning:` lines.
- **Seed and launch:** `$SCRATCH/seedSim.sh <full|first> <light|dark> <large|accessibility-extra-extra-extra-large>` (timeout 300000 ms). It installs the build from `$SCRATCH/dd`, replaces every trip with the scenario below, skips onboarding and the Siri card, sets appearance and text size, and launches the app. Build first.
- **Screenshot:** `xcrun simctl io $DEV screenshot $SCRATCH/<name>.png`. Images are 1206×2622 px = 402×874 pt, so divide pixels by 3 to get points. Look at every screenshot you take with the Read tool.
- **Taps:** run `idb connect $DEV` once. Then `idb ui tap --udid $DEV <x> <y>` (in points), `idb ui swipe --udid $DEV x1 y1 x2 y2 --duration 0.4`, and `idb ui describe-all --udid $DEV` for labels and frames. Toolbar items don't appear in describe-all, so find them from a screenshot.

**Scenario `full`:** 6 trips, 46 of 64 plates ever seen (US 42/51, CA 4/13). The never-seen plates are AK HI ND VT RI DE WY ME NH, plus NL PE NT NU YT NS NB SK MB. Seen once: MT ID NV SD AB BC.

| Trip | State | Distinct plates | Notes |
|---|---|---|---|
| Fall Colors 2026 | open (hero) | 18 | OH PA MI IN FL NY IL KY TN GA WV NC VA WI MO ON SD MT. **MT and SD are first-ever on this trip.** |
| Spring Break 2026 | closed, Mar 14–21 2026 | 25 | **Ohio is in it twice** (a sync duplicate, for #77) |
| Summer Out West 2025 | closed | 26 | |
| Lake Michigan Weekend 2025 | closed | 25 | |
| Thanksgiving at Grandma's 2024 | closed | 26 | |
| Florida Spring Break 2024 | closed, from Mar 9 2024 | 26 | earliest sighting, so "since March 2024" |

Expected history numbers for `full`: 6 trips; typical trip = median of the 5 closed counts (25, 25, 26, 26, 26) = **26**; record = **26: Summer Out West 2025** (three trips have 26; the tie goes to the most recent); never seen = **18**; usual suspects led by Indiana, Michigan, Ohio, Pennsylvania at **6 of 6**. Fall Colors' "Watch for" (5 other trips) leads with plates at 4 of 5 (e.g. California, Texas).

**Scenario `first`:** one open trip, "First Trip", with 5 plates (OH PA MI IN KY) and no other trips.

## Review Focus

1. **First-ever trip.** With one trip (scenario `first`), there are no 1ST badges, no pill, no toast, no Watch-for strip, and no Passport row. Pinned in Tasks 2, 3 and 4.
2. **Sync duplicates.** Two sightings of Ohio on Spring Break 2026 count once in the recap, the Passport and the history. Pinned in Tasks 1 and 2.
3. **Unmarking a first-ever plate.** Long-press → Remove sighting on Montana in Fall Colors removes its 1ST badge, and the pill drops from 2 to 1. Pinned in Task 3.
4. **Accessibility text size and dark mode** on the Passport screen and the Watch-for strip: nothing clipped, tiles stack, and fills stay visible on the dark grouped background. Pinned in Tasks 2 and 4.
5. **Marking from the strip.** Tapping a Watch-for card marks the plate on this trip (its grid tile turns seen), the card leaves the strip, and the plate isn't marked twice on a quick double-tap. Pinned in Task 4.

---

### Task 1: Count each plate once per trip, and fix the recap (#77)

**Outcome:** a trip's plate count means distinct plates everywhere, so the recap agrees with the trip list and Siri even when sync duplicates a sighting.

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/Models/Trip+Activity.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Services/TripBadges.swift:11-14`
- Modify: `myRoadTripTracker/myRoadTripTracker/Services/RecapStats.swift:25-65`
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/PlateSightingsGrid.swift:21-31`

**Interfaces:**
- Produces: `Trip.seenRegionCodes: Set<String>` and `Trip.firstSightingByCode: [String: PlateSighting]` (both `nonisolated`). Tasks 2–4 use them.

- [ ] **Step 1: Add the two accessors to `Trip+Activity.swift`**

Insert inside the existing `nonisolated extension Trip`, after `activitySpan`:

```swift
    /// The plates seen on this trip, one per region. Sync can leave two sightings of one
    /// plate (two phones marking it at once), so anything that counts plates counts these (#77).
    var seenRegionCodes: Set<String> {
        Set(((plateSightings as? Set<PlateSighting>) ?? []).map(\.locationCode))
    }

    /// Each seen region's sighting, keyed by code, in one unsorted pass (#38). With
    /// duplicates, the earliest sighting wins, so it's the one the grid opens and the recap
    /// credits.
    var firstSightingByCode: [String: PlateSighting] {
        let set = (plateSightings as? Set<PlateSighting>) ?? []
        return Dictionary(set.map { ($0.locationCode, $0) }) { first, second in
            (first.seenDate ?? .distantPast) <= (second.seenDate ?? .distantPast) ? first : second
        }
    }
```

- [ ] **Step 2: Use them in `TripBadges.swift` and `PlateSightingsGrid.swift`**

In `TripBadges.swift`, replace the body of `regionCounts`:

```swift
    var regionCounts: (us: Int, ca: Int) {
        let codes = seenRegionCodes
        return (codes.intersection(Self.usCodes).count, codes.intersection(Self.caCodes).count)
    }
```

In `PlateSightingsGrid.swift`, replace the `sightingsByCode` property and its doc comment with:

```swift
    /// Each seen region's sighting, keyed by code; the earliest wins with duplicates.
    private var sightingsByCode: [String: PlateSighting] { trip.firstSightingByCode }
```

- [ ] **Step 3: Count distinct plates in `RecapStats.init`**

Replace the lines from `usTotalCount = usCodes.count` through the end of the per-spotter tallies, and the rare-catches block, with:

```swift
        usTotalCount = usCodes.count
        caTotalCount = caCodes.count

        // One sighting per plate: a sync duplicate would otherwise count twice, here and in
        // the AI narrative, and disagree with the trip list (#77).
        let firstSightings = trip.firstSightingByCode
        let codes = Set(firstSightings.keys)
        usSeenCount = codes.intersection(usCodes).count
        caSeenCount = codes.intersection(caCodes).count
        totalSightings = codes.count

        // Day span (inclusive). plateSightingsArray is sorted ascending by seenDate.
        let dates = sightings.compactMap(\.seenDate)
        if let first = dates.first, let last = dates.last {
            let cal = Calendar.current
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: first), to: cal.startOfDay(for: last)).day ?? 0
            dayCount = days + 1
        } else {
            dayCount = 0
        }

        // Per-spotter tallies, crediting each plate once: to whoever marked it first.
        var counts: [String: Int] = [:]
        for s in firstSightings.values {
            let name = s.spottedByName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            counts[name, default: 0] += 1
        }
        spotterTallies = counts
            .map { SpotterTally(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }

        // Rare catches (unique region names, ordered by the canonical list).
        let seenRareCodes = codes.intersection(Self.rareCodes)
        rareCatches = Location.allLocations
            .filter { seenRareCodes.contains($0.code) }
            .map(\.name)
```

Also change the doc comment on `totalSightings` to say what it now holds:

```swift
    let totalSightings: Int           // distinct plates; a sync duplicate counts once (#77)
```

- [ ] **Step 4: Gate — build, then check the recap of the trip with the duplicate**

Run the build. Expected: `** BUILD SUCCEEDED **`, no warnings.

Run `$SCRATCH/seedSim.sh full light large`. Tap **Spring Break 2026** in Past Trips, open the overflow menu (top right) → **Trip Recap**, and screenshot `t1_recap.png`. Expected: the US/Canada numbers match the trip list row for Spring Break 2026 (**US 24 · CA 1**). On `main`, the recap showed US 25, counting Ohio twice.

- [ ] **Step 5: Commit**

```bash
git add -A myRoadTripTracker/myRoadTripTracker
git commit -m "Count each plate once per trip in the recap (#77)"
```

---

### Task 2: Plate history, the Passport row and the Passport screen

**Outcome:** from the Road Trips screen you can open Plate Passport and see what all your trips add up to (spec §1–2).

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/Services/PlateHistory.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/Services/PlateCount.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/Services/TripPlateTotal.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/Views/PassportRoute.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/Views/PassportRow.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/Views/PlatePassportView.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Services/CoreDataHelpers.swift` (append)
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/ContentView.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/PlateChips.swift`

**Interfaces:**
- Consumes: `Trip.firstSightingByCode`, `Trip.seenRegionCodes` (Task 1).
- Produces (used by Tasks 3–5):
  - `struct PlateHistory { init(trips: some Sequence<Trip>) }` with `trips: [TripPlateTotal]`, `tripCounts: [String: Int]`, `collected: Set<String>`, `showsPassport: Bool`, `otherTripCount(than: Trip) -> Int`, `isFirstEver(_ code: String, on: Trip) -> Bool`, `watchFor(on: Trip, limit: Int) -> [PlateCount]`.
  - `struct PlateCount: Identifiable { let location: Location; let trips: Int }`
  - `extension Notification { var touchesTripsOrSightings: Bool }`

- [ ] **Step 1: Create `Services/TripPlateTotal.swift`**

```swift
import CoreData

/// One trip's distinct plate count, for Plate Passport's comparisons (#78).
struct TripPlateTotal: Identifiable {
    let id: NSManagedObjectID
    let name: String
    let plateCount: Int
    let isOpen: Bool
    let lastActivity: Date
}
```

- [ ] **Step 2: Create `Services/PlateCount.swift`**

```swift
/// A plate and how many trips saw it (#78).
struct PlateCount: Identifiable {
    let location: Location
    let trips: Int
    var id: String { location.code }
}
```

- [ ] **Step 3: Create `Services/PlateHistory.swift`**

```swift
import CoreData

/// What your trips add up to, across every trip on this phone: your own and the ones shared
/// with you (#78). A plate counts once per trip (`firstSightingByCode`), so a sync duplicate
/// never counts twice (#77). Group-level only: trips are shared ad hoc and `spottedByName` is
/// free text, so there's no person to total across trips.
///
/// Cheap enough to rebuild on every render: at most 64 plates per trip.
struct PlateHistory {
    /// Trips with at least one plate, most plates first; ties go to the more recent trip.
    let trips: [TripPlateTotal]
    /// How many trips saw each plate, by region code.
    let tripCounts: [String: Int]
    /// The trip with each plate's earliest sighting, by region code. A sighting with no date
    /// (a partly synced record) never counts as first.
    let firstTripByCode: [String: NSManagedObjectID]
    /// The earliest dated sighting on any trip.
    let since: Date?

    init(trips: some Sequence<Trip>) {
        var totals: [TripPlateTotal] = []
        var counts: [String: Int] = [:]
        var firsts: [String: (date: Date, trip: NSManagedObjectID)] = [:]
        var earliest: Date?
        for trip in trips where !trip.isDeleted && trip.managedObjectContext != nil {
            let sightings = trip.firstSightingByCode
            guard !sightings.isEmpty else { continue }
            totals.append(TripPlateTotal(
                id: trip.objectID,
                name: trip.name,
                plateCount: sightings.count,
                isOpen: !trip.isClosed,
                lastActivity: trip.lastActivity
            ))
            for (code, sighting) in sightings {
                counts[code, default: 0] += 1
                guard let date = sighting.seenDate else { continue }
                if earliest.map({ date < $0 }) ?? true { earliest = date }
                if firsts[code].map({ date < $0.date }) ?? true {
                    firsts[code] = (date, trip.objectID)
                }
            }
        }
        self.trips = totals.sorted {
            $0.plateCount != $1.plateCount ? $0.plateCount > $1.plateCount : $0.lastActivity > $1.lastActivity
        }
        tripCounts = counts
        firstTripByCode = firsts.mapValues(\.trip)
        since = earliest
    }

    /// Every plate any trip has seen.
    var collected: Set<String> { Set(tripCounts.keys) }

    var usCollected: Int { Location.usStates.count(where: { tripCounts[$0.code] != nil }) }
    var caCollected: Int { Location.canadaLocations.count(where: { tripCounts[$0.code] != nil }) }

    /// Plates no trip has seen, in the app's usual order.
    var neverSeen: [Location] { Location.allLocations.filter { tripCounts[$0.code] == nil } }

    /// Plates exactly one trip saw, in the app's usual order.
    var seenOnce: [Location] { Location.allLocations.filter { tripCounts[$0.code] == 1 } }

    /// Seen plates, on the most trips first, then by name.
    var byTripCount: [PlateCount] {
        Location.allLocations
            .compactMap { location in tripCounts[location.code].map { PlateCount(location: location, trips: $0) } }
            .sorted { $0.trips != $1.trips ? $0.trips > $1.trips : $0.location.name < $1.location.name }
    }

    /// The middle plate count of finished trips, rounded; nil until there are two of them.
    var typicalPlateCount: Int? {
        let counts = trips.filter { !$0.isOpen }.map(\.plateCount).sorted()
        guard counts.count >= 2 else { return nil }
        let mid = counts.count / 2
        if counts.count.isMultiple(of: 2) {
            return Int((Double(counts[mid - 1] + counts[mid]) / 2).rounded())
        }
        return counts[mid]
    }

    /// The trip with the most plates.
    var record: TripPlateTotal? { trips.first }

    /// Enough history to compare trips: two trips with plates.
    var hasComparisons: Bool { trips.count >= 2 }

    /// The trip list shows the Passport row once a finished trip has plates (spec §1).
    var showsPassport: Bool { trips.contains { !$0.isOpen } }

    /// Trips with plates other than `trip`.
    func otherTripCount(than trip: Trip) -> Int {
        trips.count(where: { $0.id != trip.objectID })
    }

    /// Whether `trip` saw this plate before any other trip did.
    func isFirstEver(_ code: String, on trip: Trip) -> Bool {
        firstTripByCode[code] == trip.objectID
    }

    /// Plates `trip` hasn't seen that other trips have, on the most trips first (spec §4).
    func watchFor(on trip: Trip, limit: Int = 8) -> [PlateCount] {
        let seen = trip.seenRegionCodes
        return Array(byTripCount.filter { !seen.contains($0.location.code) }.prefix(limit))
    }
}
```

- [ ] **Step 4: Share the "did a trip or sighting change" check**

Append to `Services/CoreDataHelpers.swift`:

```swift
// MARK: - Change Notifications

extension Notification {
    /// Whether an `NSManagedObjectContextObjectsDidChange` touched a trip or a plate
    /// sighting: what the trip list ranks by (#65) and what Plate Passport counts (#78).
    var touchesTripsOrSightings: Bool {
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]
        return keys.contains { key in
            guard let objects = userInfo?[key] as? Set<NSManagedObject> else { return false }
            return objects.contains { $0 is Trip || $0 is PlateSighting }
        }
    }
}
```

In `ContentView.swift`, delete the private `changesTripOrSighting(_:)` function and change its call site to `if note.touchesTripsOrSightings { listRevision &+= 1 }`.

- [ ] **Step 5: Create `Views/PassportRoute.swift`**

```swift
/// The navigation value that opens Plate Passport from the trip list (#78). A value, like
/// the trips' object IDs, so resetting the path (Siri opening a trip) pops it too.
enum PassportRoute: Hashable {
    case passport
}
```

- [ ] **Step 6: Create `Views/PassportRow.swift`**

```swift
import SwiftUI

/// The trip list's way into Plate Passport. It shows the headline numbers, so you see the
/// collection grow without opening it (#78).
struct PassportRow: View {
    let history: PlateHistory

    var body: some View {
        let trips = history.trips.count
        HStack(spacing: 12) {
            Image(systemName: "globe.americas.fill")
                .font(.title2)
                // Dark on amber: white on this amber is about 2:1.
                .foregroundStyle(Color(white: 0.12))
                .frame(width: 40, height: 40)
                .background(Theme.amber, in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Plate Passport")
                    .font(.headline)
                Text("\(history.collected.count) of \(Location.allLocations.count) plates \u{00B7} \(trips) \(trips == 1 ? "trip" : "trips")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 7: Show the row in `ContentView` and route to the screen**

In `tripList`, build the history next to the sections:

```swift
        let sections = TripListSections(trips: trips, matching: searchText)
        let history = PlateHistory(trips: trips)
```

Insert this section after the `sections.otherOpen` section and before the `ForEach(... sections.pastYears ...)`:

```swift
            if searchText.isEmpty, history.showsPassport {
                Section {
                    // A link, so the whole row is tappable and gets the list's chevron.
                    NavigationLink(value: PassportRoute.passport) {
                        PassportRow(history: history)
                    }
                }
            }
```

Next to the existing `.navigationDestination(for: NSManagedObjectID.self)`, add:

```swift
        .navigationDestination(for: PassportRoute.self) { _ in
            PlatePassportView()
        }
```

- [ ] **Step 8: Let `PlateChips` show seen plates that can't be tapped**

In `Views/PlateChips.swift`, make the tap action optional and only wrap chips in a button when there is one. Replace the property and the `ForEach` body:

```swift
    /// Opens a seen plate's sighting. Without it, chips are display-only (Plate Passport, #78).
    var onTap: ((Location) -> Void)? = nil

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(locations) { location in
                if isSeen, let onTap {
                    Button {
                        onTap(location)
                    } label: {
                        PlateChip(location: location, isSeen: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double-tap to view details")
                } else {
                    PlateChip(location: location, isSeen: isSeen)
                }
            }
        }
    }
```

Also update the type's doc comment to say seen chips open their sighting only when given `onTap`. The closed-trip call site in `PlateSightingsGrid` passes a trailing closure, which still compiles.

- [ ] **Step 9: Create `Views/PlatePassportView.swift`**

```swift
import CoreData
import SwiftUI

/// Plate Passport: what every trip on this phone adds up to (#78; spec §2). Read-only.
struct PlatePassportView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Trip.createdDate, ascending: false)])
    private var trips: FetchedResults<Trip>
    /// Bumped when a trip or sighting changes, so the numbers follow a sync while open. The
    /// fetch alone only republishes trip inserts and deletes (#65).
    @State private var revision = 0
    @State private var showsAllPlates = false

    private static let usualSuspectsShown = 6

    var body: some View {
        content
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Plate Passport")
            .onReceive(NotificationCenter.default.publisher(
                for: .NSManagedObjectContextObjectsDidChange, object: viewContext
            )) { note in
                if note.touchesTripsOrSightings { revision &+= 1 }
            }
    }

    private var content: some View {
        _ = revision // Read so a bump re-runs this body.
        let history = PlateHistory(trips: trips)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                collectionPanel(history)
                statTiles(history)
                if history.hasComparisons {
                    usualSuspects(history)
                }
                let never = history.neverSeen
                if !never.isEmpty {
                    section("Still hunting \u{00B7} \(never.count)") {
                        PlateChips(locations: never, isSeen: false)
                    }
                }
                let once = history.seenOnce
                if history.hasComparisons, !once.isEmpty {
                    section("Seen only once \u{00B7} \(once.count)") {
                        PlateChips(locations: once, isSeen: true)
                    }
                }
                if !history.trips.isEmpty {
                    tripsByPlates(history)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: Collection

    private func collectionPanel(_ history: PlateHistory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All-time collection")
                .font(.subheadline)
                .bold()
                .textCase(.uppercase)
                .foregroundStyle(Theme.panelSecondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(history.collected.count)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text("of \(Location.allLocations.count)")
                    .font(.title3)
                    .bold()
                    .foregroundStyle(Theme.panelSecondaryText)
            }
            RegionProgressBars(
                usSeen: history.usCollected,
                caSeen: history.caCollected,
                axis: dynamicTypeSize.isAccessibilitySize ? .vertical : .horizontal
            )
            if let since = history.since {
                let count = history.trips.count
                Text("\(count) \(count == 1 ? "trip" : "trips") since \(since.formatted(.dateTime.month(.wide).year()))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.panelSecondaryText)
            }
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel(), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    // MARK: Stat tiles

    private func statTiles(_ history: PlateHistory) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return layout {
            if let typical = history.typicalPlateCount {
                statTile("\(typical)", "plates on a typical trip")
            }
            if let record = history.record {
                statTile("\(record.plateCount)", "record: \(record.name)")
            }
            statTile("\(history.neverSeen.count)", "plates never seen")
        }
        // Equal-height tiles: each fills the row's height, which the tallest tile sets.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    // MARK: Usual suspects

    private func usualSuspects(_ history: PlateHistory) -> some View {
        let all = history.byTripCount
        let shown = showsAllPlates ? all : Array(all.prefix(Self.usualSuspectsShown))
        let tripCount = history.trips.count
        return section("Usual suspects") {
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, plate in
                    if index > 0 { Divider().padding(.leading, 52) }
                    suspectRow(plate, of: tripCount)
                }
                if all.count > Self.usualSuspectsShown {
                    Divider()
                    Button(showsAllPlates ? "Show fewer" : "Show all \(all.count) plates") {
                        withAnimation { showsAllPlates.toggle() }
                    }
                    .foregroundStyle(Theme.greenText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private func suspectRow(_ plate: PlateCount, of tripCount: Int) -> some View {
        HStack(spacing: 10) {
            Image(plate.location.flagImageName)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 20)
                .clipShape(.rect(cornerRadius: 3))
            Text(plate.location.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            if !dynamicTypeSize.isAccessibilitySize {
                Capsule()
                    .fill(.fill)
                    .frame(width: 54, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.amber, Theme.gold],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: 54 * Double(plate.trips) / Double(max(tripCount, 1)))
                    }
            }
            Text("\(plate.trips) of \(tripCount)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plate.location.name)
        .accessibilityValue("Seen on \(plate.trips) of \(tripCount) trips")
    }

    // MARK: Trips by plates

    private func tripsByPlates(_ history: PlateHistory) -> some View {
        let most = max(history.record?.plateCount ?? 1, 1)
        return section("Trips by plates") {
            VStack(spacing: 0) {
                ForEach(Array(history.trips.enumerated()), id: \.element.id) { index, total in
                    if index > 0 { Divider().padding(.leading, 12) }
                    // Opens the trip through the trip list's destination for object IDs.
                    NavigationLink(value: total.id) {
                        tripBar(total, most: most)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private func tripBar(_ total: TripPlateTotal, most: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(total.name)
                    .lineLimit(2)
                if total.isOpen {
                    Text("in progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(total.plateCount)")
                    .bold()
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Capsule()
                .fill(.fill)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(total.isOpen
                                  ? AnyShapeStyle(LinearGradient(colors: [Theme.amber, Theme.gold],
                                                                 startPoint: .leading, endPoint: .trailing))
                                  : AnyShapeStyle(Theme.greenText))
                            .frame(width: proxy.size.width * Double(total.plateCount) / Double(most))
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(total.name)
        .accessibilityValue("\(total.plateCount) plates\(total.isOpen ? ", in progress" : "")")
    }

    // MARK: Layout

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .bold()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            content()
        }
    }
}
```

- [ ] **Step 10: Gate — build, then check the row and the screen in both modes, at large and accessibility sizes, and in the `first` scenario**

Run the build. Expected: `** BUILD SUCCEEDED **`, no warnings.

1. `$SCRATCH/seedSim.sh full light large`, then screenshot `t2_list.png`. Expected: a **Plate Passport** row after the hero and before Past Trips, reading "46 of 64 plates · 6 trips", with an amber globe tile and a chevron.
2. Tap anywhere on the row's text (not the chevron), then screenshot `t2_passport_top.png`. Expected: the screen title "Plate Passport" and a green panel with "46 of 64", US 42/51, CA 4/13, and "6 trips since March 2024". Below it, three equal-height tiles: **26** "plates on a typical trip", **26** "record: Summer Out West 2025", and **18** "plates never seen".
3. Swipe up and screenshot `t2_passport_lists.png`. Expected: Usual suspects with Indiana, Michigan, Ohio and Pennsylvania at "6 of 6", then two more rows, then "Show all 46 plates". Still hunting · 18 as grey chips. Seen only once · 6 as colour chips. Trips by plates with 6 rows, Fall Colors 2026 marked "in progress" with an amber bar. Spring Break 2026 shows **25**, not 26 (the duplicate counts once).
4. Tap "Show all 46 plates". Expected: 46 rows and a "Show fewer" button. Tap **Fall Colors 2026** in Trips by plates. Expected: that trip opens. Go back twice. Expected: the trip list.
5. `$SCRATCH/seedSim.sh full dark accessibility-extra-extra-extra-large`, open the Passport, and screenshot the top and one swipe down. Expected: the tiles stack vertically; no text is clipped or truncated to "…" in the tiles; the tile and list fills are visible against the black background; there are no bars in the suspect rows.
6. `$SCRATCH/seedSim.sh first light large`, then screenshot `t2_first.png`. Expected: **no** Plate Passport row, since the only trip is open.

- [ ] **Step 11: Commit**

```bash
git add -A myRoadTripTracker/myRoadTripTracker
git commit -m "Plate Passport: history across trips, a row on the trip list, and its screen (#78)"
```

---

### Task 3: First time ever: toast, 1ST badge and pill

**Outcome:** marking a plate no trip has seen before feels like an event, and the trip remembers which plates were firsts (spec §3).

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/Views/FirstEverToast.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/Views/FirstEverBadge.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/PlateTileView.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/PlateSightingsGrid.swift`

**Interfaces:**
- Consumes: `PlateHistory(trips:)`, `.tripCounts`, `.collected`, `.otherTripCount(than:)`, `.isFirstEver(_:on:)` (Task 2); `Trip.seenRegionCodes` (Task 1).
- Produces: `PlateSightingsGrid` gains `@FetchRequest private var allTrips: FetchedResults<Trip>`, and `history` / `showsFirsts` locals in `body`. Task 4 uses them.

- [ ] **Step 1: Create `Views/FirstEverBadge.swift`**

```swift
import SwiftUI

/// The gold "1ST" capsule on a plate this trip saw before any other trip did (#78).
struct FirstEverBadge: View {
    var body: some View {
        Text("1ST")
            .font(.system(.caption, design: .rounded, weight: .heavy))
            // Dark brown on gold, about 9:1; white on gold is under 2:1.
            .foregroundStyle(Color(red: 0.23, green: 0.15, blue: 0))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                LinearGradient(colors: [Theme.gold, Theme.amber], startPoint: .top, endPoint: .bottom),
                in: .capsule
            )
            .accessibilityHidden(true)
    }
}
```

- [ ] **Step 2: Create `Views/FirstEverToast.swift`**

```swift
import SwiftUI

/// The banner after marking a plate no trip on this phone has seen (#78).
struct FirstEverToast: View {
    let location: Location
    /// The collection's size including this plate.
    let collectedCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(location.flagImageName)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 24)
                .clipShape(.rect(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 1) {
                Text("First time ever: \(location.name)!")
                    .font(.subheadline)
                    .bold()
                Text("Your collection is now \(collectedCount) of \(Location.allLocations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 3: Give `PlateTileView` a first-ever flag**

Add the stored property after `isRevealing`:

```swift
    /// This trip saw the plate before any other trip did; it wears a 1ST badge (#78).
    var isFirstEver = false
```

Include it in `==`:

```swift
        lhs.location == rhs.location && lhs.isSeen == rhs.isSeen && lhs.isRevealing == rhs.isRevealing
            && lhs.isFirstEver == rhs.isFirstEver
```

Add a badge overlay in `tileContent`, after the checkmark overlay. It appears with the checkmark, so it waits for the reveal:

```swift
        .overlay(alignment: .topLeading) {
            if isFirstEver && showCheckmark {
                FirstEverBadge()
                    .offset(x: -4, y: -6)
            }
        }
```

Extend the accessibility label:

```swift
        .accessibilityLabel("\(location.name), \(isSeen ? "seen" : "not seen")\(isSeen && isFirstEver ? ", first time ever" : "")")
```

- [ ] **Step 4: Fetch every trip in `PlateSightingsGrid` and build the history**

Add these properties:

```swift
    /// Every trip, for what the history says about this one: first-ever plates and what to
    /// watch for (#78). Reads in `markAsSeen` see the current results, not a past render's.
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Trip.createdDate, ascending: false)])
    private var allTrips: FetchedResults<Trip>
    /// The plate behind the "First time ever" banner, and the collection size it made.
    @State private var firstEver: Location?
    @State private var firstEverCount = 0
```

In `body`, after `let seenCodes = …`, add:

```swift
        let history = PlateHistory(trips: allTrips)
        // Firsts mean something only next to another trip; on your first trip every plate
        // would be one (spec §3).
        let showsFirsts = history.otherTripCount(than: trip) > 0
        let firstCodes = showsFirsts ? seenCodes.filter { history.isFirstEver($0, on: trip) } : []
```

Pass `firstCodes` through `sectionView` → `openSectionView` → `tile(for:seenCodes:firstCodes:)`. Add a `firstCodes: Set<String>` parameter to each, and in `tile` pass `isFirstEver: firstCodes.contains(location.code)` to `PlateTileView` after `isRevealing:`. The closed-trip path ignores it.

At the top of the `VStack(spacing: 16)`, after the closed-trip banner, add the pill:

```swift
                if !firstCodes.isEmpty {
                    HStack(spacing: 6) {
                        FirstEverBadge()
                        Text("\(firstCodes.count) new to your collection this trip")
                            .font(.subheadline)
                            .bold()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.fill, in: .capsule)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
```

- [ ] **Step 5: Toast from `markAsSeen`**

In `markAsSeen`, after the `guard` and before creating the sighting, add:

```swift
        // Checked before the save, while this trip doesn't have the plate yet. Only local
        // marks get the banner; a collaborator's or Siri's arrive without one (spec §3).
        let history = PlateHistory(trips: allTrips)
        let isFirstEver = history.otherTripCount(than: trip) > 0 && history.tripCounts[location.code] == nil
```

After `viewContext.save(contextInfo: "markAsSeen")`, add:

```swift
        if isFirstEver {
            withAnimation(.spring) {
                firstEverCount = history.collected.count + 1
                firstEver = location
            }
            AccessibilityNotification.Announcement("First time ever: \(location.name)").post()
        }
```

Attach the banner to the `ScrollView` in `body`, after `.sheet(item:)`:

```swift
        .overlay(alignment: .bottom) {
            if let firstEver {
                FirstEverToast(location: firstEver, collectedCount: firstEverCount)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: firstEver) {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation { self.firstEver = nil }
                    }
            }
        }
```

- [ ] **Step 6: Gate — build, then check the badges, the pill, the toast, unmarking, and the `first` scenario**

Run the build. Expected: `** BUILD SUCCEEDED **`, no warnings.

1. `$SCRATCH/seedSim.sh full light large`. Open **Fall Colors 2026** and screenshot `t3_pill.png`. Expected: the pill "2 new to your collection this trip" above US States & DC.
2. Scroll to the M and S tiles. Expected: **Montana** and **South Dakota** carry a gold 1ST badge at the top left and a green check at the top right. Ohio and Pennsylvania don't.
3. Scroll to **Wyoming** (never seen), tap it, and screenshot within 2 seconds (`t3_toast.png`). Expected: the toast "First time ever: Wyoming!" / "Your collection is now 47 of 64" at the bottom, and Wyoming now has 1ST. Scroll up: the pill reads 3. After about 3 s, the toast is gone.
4. Tap **Alabama**, which other trips have seen. Expected: no toast and no 1ST.
5. Long-press **Montana** → **Remove sighting**. Expected: the badge goes with the check, and the pill reads 2.
6. Close the trip (overflow menu → Close Trip). Expected: the pill is still shown on the closed trip; the chips have no badges.
7. `$SCRATCH/seedSim.sh first light large`, open **First Trip**, and tap **Texas**. Expected: no pill, no badges, no toast.

- [ ] **Step 7: Commit**

```bash
git add -A myRoadTripTracker/myRoadTripTracker
git commit -m "First time ever: a toast and a lasting 1ST badge for plates new to your collection (#78)"
```

---

### Task 4: "Watch for" strip

**Outcome:** on an open trip, you can see at a glance which plates your past trips usually saw and this one hasn't, and mark one with a tap (spec §4).

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/Views/WatchForStrip.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/PlateSightingsGrid.swift`

**Interfaces:**
- Consumes: `PlateHistory.watchFor(on:limit:)`, `.otherTripCount(than:)`, `PlateCount` (Task 2); `history` in `PlateSightingsGrid.body` and `markAsSeen(_:)` (Task 3).

- [ ] **Step 1: Create `Views/WatchForStrip.swift`**

```swift
import SwiftUI

/// Plates this trip hasn't seen that your other trips usually did, so you know what to look
/// out for (#78; spec §4). A tap marks the plate, like its tile in the grid.
struct WatchForStrip: View {
    let plates: [PlateCount]
    /// Other trips with plates: the "of M" in each caption.
    let pastTripCount: Int
    let onMark: (Location) -> Void

    @ScaledMetric(relativeTo: .caption) private var cardWidth: CGFloat = 96
    @State private var marks = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Watch for")
                    .font(.headline)
                Spacer()
                Text("seen on most past trips")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(plates) { plate in
                        Button {
                            marks += 1
                            onMark(plate.location)
                        } label: {
                            card(plate)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(plate.location.name), not seen")
                        .accessibilityValue("Seen on \(plate.trips) of \(pastTripCount) past trips")
                        .accessibilityHint("Double-tap to mark as seen")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .animation(.default, value: plates.map(\.id))
        }
        // The grid tile that plays the reveal may be off screen, so the strip gives its own.
        .sensoryFeedback(.success, trigger: marks)
    }

    private func card(_ plate: PlateCount) -> some View {
        VStack(spacing: 2) {
            Image(plate.location.flagImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 28)
                .clipShape(.rect(cornerRadius: 3))
                .grayscale(1)
                .opacity(0.5)
            Text(plate.location.code)
                .font(.system(.caption, design: .monospaced))
                .bold()
            Text(plate.location.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("\(plate.trips) of \(pastTripCount) trips")
                .font(.caption)
                .bold()
                .foregroundStyle(Theme.greenText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(width: cardWidth)
        .background(.background)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
        }
    }
}
```

(`.background` is right for the cards: they match the plate tiles, which sit on the plain background, not the grouped one.)

- [ ] **Step 2: Show it in `PlateSightingsGrid` above the US section on open trips**

In `body`, after the `firstCodes` line, add:

```swift
        let pastTrips = history.otherTripCount(than: trip)
        // Two other trips before "usually" means anything (spec §4).
        let watchFor = trip.isClosed || pastTrips < 2 ? [] : history.watchFor(on: trip)
```

In the `VStack(spacing: 16)`, after the pill and before the US `sectionView`, add:

```swift
                if !watchFor.isEmpty {
                    WatchForStrip(plates: watchFor, pastTripCount: pastTrips) { location in
                        markAsSeen(location)
                    }
                }
```

`markAsSeen` already ignores a plate that's already seen, so a fast double-tap marks once.

- [ ] **Step 3: Gate — build, then check the strip, a tap, both modes, accessibility size and the `first` scenario**

Run the build. Expected: `** BUILD SUCCEEDED **`, no warnings.

1. `$SCRATCH/seedSim.sh full light large`. Open **Fall Colors 2026** and screenshot `t4_strip.png`. Expected: under the pill, "Watch for" / "seen on most past trips", then grey cards captioned "4 of 5 trips" (California, Texas…) followed by "3 of 5 trips". No card is a plate this trip has, such as Ohio.
2. Swipe the strip left. Expected: up to 8 cards, and the page doesn't scroll sideways.
3. Tap the first card (e.g. **California**) and screenshot `t4_after_tap.png`. Expected: the card leaves the strip and the next one slides in. Scroll to California's tile in the grid: seen, with a check and no 1ST, because other trips saw it first. Then double-tap a card quickly and check its grid tile. Expected: marked once. The context menu's Remove sighting removes it, and it comes back to the strip.
4. Switch the filter to **Not Seen**. Expected: the strip is still there, and the tapped plates are gone from the grid.
5. `$SCRATCH/seedSim.sh full dark accessibility-extra-extra-extra-large`, open Fall Colors, and screenshot. Expected: wider cards, readable captions (scaled down, not cut to "…" mid-word), and card fills visible on dark.
6. Close the trip. Expected: no strip. `$SCRATCH/seedSim.sh first light large` → First Trip. Expected: no strip.

- [ ] **Step 4: Commit**

```bash
git add -A myRoadTripTracker/myRoadTripTracker
git commit -m "Watch for: plates your past trips usually saw, on an open trip (#78)"
```

---

### Task 5: What's-new card, docs, final verification and PR

**Outcome:** existing users find Plate Passport, the docs describe the new pieces, and the branch is merged ready.

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/Services/WhatsNew.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/ContentView.swift` (`presentWhatsNewIfDue`)
- Modify: `CLAUDE.md` (source layout)

- [ ] **Step 1: Add the card**

In `WhatsNew.swift`, add `case passport` to `Announcement.ID`, and append to `all`:

```swift
        Announcement(id: .passport, title: "Plate Passport", systemImage: "globe.americas.fill", lines: [
            .init(text: "See what all your trips add up to: the plates you always see, the ones you never have, and your record trip."),
            .init(text: "Tap Plate Passport on the Road Trips screen.", isKey: true),
            .init(text: "Spot a plate none of your trips has seen and it gets a gold 1ST badge."),
            .init(text: "On a trip, Watch for shows the plates you usually see but haven't yet."),
        ]),
```

Change `next` so the Passport card waits for the Passport row (spec §5):

```swift
    /// The next unseen card, or nil. Nothing until the user has a trip: Siri has nothing to
    /// answer about without one. The Plate Passport card waits until its row shows (#78).
    static func next(seen: Set<String>, hasTrips: Bool, showsPassport: Bool) -> Announcement? {
        guard hasTrips else { return nil }
        return all.first { !seen.contains($0.id.rawValue) && ($0.id != .passport || showsPassport) }
    }
```

In `ContentView.presentWhatsNewIfDue`, pass `showsPassport: PlateHistory(trips: trips).showsPassport`.

- [ ] **Step 2: Update `CLAUDE.md`'s source layout**

In the `Services/` line of the layout block, add `PlateHistory, PlateCount, TripPlateTotal` after `TripBadges`. (The Views line lists examples only; leave it.)

- [ ] **Step 3: Gate — full build, the card, and a final pass**

Run the build. Expected: `** BUILD SUCCEEDED **`, no warnings.

`$SCRATCH/seedSim.sh full light large`. Expected: the Plate Passport card appears over the trip list (the seed only marks `siri` seen). Dismiss it, terminate and relaunch the app (`xcrun simctl terminate $DEV com.tentenbits.myRoadTripTracker; xcrun simctl launch $DEV com.tentenbits.myRoadTripTracker`). Expected: no card. `$SCRATCH/seedSim.sh first light large`. Expected: no card.

Final pass on `full`, in light and dark: trip list → Passport → a trip from Trips by plates → back; Fall Colors with pill, badges and strip. Screenshot each and look at them.

- [ ] **Step 4: Commit, push and open the PR**

```bash
git add -A
git commit -m "Plate Passport what's-new card and docs (#78)"
git push -u origin HEAD
gh pr create --title "Plate Passport: stats across your trips (#78)" --body "$(cat <<'EOF'
## Why
Trips were only ever looked at one at a time. Plate Passport shows what they add up to, and uses that history during a trip.

## What changed
- Plates count once per trip everywhere; the recap no longer counts sync duplicates (#77).
- Plate Passport row on the trip list and a Passport screen: collection, typical/record/never-seen tiles, usual suspects, still hunting, seen once, trips by plates.
- First time ever: toast plus a lasting 1ST badge, and a "new to your collection" pill.
- Watch for: a strip of unseen plates your past trips usually saw.
- What's-new card. No data model change.

## How verified
Simulator (iPhone 17, iOS 26.5) with seeded history (6 trips) and a first-trip scenario, light and dark, large and AX5 text: screenshots of every screen and state in the plan's gates.

Closes #78
Closes #77
EOF
)"
```

Don't merge: Sam reviews the PR (and a device check) first.
