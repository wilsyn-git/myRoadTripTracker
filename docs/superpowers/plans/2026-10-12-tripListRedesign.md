# Trips Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When someone opens TripSpotter, the trip they're on now is front and centre, and their past trips are tidy, scannable history. Every trip action is discoverable, and the screen meets Apple's contrast and color guidance.

**Architecture:** The trip list's `ScrollView` + `LazyVGrid` of cards becomes an inset-grouped `List`. A hero card shows the open trip with the latest activity. Other open trips and closed trips (grouped by year) are compact rows with swipe and long-press actions. Grouping lives in a small value type (`TripListSections`). Close, reopen and delete live in one main-actor helper (`TripLifecycle`), so the list and the trip screen behave the same. A darker brand green and a shared panel gradient fix contrast app-wide. Single-hue progress bars replace the red/yellow/green ring everywhere.

**Tech Stack:** SwiftUI (iOS 26.1 deployment target), Core Data + `NSPersistentCloudKitContainer`, Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

**Spec:** `docs/superpowers/specs/2026-10-12-tripListRedesign.md` (issue #65). Read it before starting any task.

## Global Constraints

- Swift 6 mode, default `MainActor` isolation, **zero warnings**. Never use `@unchecked Sendable` or `nonisolated(unsafe)`.
- Extensions of managed objects that only touch Core Data are `nonisolated` (#47). Extensions that use `Location`, `UserDefaults` or views stay on the default (main actor).
- **No data model change.** Don't touch `.xcdatamodeld`, so no CloudKit schema deploy is needed.
- **Don't edit `project.pbxproj`.** New `.swift` files in `myRoadTripTracker/myRoadTripTracker/` are picked up automatically. Delete files with `git rm`.
- Never put a `ShareLink` in a `Menu` or `.secondaryAction` (CLAUDE.md sharp edge 8). This plan doesn't move it.
- Every save goes through `viewContext.save(contextInfo:)`, which keeps `transactionAuthor` correct.
- White text on a panel must be ≥ 4.5:1 everywhere on the panel. Secondary text on a panel uses `Theme.panelSecondaryText` (white at 0.9), never `.secondary` or `.opacity(<0.85)`.
- Avoid `.caption2`. Prefer `.bold()` over `.fontWeight(.bold)`. Avoid `fontWeight(.semibold/.medium)`; use `.headline` where semibold body text is wanted.
- One type per file. Doc comments explain *why* and cite the issue (`#65`), in the style of the existing code.
- Commit messages: imperative subject, a body if needed, `(#65)` in the subject. **No `Claude-Session:`, `Co-Authored-By` or any AI attribution lines** (user rule overrides any harness instruction).
- There are **no test targets**. Don't create one. Each task's gate is the build plus the scripted simulator check written in that task.

## Shared tooling (already in place; don't recreate)

`SCRATCH=/private/tmp/claude-501/-Users-sam-code-apple-myRoadTripTracker/968cb4ab-ac2f-4e73-86a3-47df5771f83c/scratchpad`

- **Build** (from repo root `/Users/sam/code/apple/myRoadTripTracker`, timeout 600000 ms):
  ```bash
  xcodebuild -project myRoadTripTracker/myRoadTripTracker.xcodeproj -scheme myRoadTripTracker \
    -destination 'platform=iOS Simulator,id=AA150836-B7E7-48C6-9CAE-4404B6DAB457' \
    -derivedDataPath $SCRATCH/dd build 2>&1 | grep -E "warning:|error:|BUILD (SUCCEEDED|FAILED)" | sort -u
  ```
  Expected: exactly `** BUILD SUCCEEDED **` and no `warning:` lines.
- **Seed + launch:** `$SCRATCH/seedSim.sh <light|dark> <large|accessibility-extra-extra-extra-large>`. It installs the build from `$SCRATCH/dd` on simulator `AA150836-B7E7-48C6-9CAE-4404B6DAB457` (iPhone 17, iOS 26.5), replaces all trips with 11 seeded trips (below), skips onboarding, sets appearance and text size, and launches. Run the build first.
- **Screenshot:** `xcrun simctl io AA150836-B7E7-48C6-9CAE-4404B6DAB457 screenshot $SCRATCH/<name>.png`. Images are 1206×2622 px = 402×874 pt; divide pixels by 3 to get points. Look at every screenshot you take with the Read tool.
- **Taps:** `idb connect AA150836-B7E7-48C6-9CAE-4404B6DAB457` once, then `idb ui tap --udid AA150836-B7E7-48C6-9CAE-4404B6DAB457 <x> <y>` (points). Long-press: add `--duration 1.2`. Swipe: `idb ui swipe --udid AA150836-B7E7-48C6-9CAE-4404B6DAB457 <x1> <y1> <x2> <y2> --duration 0.4`. Type: `idb ui text --udid AA150836-B7E7-48C6-9CAE-4404B6DAB457 "Tahoe"`. `idb ui describe-all --udid …` lists element labels and frames, but toolbar items don't appear there, so find them from a screenshot.
- **Contrast:** `python3 -I $SCRATCH/contrast.py <png> <x> <y>` (pixel coordinates). Prints the white and 90%-white contrast against that pixel, plus PASS/FAIL at 4.5:1. Sample the **top** of a panel, above its text, where the gradient is lightest. Baseline on `main`: `(98,196,132)`, 2.15:1, FAIL.

**Seeded trips** (relative times are from seeding):

| Trip | State | Activity | Notes |
|---|---|---|---|
| Colorado to Utah | open | 8 plates, last 2 h ago | 3 participants (shared) → **hero** |
| Great American Loop | open | 44 plates, last 26 h ago | |
| Weekend in Moab | open | no plates, created 50 h ago | |
| Summer Coast Run | closed | Aug 30 – Sep 2, 2026 | unseen recap (sparkle) |
| Spring Break Florida | closed | Mar 14 – 22, 2026 | 4 participants |
| Lake Weekend | closed | one day, Feb 7, 2026 | |
| New Year Drive | closed | Dec 30, 2025 – Jan 2, 2026 | crosses years → 2026 section |
| Partly Synced | closed | no created date, no plates | partial CloudKit record |
| Thanksgiving to Tahoe | closed | Nov 26 – 30, 2025 | |
| Pacific Northwest | closed | Jul 3 – 12, 2025 | |
| Old Empty Trip | closed | no plates, created Jun 1, 2025 | |

## Review Focus

1. **Search field vanishing mid-typing.** If the "more than 5 past trips" threshold counted *filtered* results, typing a narrow query would remove the field under your finger. Expected: the threshold counts all closed trips. *Task 4, Step 7.*
2. **Deleting from the trip screen while it's still showing.** The detail view observes the trip, and reading a deleted trip's non-optional `name` crashes. Expected: the screen pops first, then the trip is deleted, with no crash. *Task 3, Step 6.*
3. **Swipe Delete removing the row before the alert is answered.** `role: .destructive` on a swipe action makes `List` animate the row away at once. Expected: Cancel leaves the row in place. *Task 5, Step 4.*
4. **Partially synced trip (nil `createdDate`, no plates).** Expected: no "Year 1" section and no blank second line. It sits in the current year's section with just its name. *Task 4, Step 6.*
5. **Closing the last open trip.** Expected: the Current section shows "No trip in progress" with a working Start a Trip button. Reopening a past trip brings it back to Current. *Task 5, Step 5.*

---

### Task 1: Visual foundation — darker green, panel gradient, progress bars

Outcome served: white text on every green panel (trip cards, recap card, Siri cards) is readable at ≥ 4.5:1, and progress is no longer colored as if a new trip were failing.

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/Theme.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/Views/RegionProgressBars.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/TripCardView.swift` (temporary; deleted in Task 4)
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/RecapCardContent.swift:51` and its `.opacity(0.85)` text
- Modify: `myRoadTripTracker/myRoadTripTracker/Intents/IntentSnippets.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/WhatsNewSheet.swift:18`
- Delete: `myRoadTripTracker/myRoadTripTracker/Views/DualProgressRingView.swift`

**Interfaces:**
- Produces: `Theme.green` (new value), `Theme.panelSecondaryText: Color`, `Theme.panel(closed: Bool = false) -> LinearGradient`, `RegionProgressBars(usSeen: Int, caSeen: Int, axis: Axis = .horizontal)`, `RegionProgressBars.usTotal: Int`, `RegionProgressBars.caTotal: Int`.

- [ ] **Step 1: Replace `Theme.swift`**

```swift
import SwiftUI

/// The app's brand colors, kept in one place so screens stay consistent.
enum Theme {
    /// Open trip panels, the recap card, Siri cards and what's-new accents. Dark enough
    /// that white text on it is 5.7:1; the HIG minimum is 4.5:1 (#65).
    static let green = Color(red: 0.11, green: 0.46, blue: 0.24)
    /// A closed trip's Siri card.
    static let closedGray = Color(white: 0.38)
    /// Secondary text on a `panel`. Plain `.secondary` is too faint there: white at 0.6
    /// on `green` is 3.1:1, at 0.9 it's 5.1:1 (#65).
    static let panelSecondaryText = Color.white.opacity(0.9)
    /// The two ends of the plate progress bars; also the reveal confetti.
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let gold = Color(red: 0.98, green: 0.75, blue: 0.15)

    /// The background behind white text: the base color at the top, darkening toward the
    /// bottom. SwiftUI's `.gradient` lightens the top instead, which took white text on
    /// the old green down to about 2:1 (#65).
    static func panel(closed: Bool = false) -> LinearGradient {
        let base = closed ? closedGray : green
        return LinearGradient(
            colors: [base, base.mix(with: .black, by: 0.2)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
```

- [ ] **Step 2: Create `RegionProgressBars.swift`**

```swift
import SwiftUI

/// US and Canada progress as two labelled bars ("US 7/51"). One hue, drawn in the current
/// foreground style, so it reads on a green panel and on a plain background. Replaces the
/// red/yellow/green ring, where every new trip started out red (#65).
struct RegionProgressBars: View {
    let usSeen: Int
    let caSeen: Int
    /// Side by side on the trip list's hero card; stacked in narrow Siri cards and at
    /// accessibility text sizes.
    var axis: Axis = .horizontal

    static let usTotal = Location.usStates.count
    static let caTotal = Location.canadaLocations.count

    var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        layout {
            RegionBar(region: "US", spokenRegion: "US plates", seen: usSeen, total: Self.usTotal)
            RegionBar(region: "CA", spokenRegion: "Canadian plates", seen: caSeen, total: Self.caTotal)
        }
    }
}

/// One labelled bar. The track and fill use hierarchical styles, so they follow whatever
/// foreground style the bars sit in.
private struct RegionBar: View {
    let region: String
    let spokenRegion: String
    let seen: Int
    let total: Int
    @ScaledMetric(relativeTo: .subheadline) private var barHeight: CGFloat = 6

    private var fraction: Double {
        total > 0 ? min(Double(seen) / Double(total), 1) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(region).font(.subheadline).bold()
                Text("\(seen)/\(total)").font(.subheadline).monospacedDigit()
            }
            Capsule()
                .fill(.quaternary)
                .frame(height: barHeight)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        // A started trip always shows a sliver, so one plate doesn't look like none.
                        let width = seen > 0 ? max(proxy.size.width * fraction, barHeight) : 0
                        Capsule().fill(.primary).frame(width: width)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenRegion)
        .accessibilityValue("\(seen) of \(total)")
    }
}
```

- [ ] **Step 3: Point `TripCardView` at the new pieces** (it's deleted in Task 4; this just keeps it compiling and correct until then)

In `TripCardView.swift`:
- Delete the `cardColor` property and the `regionCount(_:seen:total:)` function.
- Replace the whole bottom `HStack(spacing: 10) { DualProgressRingView(…) … Spacer(minLength: 0) }` block with:
  ```swift
  // Stacked: two bars side by side don't fit a 160pt card.
  RegionProgressBars(usSeen: data.usSeenCount, caSeen: data.caSeenCount, axis: .vertical)
  ```
- Replace `.background(cardColor.gradient, in: RoundedRectangle(cornerRadius: 16))` with:
  ```swift
  .background(Theme.panel(closed: trip.isClosed), in: RoundedRectangle(cornerRadius: 16))
  ```
- Keep `usTotalCount` / `caTotalCount`; the accessibility label uses them.

- [ ] **Step 4: Recap card and What's New**

- `RecapCardContent.swift`: `.background(Theme.green.gradient, in: RoundedRectangle(cornerRadius: 20))` → `.background(Theme.panel(), in: RoundedRectangle(cornerRadius: 20))`. In the same file, change every `.opacity(0.85)` applied to `Text` to `.foregroundStyle(Theme.panelSecondaryText)`.
- `WhatsNewSheet.swift:18`: `.background(Theme.green.gradient, in: .circle)` → `.background(Theme.panel(), in: .circle)`.

- [ ] **Step 5: Siri snippets (`IntentSnippets.swift`)**

- Delete `private enum SnippetStyle`. In `SnippetShell`, change `.background(SnippetStyle.panel(closed: isClosed).gradient, in: .rect(cornerRadius: 16))` to `.background(Theme.panel(closed: isClosed), in: .rect(cornerRadius: 16))`.
- Change every `.opacity(0.85)` on `Text` in this file to `.foregroundStyle(Theme.panelSecondaryText)`.
- Update the file's header comment: the cards use "the trip list's green panel (`Theme.panel`) with white text".
- Replace `private struct TripRing` with:
  ```swift
  /// A trip's progress, stacked to fit beside a card's text.
  private struct TripProgress: View {
      let trip: TripSnapshot

      var body: some View {
          RegionProgressBars(usSeen: trip.usSeen, caSeen: trip.caSeen, axis: .vertical)
      }
  }
  ```
- In `CountCard.body`, the bars now carry the counts, so drop the duplicated text lines. Replace the `HStack(spacing: 16) { TripRing(…) VStack { Text("… of … US") Text("… of … Canada") HStack { flags } } }` with:
  ```swift
  VStack(alignment: .leading, spacing: 12) {
      RegionProgressBars(usSeen: trip.usSeen, caSeen: trip.caSeen)
      HStack(spacing: -4) {
          ForEach(recentFlags, id: \.code) { sighting in
              if let location = Location.byCode[sighting.code] {
                  Flag(assetName: location.flagImageName)
              }
          }
      }
  }
  ```
- In `MarkCard`, replace `TripRing(trip: trip)` with `TripProgress(trip: trip).frame(width: 110)`.
- `grep -n "TripRing\|SnippetStyle\|DualProgressRing" myRoadTripTracker/myRoadTripTracker -r` must print nothing after this step.

- [ ] **Step 6: Delete the ring**

```bash
git rm myRoadTripTracker/myRoadTripTracker/Views/DualProgressRingView.swift
```

- [ ] **Step 7: Gate — build, then check contrast on the live grid**

Run the **Build** command. Expected: `** BUILD SUCCEEDED **` and no warnings. Then:
```bash
$SCRATCH/seedSim.sh light large
xcrun simctl io AA150836-B7E7-48C6-9CAE-4404B6DAB457 screenshot $SCRATCH/t1_grid.png
python3 -I $SCRATCH/contrast.py $SCRATCH/t1_grid.png 300 565
```
Expected: the contrast line ends in `PASS`, with white ≥ 5.5:1 against a pixel near `(28,117,61)`. Look at the screenshot: the first card is green, with bars instead of a ring and no red or yellow anywhere. If (300, 565) isn't at the top of the first card above its title, pick a point that is and say which.

- [ ] **Step 8: Commit**

```bash
git add -A myRoadTripTracker/myRoadTripTracker
git commit -m "Darker panel green and single-hue progress bars (#65)" -m "White text on green panels was 2.1:1 at the top of SwiftUI's .gradient. Theme.panel darkens downward instead and the base green is 5.7:1. RegionProgressBars replaces the red/yellow/green ring, including in the Siri cards."
```

---

### Task 2: One "last activity" rule and the list's grouping model

Outcome served: the trip list and Siri agree on which trip is current. The list's grouping (hero, other open trips, past trips by year) is computed in one readable place.

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/Models/Trip+Activity.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/Services/TripBadges.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/Services/TripListSections.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Intents/IntentTrips.swift:65-82`

**Interfaces:**
- Produces (nonisolated): `Trip.lastActivity: Date`, `Trip.activitySpan: ClosedRange<Date>?`, `static Trip.byRecentActivity(_: some Sequence<Trip>) -> [(trip: Trip, lastActivity: Date)]`.
- Produces (main actor): `Trip.regionCounts: (us: Int, ca: Int)`, `Trip.noteCount: Int`, `Trip.participantCount: Int`, `Trip.unseenNoteCount: Int`, `Trip.hasUnseenRecap: Bool`.
- Produces: `TripListSections(trips: some Sequence<Trip>, matching: String = "", calendar: Calendar = .current)` with `hero: Trip?`, `otherOpen: [Trip]`, `pastYears: [TripListSections.PastYear]` (`year: Int`, `trips: [Trip]`, `id: Int`), `isEmpty: Bool`.

- [ ] **Step 1: Create `Models/Trip+Activity.swift`**

```swift
import CoreData

/// When a trip was active. Shared by the trip list and Siri so they agree on which trip is
/// current (#65). Nonisolated like the managed object itself (#47).
nonisolated extension Trip {
    /// The latest sighting, else when the trip was created.
    var lastActivity: Date {
        sightingDates.max() ?? createdDate ?? .distantPast
    }

    /// The first and last sighting; nil before the first plate.
    var activitySpan: ClosedRange<Date>? {
        let dates = sightingDates
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return first...last
    }

    private var sightingDates: [Date] {
        ((plateSightings as? Set<PlateSighting>) ?? []).compactMap(\.seenDate)
    }

    /// Trips paired with their last activity, most recent first, each computed once. Equal
    /// activity goes to the trip created later, then to the higher trip ID, so the order
    /// never depends on fetch order (#14).
    static func byRecentActivity(_ trips: some Sequence<Trip>) -> [(trip: Trip, lastActivity: Date)] {
        trips.map { (trip: $0, lastActivity: $0.lastActivity) }.sorted { a, b in
            if a.lastActivity != b.lastActivity { return a.lastActivity > b.lastActivity }
            let aCreated = a.trip.createdDate ?? .distantPast
            let bCreated = b.trip.createdDate ?? .distantPast
            if aCreated != bCreated { return aCreated > bCreated }
            return (a.trip.tripID?.uuidString ?? "") > (b.trip.tripID?.uuidString ?? "")
        }
    }
}
```

- [ ] **Step 2: Create `Services/TripBadges.swift`** (logic moved from `TripCardView`; the region count now counts *distinct* plates, as `TripSnapshot` does)

```swift
import Foundation

/// What a trip's entry in the trip list shows besides its name: plates by country, notes
/// you haven't read, a recap you haven't opened, and who's on it (#65).
extension Trip {
    private static let usCodes = Set(Location.usStates.map(\.code))
    private static let caCodes = Set(Location.canadaLocations.map(\.code))

    /// Distinct US and Canadian plates seen. Distinct, because sync can leave two sightings
    /// of one plate; `TripSnapshot` counts the same way, so Siri and the list agree.
    var regionCounts: (us: Int, ca: Int) {
        let codes = Set(((plateSightings as? Set<PlateSighting>) ?? []).map(\.locationCode))
        return (codes.intersection(Self.usCodes).count, codes.intersection(Self.caCodes).count)
    }

    var noteCount: Int { observationEntries?.count ?? 0 }

    var participantCount: Int { participants?.count ?? 0 }

    /// Notes added since you last opened the Notes tab, which stamps the key.
    var unseenNoteCount: Int {
        let notes = (observationEntries as? Set<ObservationEntry>) ?? []
        guard let tripID = tripID?.uuidString else { return notes.count }
        guard let lastViewed = UserDefaults.standard.object(forKey: "lastViewedObservations_\(tripID)") as? Date else {
            return notes.count
        }
        return notes.filter { ($0.createdDate ?? .distantPast) > lastViewed }.count
    }

    /// A recap generated since you last opened it; `TripRecapView` stamps the key.
    var hasUnseenRecap: Bool {
        guard let generated = recapGeneratedDate else { return false }
        guard let tripID = tripID?.uuidString else { return true }
        guard let lastViewed = UserDefaults.standard.object(forKey: "lastViewedRecap_\(tripID)") as? Date else {
            return true
        }
        return generated > lastViewed
    }
}
```

- [ ] **Step 3: Create `Services/TripListSections.swift`**

```swift
import Foundation

/// The trip list's grouping (#65). The hero is the open trip with the latest activity, the
/// same trip Siri treats as current. The other open trips follow it, newest activity first.
/// Closed trips are grouped by the year of their last activity, newest year first.
struct TripListSections {
    struct PastYear: Identifiable {
        let year: Int
        let trips: [Trip]
        var id: Int { year }
    }

    let hero: Trip?
    let otherOpen: [Trip]
    let pastYears: [PastYear]

    var isEmpty: Bool { hero == nil && pastYears.isEmpty }

    /// - Parameter query: Search text. Trips whose name doesn't contain it are left out.
    init(trips: some Sequence<Trip>, matching query: String = "", calendar: Calendar = .current) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = trips.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
        let ordered = Trip.byRecentActivity(matching)

        let open = ordered.filter { !$0.trip.isClosed }.map(\.trip)
        hero = open.first
        otherOpen = Array(open.dropFirst())

        var years: [Int: [Trip]] = [:]
        let thisYear = calendar.component(.year, from: .now)
        for entry in ordered where entry.trip.isClosed {
            // A partially synced trip can arrive with no dates at all; it goes in this
            // year's section rather than under "Year 1".
            let year = entry.lastActivity == .distantPast
                ? thisYear
                : calendar.component(.year, from: entry.lastActivity)
            years[year, default: []].append(entry.trip)
        }
        pastYears = years
            .sorted { $0.key > $1.key }
            .map { PastYear(year: $0.key, trips: $0.value) }
    }
}
```

- [ ] **Step 4: Make Siri use the shared rule (`IntentTrips.swift`)**

Replace `currentTrip(in:)` and its doc comment with:
```swift
    /// Spec, "Decisions": the open trip with the most recent activity (latest sighting,
    /// else creation date). Ties resolve the same way every time (#14), and the trip list's
    /// hero uses the same rule (#65).
    static func currentTrip(in trips: [Trip]) -> Trip? {
        Trip.byRecentActivity(trips.filter { !$0.isClosed }).first?.trip
    }
```
In `suggestedTrips(now:)`, change `lastActivity($0) >= cutoff` to `$0.lastActivity >= cutoff`. Delete `private static func lastActivity(_ trip: Trip) -> Date`.

- [ ] **Step 5: Fix the stale comment on `allTrips()`**

Its doc comment says the order is "the trip list's order", which stops being true. Change it to:
```swift
    /// Every trip, open first, newest first.
```

- [ ] **Step 6: Gate — build**

Run the **Build** command. Expected: `** BUILD SUCCEEDED **`, no warnings. Nothing visible changes in this task, so no simulator check. Task 4's screenshots exercise `TripListSections` on the seeded data.

- [ ] **Step 7: Commit**

```bash
git add -A myRoadTripTracker/myRoadTripTracker
git commit -m "Share one last-activity rule between the trip list and Siri (#65)" -m "Adds TripListSections for the list's grouping and moves the card's badge logic onto Trip. Ties in Siri's current trip now break by created date, then trip ID (#14)."
```

---

### Task 3: Shared close/reopen/delete, and Delete in the trip screen

Outcome served: closing or deleting a trip works the same from any entry point. Closing always produces the recap, and Delete is reachable from the trip screen, not only the long-press menu.

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/Services/TripLifecycle.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/TripDetailView.swift` (props, toolbar, alert; remove `isGeneratingRecap` and `generateRecap()`)
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/ContentView.swift` (delete alert action, `navigationDestination`, new `deleteAfterPop`)

**Interfaces:**
- Consumes: `RecapStats(trip:)`, `.isEmpty`, `RecapNarrativeGenerator.generate(from:tripName:) async -> String?` (existing).
- Produces: `TripLifecycle.setClosed(_ closed: Bool, for trip: Trip, in context: NSManagedObjectContext)`, `TripLifecycle.delete(_ trip: Trip, in context: NSManagedObjectContext)`. `TripDetailView` gains `let onDelete: (NSManagedObjectID) -> Void`.

- [ ] **Step 1: Create `Services/TripLifecycle.swift`**

```swift
import CoreData

/// Closing, reopening and deleting a trip, shared by the trip list and the trip screen so
/// every entry point behaves the same (#65). Closing always produces the recap. Callers
/// offer these actions to the trip's owner only.
enum TripLifecycle {
    /// Trips whose recap is being written, so closing from two places can't start a second.
    private static var generatingRecap: Set<NSManagedObjectID> = []

    static func setClosed(_ closed: Bool, for trip: Trip, in context: NSManagedObjectContext) {
        guard trip.isClosed != closed else { return }
        trip.isClosed = closed
        context.save(contextInfo: closed ? "closeTrip" : "reopenTrip")
        if closed {
            Task { await generateRecap(for: trip, in: context) }
        }
    }

    static func delete(_ trip: Trip, in context: NSManagedObjectContext) {
        context.delete(trip)
        context.save(contextInfo: "deleteTrip")
    }

    /// Moved from `TripDetailView`. `recapGeneratedDate` is stamped even when the model is
    /// unavailable (narrative == nil), so the "recap ready" badge appears for everyone;
    /// `TripRecapView` falls back to the template narrative.
    private static func generateRecap(for trip: Trip, in context: NSManagedObjectContext) async {
        let id = trip.objectID
        guard !generatingRecap.contains(id) else { return }
        let stats = RecapStats(trip: trip)
        guard !stats.isEmpty else { return }
        generatingRecap.insert(id)
        defer { generatingRecap.remove(id) }
        let narrative = await RecapNarrativeGenerator.generate(from: stats, tripName: trip.name)
        // The trip may have been deleted while the model ran.
        guard !trip.isDeleted, trip.managedObjectContext != nil else { return }
        if let narrative { trip.recapNarrative = narrative }
        trip.recapGeneratedDate = Date()
        context.save(contextInfo: "generateRecap")
    }
}
```
This enum takes the default `MainActor` isolation; don't annotate it. If the compiler objects to the `Task` capturing `trip`, keep the capture on the main actor (`Task { @MainActor in … }`). Don't pass the object to another actor.

- [ ] **Step 2: Update `TripDetailView.swift`**

- After `let onLeave: (String) -> Void`, add:
  ```swift
      /// Asks the trip list to delete this trip after popping back to it; deleting it while
      /// this screen still shows it would crash on the deleted trip's name (#65).
      let onDelete: (NSManagedObjectID) -> Void
      @State private var showingDeleteAlert = false
  ```
- Delete `@State private var isGeneratingRecap = false`, the whole `generateRecap()` function and the `@MainActor` line above it.
- In the Close/Reopen toolbar button, replace the action body (`let wasClosed = … Task { await generateRecap() } }`) with:
  ```swift
  TripLifecycle.setClosed(!trip.isClosed, for: trip, in: viewContext)
  ```
- Directly after that `ToolbarItem`, add Delete as the last overflow item. It's a plain `Button`, not a `ShareLink`, so sharp edge 8 doesn't apply:
  ```swift
              if persistenceController.isOwner(of: trip) {
                  ToolbarItem(placement: .secondaryAction) {
                      Button(role: .destructive) {
                          showingDeleteAlert = true
                      } label: {
                          Label("Delete Trip", systemImage: "trash")
                      }
                  }
              }
  ```
- After the `.sheet(isPresented: $showingRecap) { … }` modifier, add:
  ```swift
          .alert("Delete Trip", isPresented: $showingDeleteAlert) {
              Button("Delete", role: .destructive) { onDelete(trip.objectID) }
              Button("Cancel", role: .cancel) {}
          } message: {
              Text("Are you sure you want to delete this trip? This cannot be undone.")
          }
  ```

- [ ] **Step 3: Update `ContentView.swift`**

- In the existing delete alert, replace `viewContext.delete(trip)` + `viewContext.save(contextInfo: "deleteTrip")` with `TripLifecycle.delete(trip, in: viewContext)`.
- In `.navigationDestination(for: NSManagedObjectID.self)`, add `onDelete: deleteAfterPop` after the `onLeave:` argument.
- Add below `confirmLeft(_:)`:
  ```swift
      /// Deletes a trip its own screen asked to delete, once that screen is gone (#65).
      private func deleteAfterPop(_ objectID: NSManagedObjectID) {
          navigationPath = NavigationPath()
          Task {
              // Lets the pop animation finish before the trip disappears under it.
              try? await Task.sleep(for: .milliseconds(600))
              guard let trip = try? viewContext.existingObject(with: objectID) as? Trip else { return }
              TripLifecycle.delete(trip, in: viewContext)
          }
      }
  ```

- [ ] **Step 4: Build**

Run the **Build** command. Expected: `** BUILD SUCCEEDED **`, no warnings.

- [ ] **Step 5: Simulator check — close from the trip screen produces the recap badge**

```bash
$SCRATCH/seedSim.sh light large
idb connect AA150836-B7E7-48C6-9CAE-4404B6DAB457
```
The list is still the card grid. Screenshot it, tap the "Colorado to Utah" card, then screenshot to find the overflow (•••) button at the top right. Tap it, screenshot, and tap **Close Trip**. Go back with the back button. Screenshot the list. Expected: Colorado to Utah is now gray, with a lock and the sparkle (recap generated through `TripLifecycle`).

- [ ] **Step 6: Simulator check — delete from the trip screen (Review Focus 2)**

Tap "Weekend in Moab", open the overflow menu, and screenshot. Expected: **Delete Trip** is the last item, in red. Tap it. Expected: an alert titled "Delete Trip". Tap **Delete**. Wait 2 s and screenshot. Expected: back on the list, Weekend in Moab is gone, and the app is still running (`xcrun simctl spawn AA150836-B7E7-48C6-9CAE-4404B6DAB457 launchctl list | grep -c myRoadTripTracker` prints `1`).

- [ ] **Step 7: Commit**

```bash
git add -A myRoadTripTracker/myRoadTripTracker
git commit -m "Share trip close/delete logic; add Delete Trip to the trip screen (#65)" -m "TripLifecycle owns close, reopen and delete, so closing from any entry point writes the recap once. Delete from the trip screen pops back first, then deletes."
```

---

### Task 4: The new trip list — hero card, rows, year sections, search

Outcome served: on opening the app, the current trip is a hero card at the top, other open trips sit right below it, and past trips are a compact, searchable list by year.

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/Views/TripActivityLine.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/Views/TripBadgeIcons.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/Views/TripListLabel.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/Views/TripHeroCard.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/Views/TripRow.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/ContentView.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Intents/IntentSnippets.swift` (comments that name `TripCardView`)
- Delete: `myRoadTripTracker/myRoadTripTracker/Views/TripCardView.swift`

**Interfaces:**
- Consumes: Task 1 `Theme.panel()`, `Theme.panelSecondaryText`, `RegionProgressBars`. Task 2 `TripListSections`, `Trip.activitySpan`, `Trip.regionCounts`, `Trip.unseenNoteCount`, `Trip.hasUnseenRecap`, `Trip.participantCount`. Task 3 `TripLifecycle.delete`, `deleteAfterPop`.
- Produces: `TripHeroCard(trip: Trip, isShared: Bool)`, `TripRow(trip: Trip, isShared: Bool)`, `TripActivityLine(trip: Trip, style: TripActivityLine.Style = .row)`, `static TripActivityLine.text(for: Trip, style: Style) -> String`, `TripBadgeIcons(trip: Trip, isShared: Bool, onPanel: Bool = false)`, `TripListLabel.spoken(_: Trip, isShared: Bool, style: TripActivityLine.Style) -> String`. In `ContentView`: `tripRow(_:)`, `tripMenu(_:)`, `isShared(_:)`, `confirmDelete(_:)`, `confirmLeave(_:)` (Task 5 extends `tripRow` and `tripMenu`).

- [ ] **Step 1: Create `TripActivityLine.swift`**

```swift
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
            return trip.createdDate?.formatted(.dateTime.month(.abbreviated).day().year()) ?? ""
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
```

- [ ] **Step 2: Create `TripBadgeIcons.swift` and `TripListLabel.swift`**

```swift
import SwiftUI

/// The small icons beside a trip's name: shared, unread notes, a new recap (#65). Hidden
/// from VoiceOver; `TripListLabel` reads the same facts as part of the trip's label.
struct TripBadgeIcons: View {
    @ObservedObject var trip: Trip
    let isShared: Bool
    /// The sparkle is gold on the green hero card and orange on a plain row, where gold
    /// would barely show against white.
    var onPanel = false

    var body: some View {
        HStack(spacing: 6) {
            if isShared {
                Image(systemName: "person.2.fill")
            }
            if trip.unseenNoteCount > 0 {
                Image(systemName: "text.bubble.fill")
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(.orange).frame(width: 7, height: 7).offset(x: 3, y: -3)
                    }
            }
            if trip.hasUnseenRecap {
                Image(systemName: "sparkles")
                    .foregroundStyle(onPanel ? Theme.gold : .orange)
            }
        }
        .font(.subheadline)
        .imageScale(.small)
        .accessibilityHidden(true)
    }
}
```

```swift
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
```

- [ ] **Step 3: Create `TripHeroCard.swift`**

```swift
import SwiftUI

/// The trip list's lead card: the open trip with the latest activity (#65).
struct TripHeroCard: View {
    @ObservedObject var trip: Trip
    let isShared: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The five newest plates, newest first, one per region.
    private var recentFlags: [PlateSighting] {
        var seen = Set<String>()
        return Array(trip.plateSightingsArray.reversed().filter { seen.insert($0.locationCode).inserted }.prefix(5))
    }

    var body: some View {
        let counts = trip.regionCounts
        let flags = recentFlags
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(trip.name)
                        .font(.title2)
                        .bold()
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                    Spacer(minLength: 0)
                    TripBadgeIcons(trip: trip, isShared: isShared, onPanel: true)
                }
                TripActivityLine(trip: trip, style: .hero)
                    .font(.subheadline)
                    .foregroundStyle(Theme.panelSecondaryText)
            }
            if !flags.isEmpty {
                HStack(spacing: -4) {
                    ForEach(flags, id: \.objectID) { sighting in
                        Image(sighting.flagImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 18)
                            .clipShape(.rect(cornerRadius: 2))
                            .overlay {
                                RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.6), lineWidth: 1)
                            }
                    }
                }
                .accessibilityHidden(true)
            }
            RegionProgressBars(
                usSeen: counts.us,
                caSeen: counts.ca,
                axis: dynamicTypeSize.isAccessibilitySize ? .vertical : .horizontal
            )
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel(), in: .rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TripListLabel.spoken(trip, isShared: isShared, style: .hero))
    }
}
```

- [ ] **Step 4: Create `TripRow.swift`**

```swift
import SwiftUI

/// A trip in the trip list other than the hero: a later open trip or a past trip (#65).
struct TripRow: View {
    @ObservedObject var trip: Trip
    let isShared: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let counts = trip.regionCounts
        // At accessibility sizes the score moves under the name instead of squeezing it.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(trip.name)
                        .font(.headline)
                        .lineLimit(2)
                    TripBadgeIcons(trip: trip, isShared: isShared)
                        .foregroundStyle(.secondary)
                }
                TripActivityLine(trip: trip)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("US \(counts.us) · CA \(counts.ca)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TripListLabel.spoken(trip, isShared: isShared, style: .row))
    }
}
```

- [ ] **Step 5: Rebuild `ContentView.swift`'s list**

Keep the `body` and its alerts exactly as they are; only the `NavigationStack` content `tripList` and the stored state change. Make these changes:

a. Replace the `@FetchRequest` sort (grouping and order now come from `TripListSections`):
```swift
    /// Every trip. `TripListSections` groups and orders them by activity (#65); this sort
    /// only keeps the fetch stable.
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Trip.createdDate, ascending: false)],
        animation: .default
    )
    private var trips: FetchedResults<Trip>
```
b. Delete `@Environment(\.dynamicTypeSize)` and the `columns` property. Add:
```swift
    @State private var searchText = ""

    /// Search appears once there's enough history to need it. Counted over all trips, not
    /// the search results, so the field can't vanish while you type (#65).
    private var showsSearch: Bool { trips.lazy.filter(\.isClosed).count > 5 }
```
c. Replace the opening of `tripList`, from `ScrollView {` through the grid's closing `.padding()` + `}`, with:
```swift
    private var tripList: some View {
        let sections = TripListSections(trips: trips, matching: searchText)
        return List {
            if let hero = sections.hero {
                Section {
                    // A plain button rather than a NavigationLink: in a List, a link adds a
                    // disclosure chevron, which doesn't belong on a card.
                    Button {
                        navigationPath.append(hero.objectID)
                    } label: {
                        TripHeroCard(trip: hero, isShared: isShared(hero))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .contextMenu { tripMenu(hero) }
                } header: {
                    Text("Current").bold()
                }
            } else if searchText.isEmpty, !trips.isEmpty {
                Section {
                    noTripInProgressRow
                } header: {
                    Text("Current").bold()
                }
            }
            if !sections.otherOpen.isEmpty {
                Section {
                    ForEach(sections.otherOpen) { trip in tripRow(trip) }
                }
            }
            ForEach(Array(sections.pastYears.enumerated()), id: \.element.id) { index, pastYear in
                Section {
                    ForEach(pastYear.trips) { trip in tripRow(trip) }
                } header: {
                    pastHeader(year: pastYear.year, isFirst: index == 0)
                }
            }
        }
        .listStyle(.insetGrouped)
        .tripSearch(text: $searchText, enabled: showsSearch)
        .onChange(of: showsSearch) { _, enabled in
            if !enabled { searchText = "" }
        }
```
The existing modifiers (`.navigationTitle("Road Trips")` and everything after it) stay attached, unchanged, except the first `.overlay`, which becomes:
```swift
        .overlay {
            if trips.isEmpty {
                ContentUnavailableView {
                    Label("No Trips", systemImage: "car.fill")
                } description: {
                    Text("Start tracking your road trip games by creating your first trip.")
                } actions: {
                    Button("Create Trip", action: addTrip)
                }
            } else if !searchText.isEmpty, sections.isEmpty {
                ContentUnavailableView.search
            }
        }
```
d. Add these helpers below `tripList` (Task 5 adds swipe actions to `tripRow` and the Close item to `tripMenu`):
```swift
    private func tripRow(_ trip: Trip) -> some View {
        NavigationLink(value: trip.objectID) {
            TripRow(trip: trip, isShared: isShared(trip))
        }
        .contextMenu { tripMenu(trip) }
    }

    @ViewBuilder
    private func tripMenu(_ trip: Trip) -> some View {
        if persistenceController.isOwner(of: trip) {
            Button(role: .destructive) { confirmDelete(trip) } label: {
                Label("Delete Trip", systemImage: "trash")
            }
        } else {
            Button(role: .destructive) { confirmLeave(trip) } label: {
                Label("Leave Trip", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    private func confirmDelete(_ trip: Trip) {
        tripToDelete = trip
        showingDeleteAlert = true
    }

    private func confirmLeave(_ trip: Trip) {
        tripToLeave = trip
        showingLeaveAlert = true
    }

    /// Shared when someone else is on it, or when it's someone else's trip you joined.
    private func isShared(_ trip: Trip) -> Bool {
        trip.participantCount > 1 || !persistenceController.isOwner(of: trip)
    }

    private var noTripInProgressRow: some View {
        HStack {
            Text("No trip in progress")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Start a Trip", action: addTrip)
                .bold()
        }
    }

    /// The first past year carries the "Past Trips" title above its year.
    @ViewBuilder
    private func pastHeader(year: Int, isFirst: Bool) -> some View {
        let yearText = Text(year, format: .number.grouping(.never))
        if isFirst {
            VStack(alignment: .leading, spacing: 6) {
                Text("Past Trips").bold()
                yearText
            }
        } else {
            yearText
        }
    }
```
e. At file scope, after the `ContentView` struct:
```swift
private extension View {
    /// Search only once there's enough history to need it (#65).
    @ViewBuilder
    func tripSearch(text: Binding<String>, enabled: Bool) -> some View {
        if enabled {
            searchable(text: text, prompt: "Search trips")
        } else {
            self
        }
    }
}
```
f. `git rm myRoadTripTracker/myRoadTripTracker/Views/TripCardView.swift`. In `IntentSnippets.swift`, change comments that mention `TripCardView` to `TripHeroCard`. `grep -rn "TripCardView" myRoadTripTracker/myRoadTripTracker` must print nothing.

- [ ] **Step 6: Gate — build, then check the seeded list (Review Focus 4)**

Run the **Build** command (zero warnings). Then:
```bash
$SCRATCH/seedSim.sh light large
xcrun simctl io AA150836-B7E7-48C6-9CAE-4404B6DAB457 screenshot $SCRATCH/t4_light_top.png
```
Expected, top to bottom:
- **Current**: the hero is **Colorado to Utah**, with the shared icon, "Since Oct 11 · last plate 2 hours ago" (dates relative to seeding), flags and US 7/51 · CA 1/13 bars.
- An untitled section with rows **Great American Loop**, then **Weekend in Moab** ("Started …").
- **Past Trips / 2026** begins.

Swipe up (`idb ui swipe --udid … 200 700 200 200 --duration 0.4`) and screenshot `t4_light_past.png`. Expected:
- 2026: Summer Coast Run ("Aug 30 – Sep 2", orange sparkle), Spring Break Florida ("Mar 14 – 22", shared icon), Lake Weekend ("Feb 7"), New Year Drive ("Dec 30, 2025 – Jan 2, 2026"), and **Partly Synced** with no second line.
- 2025: Thanksgiving to Tahoe, Pacific Northwest, Old Empty Trip ("Jun 1, 2025").
- No "1" year header anywhere.

Contrast: `python3 -I $SCRATCH/contrast.py $SCRATCH/t4_light_top.png <x> <y>`, with x,y on the hero card's top strip above its title. Expected: PASS.

- [ ] **Step 7: Search (Review Focus 1), dark mode and AX3**

Find the search field in a screenshot (on iOS 26 it may sit in the bottom toolbar), tap it, then `idb ui text --udid … "Tahoe"` and screenshot `t4_search.png`. Expected: only Thanksgiving to Tahoe, and the search field still on screen. Then type a few more letters that match nothing (`idb ui text --udid … "zzz"`). Expected: `ContentUnavailableView.search`, and the field is still there.
```bash
$SCRATCH/seedSim.sh dark accessibility-extra-extra-extra-large
xcrun simctl io AA150836-B7E7-48C6-9CAE-4404B6DAB457 screenshot $SCRATCH/t4_dark_ax3.png
```
Expected: the hero card is readable, with bars stacked vertically and the name wrapping (no clipping). Rows put "US n · CA n" under the name. Rows use the system dark background. Then tap the hero and confirm Colorado to Utah's trip screen opens. Go back, tap the Great American Loop row, and confirm its trip screen opens.

- [ ] **Step 8: Commit**

```bash
git add -A myRoadTripTracker/myRoadTripTracker
git commit -m "Trip list: current hero card and past trips by year (#65)" -m "Replaces the card grid with an inset-grouped list: the most recently active open trip leads as a hero card, other open trips and past trips are compact rows, past trips are grouped by year, and search appears once there are more than five past trips."
```

---

### Task 5: Swipe and long-press actions

Outcome served: closing, reopening, deleting and leaving a trip are all one gesture from the list, and the same actions appear in the long-press menu and the trip screen.

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/ContentView.swift` (`tripRow`, `tripMenu`, new `closeButton`)

**Interfaces:**
- Consumes: Task 3 `TripLifecycle.setClosed(_:for:in:)`. Task 4 `tripRow(_:)`, `tripMenu(_:)`, `confirmDelete(_:)`, `confirmLeave(_:)`.

- [ ] **Step 1: Add `closeButton` and replace Task 4's `tripMenu` with this version**

```swift
    private func closeButton(_ trip: Trip) -> some View {
        Button {
            withAnimation {
                TripLifecycle.setClosed(!trip.isClosed, for: trip, in: viewContext)
            }
        } label: {
            Label(
                trip.isClosed ? "Reopen Trip" : "Close Trip",
                systemImage: trip.isClosed ? "lock.open" : "lock"
            )
        }
    }

    /// The same actions as the swipes and the trip screen; destructive last (HIG).
    @ViewBuilder
    private func tripMenu(_ trip: Trip) -> some View {
        if persistenceController.isOwner(of: trip) {
            closeButton(trip)
            Divider()
            Button(role: .destructive) { confirmDelete(trip) } label: {
                Label("Delete Trip", systemImage: "trash")
            }
        } else {
            Button(role: .destructive) { confirmLeave(trip) } label: {
                Label("Leave Trip", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }
```

- [ ] **Step 2: Replace Task 4's `tripRow` with this version, which adds swipe actions** (rows only; the hero keeps just the long-press menu)

```swift
    private func tripRow(_ trip: Trip) -> some View {
        NavigationLink(value: trip.objectID) {
            TripRow(trip: trip, isShared: isShared(trip))
        }
        .swipeActions(edge: .leading) {
            if persistenceController.isOwner(of: trip) {
                closeButton(trip)
                    .tint(trip.isClosed ? Theme.green : .gray)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Red by tint, not `role: .destructive`: a destructive swipe makes List animate
            // the row away at once, before the confirmation alert is answered.
            if persistenceController.isOwner(of: trip) {
                Button { confirmDelete(trip) } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            } else {
                Button { confirmLeave(trip) } label: {
                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .tint(.red)
            }
        }
        .contextMenu { tripMenu(trip) }
    }
```

- [ ] **Step 3: Build**

Run the **Build** command. Expected: `** BUILD SUCCEEDED **`, no warnings.

- [ ] **Step 4: Simulator check — swipes (Review Focus 3)**

`$SCRATCH/seedSim.sh light large`, then screenshot to find row positions.
- Swipe right across **Great American Loop** (`idb ui swipe --udid … 40 <y> 300 <y> --duration 0.4`) and screenshot. Expected: a gray **Close Trip** action. Tap it and screenshot. Expected: the row leaves the open section and appears in Past Trips · 2026 with a date range and an orange sparkle.
- Swipe left across a past row, e.g. **Lake Weekend** (`360 <y> 80 <y>`), and screenshot. Expected: a red **Delete** action. Tap it. Expected: the "Delete Trip" alert. Tap **Cancel** and screenshot. Expected: Lake Weekend is still in the list.
- Swipe right across a past row (**Lake Weekend**) and tap **Reopen Trip**. Expected: it moves to the open-trips section.

- [ ] **Step 5: Simulator check — hero menu and closing the last open trip (Review Focus 5)**

Long-press the hero (`idb ui tap --udid … <x> <y> --duration 1.2`) and screenshot. Expected: **Close Trip**, a separator, and **Delete Trip** in red. Tap **Close Trip**. Expected: the next most recent open trip becomes the hero. Keep closing the hero this way until no open trips remain, then screenshot. Expected: the **Current** section shows "No trip in progress" and a **Start a Trip** button. Tap the button. Expected: a new trip's screen opens. Go back. Expected: the new trip is the hero.

- [ ] **Step 6: Commit**

```bash
git add -A myRoadTripTracker/myRoadTripTracker
git commit -m "Swipe and long-press actions on trips (#65)" -m "Leading swipe closes or reopens (owners); trailing swipe deletes or leaves behind the existing confirmation. The long-press menu offers the same actions, destructive last."
```

---

### Task 6: Final verification, docs, and PR

Outcome served: proof that the redesigned screen works in both appearances and at large text sizes, with docs that describe the code as it now is.

**Files:**
- Modify: `CLAUDE.md` (Views line in "Source layout")
- Modify: `ARCHITECTURE.md` ("Trip list / cards" bullet, and the "Trip list grid (landed in 17a1f31…)" section)

- [ ] **Step 1: Clean build, zero warnings**

```bash
cd /Users/sam/code/apple/myRoadTripTracker && xcodebuild -project myRoadTripTracker/myRoadTripTracker.xcodeproj -scheme myRoadTripTracker \
  -destination 'platform=iOS Simulator,id=AA150836-B7E7-48C6-9CAE-4404B6DAB457' \
  -derivedDataPath $SCRATCH/dd clean build 2>&1 | grep -E "warning:|error:|BUILD (SUCCEEDED|FAILED)" | sort -u
```
Expected: exactly `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Screenshot matrix**

For each of `light large`, `dark large`, `light accessibility-extra-extra-extra-large` and `dark accessibility-extra-extra-extra-large`, run `$SCRATCH/seedSim.sh <appearance> <size>` and screenshot `final_<appearance>_<size>.png`. Look at each one. Expected:
- The hero card is readable.
- No clipped text.
- Rows use system backgrounds in both modes.
- No red/yellow/green progress colors.

- [ ] **Step 3: Contrast on the hero and the recap card**

Sample the hero's top strip in `final_light_large.png` and `final_dark_large.png` with `contrast.py`. Expected: PASS for both. Then open **Summer Coast Run**, open the overflow menu, tap **Trip Recap**, screenshot, and sample the recap card's top strip. Expected: PASS.

- [ ] **Step 4: Update docs**

- `CLAUDE.md`, Source layout: change `Views/       SwiftUI views (ContentView, TripCardView, TripDetailView,` to `Views/       SwiftUI views (ContentView, TripHeroCard, TripRow, TripDetailView,`.
- `ARCHITECTURE.md`: replace the "Trip list / cards" bullet with:
  `- **Trip list:** \`ContentView.swift\` (inset-grouped \`List\`: a \`TripHeroCard\` for the most recently active open trip, \`TripRow\`s for other open trips and for past trips by year; grouping in \`Services/TripListSections.swift\`; close/reopen/delete in \`Services/TripLifecycle.swift\`)`
- `ARCHITECTURE.md`: replace the whole "## Trip list grid (landed in 17a1f31, 2026-04-25)" section with:
  ```markdown
  ## Trip list (redesigned 2026-10-12, #65)

  - Inset-grouped `List`. **Current**: the open trip with the latest activity as a hero card (same rule as Siri's current trip, `Trip.byRecentActivity`), then other open trips as rows. **Past Trips**: closed trips by year of last activity. Search appears with more than 5 past trips.
  - Actions everywhere: leading swipe Close/Reopen (owner), trailing swipe Delete (owner) / Leave (participant), the same in the long-press menu; Delete Trip is also in the trip screen's overflow menu.
  - Panels with white text use `Theme.panel(closed:)` (darkens downward; ≥ 4.5:1). Progress is `RegionProgressBars`, single hue; the red/yellow/green `DualProgressRingView` is gone.
  ```

- [ ] **Step 5: Commit docs**

```bash
git add CLAUDE.md ARCHITECTURE.md
git commit -m "docs: describe the redesigned trip list (#65)"
```

- [ ] **Step 6: Push and open the PR (do not merge)**

```bash
git push
gh pr create --title "Trips screen redesign: current hero, past trips by year, swipe actions (#65)" --body "<body>"
```
The PR body covers:
- **Why:** the HIG review findings.
- **What changed:** per task.
- **How verified:** the gates above, with the contrast numbers measured and the screenshot list.
- `Closes #65` and `Closes #14`.
- **No attribution lines.**

Then add a comment to #61 (device check): "Build after #65: check a Siri 'how many plates' card shows the new progress bars on the darker green, light and dark." Merging waits for the user's "merge".
