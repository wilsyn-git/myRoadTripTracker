# Siri and Spotlight (App Intents) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a road trip, a family can log a plate ("We saw Maine in TripSpotter") and ask about their trip ("How many states have we seen in TripSpotter?") by voice. The answers come back spoken with a card, without opening the app, on a locked phone and on CarPlay. A one-time "Ask Siri" card tells existing users the feature exists.

**Architecture:** App Intents compiled into the app target, in a new auto-discovered `Intents/` folder. Intents reach Core Data only through `PersistenceController.shared`, whose stores load synchronously in `init`, so a background launch with no UI works. Spoken lines come from a pure `IntentAnswers` builder over a value `TripSnapshot`. The one opening intent hands off through a small `IntentRoute` that `ContentView` reads.

**Tech Stack:** Swift (language mode 5, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, approachable concurrency), SwiftUI, AppIntents, Core Data + `NSPersistentCloudKitContainer`, CoreLocation. iOS 26.1 deployment target, Xcode 27.

**Spec:** `docs/superpowers/specs/2026-10-09-appIntentsDesign.md` — read it before any task.

## Global Constraints

- **Do not edit `project.pbxproj`.** New `.swift` files under `myRoadTripTracker/myRoadTripTracker/` are auto-discovered (`PBXFileSystemSynchronizedRootGroup`).
- **There is no test target.** Don't create one and don't run `xcodebuild test`. Each task's gate is the build command below.
- **Build gate** (from the repo root, explicit timeout 600 s):
  `xcodebuild -project myRoadTripTracker/myRoadTripTracker.xcodeproj -scheme myRoadTripTracker -destination 'generic/platform=iOS Simulator' -quiet build 2>&1 | tail -40`
  Expected: no `error:` lines. Fix every new warning in files you created.
- **Isolation rule:** the target defaults to `@MainActor`. Declare every `AppIntent`, `AppEnum`, `AppEntity`, `EntityQuery` and `AppShortcutsProvider` type `nonisolated` (for example `nonisolated struct TripCountIntent: AppIntent`), and mark `perform()` and the query methods `@MainActor`. Anything touching `Trip`, `PlateSighting`, `Location`'s static lists or `PersistenceController` stays `@MainActor`. If the compiler still rejects a conformance, fix it the narrowest way and record that in the commit message.
- **Every App Shortcut phrase contains `\(.applicationName)`** and at most one parameter.
- **Privacy:** location comes from one fix only, **only if when-in-use is already granted**, never via a prompt from an intent, and falls back to `0,0`. No background location, no route tracking.
- **NotificationCenter observers are closure-based** (CLAUDE.md sharp edge 6).
- **Plate writes copy the tap path:** `PlateSighting(context:…)`, set `sighting.trip = trip`, save. Never call `assign(_:to:)` on a sighting.
- **Spoken copy is exactly the spec's** (table "The six intents" and "Edge cases"). Don't paraphrase.
- **Brand colors:** open-trip green `Color(red: 0.2, green: 0.65, blue: 0.35)`, closed-trip gray `Color(white: 0.38)` (from `TripCardView.cardColor`).
- **Commit style:** `feat: …` / `docs: …`, no AI attribution, on branch `feature/appIntents`.

## Review Focus

There is no test target, so each line below is handled in code in the task that owns it, and checked in Task 7's harness or the device checklist.

1. **Siri hears "Washington" or "DC".** "Washington" must resolve to WA. "DC", "D.C.", "Washington DC" and "District of Columbia" must resolve to DC. "Newfoundland", "PEI" and "Yukon" also resolve. (Task 1 synonyms; device check.)
2. **A joined (shared) trip with a nil `tripID`.** The backfill only repairs the private store. Such a trip has no `TripEntity`, but it must still be found as the *current* trip, because `resolve(nil)` never reads `tripID`. (Task 1.)
3. **`spottedByName` that's empty or only spaces.** Treat it as no name. Siri must never say "Yes — spotted Ohio" with a blank name, and the speaker must never be credited as "". (Tasks 2 and 3.)
4. **The same plate lands while a voice mark waits for GPS** (a tap, or a sync from another phone). Re-check for a duplicate after every `await` and before inserting. (Task 3.)
5. **"Open my trip" arrives before `ContentView` exists** (cold launch, or onboarding not finished). The route stays pending and is applied when `ContentView` appears (`onChange(…, initial: true)`). (Task 4.)

## File map

| File | Status | Responsibility |
|---|---|---|
| `Intents/PlateRegion.swift` | new | 64-case `AppEnum` + `Location.byCode` + debug consistency assert |
| `Intents/IntentAnswers.swift` | new | `TripSnapshot`, `Spotter`, pure spoken-line builders, trip-name matching |
| `Intents/IntentTrips.swift` | new | `IntentFailure`, trip lookup, current-trip rule, snapshot, speaker name, `markPlate` |
| `Intents/TripEntity.swift` | new | `TripEntity` + `TripQuery` |
| `Intents/TripIntents.swift` | new | Count, have-we-seen, plates-left, top-spotter intents |
| `Intents/MarkPlateIntent.swift` | new | The one writing intent |
| `Intents/OpenTripIntent.swift` | new | Opens the app on a trip |
| `Intents/IntentSnippets.swift` | new | The five Siri cards |
| `Intents/TripSpotterShortcuts.swift` | new | `AppShortcutsProvider` |
| `Services/IntentRoute.swift` | new | Pending trip to open |
| `Services/WhatsNew.swift` | new | `Announcement`, `WhatsNew`, `WhatsNewStore` |
| `Views/WhatsNewSheet.swift` | new | The "Ask Siri" card |
| `Services/LocationManager.swift` | modify | `requestFixIfAuthorized(timeout:)` |
| `Services/PersistenceController.swift` | modify | `awaitExport(after:timeout:)` |
| `Views/ContentView.swift` | modify | Route handling, shortcut-parameter refresh, what's-new sheet |
| `App/myRoadTripTrackerApp.swift` | modify | DEBUG `PlateRegion` assert |
| `CLAUDE.md` | modify | Add `Intents/` to the source layout |

All source paths are relative to `myRoadTripTracker/myRoadTripTracker/`.

---

### Task 1: Read path + "How many states have we seen"

**Outcome:** "How many states have we seen in TripSpotter?" answers with the current trip's count, even when Siri launches the app in the background.

**Files:**
- Create: `Intents/PlateRegion.swift`, `Intents/IntentAnswers.swift`, `Intents/IntentTrips.swift`, `Intents/TripEntity.swift`, `Intents/TripIntents.swift`, `Intents/TripSpotterShortcuts.swift`
- Modify: `App/myRoadTripTrackerApp.swift`

**Interfaces — produces:**
- `nonisolated enum PlateRegion: String, AppEnum` (raw value = `Location.code`); `@MainActor var location: Location`
- `extension Location { static let byCode: [String: Location] }`
- `struct TripSnapshot { name, isClosed, sightings: [Sighting] }`, `TripSnapshot.Sighting { code, name, spottedBy: String?, seenDate: Date? }`; extension members `usCodes`, `caCodes`, `seenCodes`, `usSeen`, `caSeen`, `unseen: [Location]`, `sighting(of:)`, `tally: [Spotter]`
- `struct Spotter: Equatable { name, count, isUnknown }`
- `enum IntentAnswers` with `count(_:)`, `spokenDay(_:now:calendar:)`, `states(_:)`, `list(_:)`, `tripName(_:matches:)`, `cleanName(_:)`
- `enum IntentFailure: Error, CustomLocalizedStringResourceConvertible`
- `@MainActor enum IntentTrips` with `allTrips()`, `resolve(_ entity: TripEntity?) throws -> Trip`, `currentTrip(in:)`, `snapshot(of:)`
- `nonisolated struct TripEntity: AppEntity` (`id` = `tripID.uuidString`), `TripQuery: EntityStringQuery`
- `nonisolated struct TripCountIntent: AppIntent` (param `trip: TripEntity?`)
- `nonisolated struct TripSpotterShortcuts: AppShortcutsProvider`

- [ ] **Step 1: Create `Intents/PlateRegion.swift`**

```swift
import AppIntents

/// The 64 plates as Siri names them. Raw values are `Location.code`.
///
/// The App Intents compiler needs the cases and their display representations as
/// literals, so this can't be built from `Location.allLocations`. In debug builds,
/// `assertMatchesLocations()` runs at launch and keeps the two lists in step.
nonisolated enum PlateRegion: String, AppEnum {
    case alabama = "AL", alaska = "AK", arizona = "AZ", arkansas = "AR", california = "CA"
    case colorado = "CO", connecticut = "CT", delaware = "DE", districtOfColumbia = "DC", florida = "FL"
    case georgia = "GA", hawaii = "HI", idaho = "ID", illinois = "IL", indiana = "IN"
    case iowa = "IA", kansas = "KS", kentucky = "KY", louisiana = "LA", maine = "ME"
    case maryland = "MD", massachusetts = "MA", michigan = "MI", minnesota = "MN", mississippi = "MS"
    case missouri = "MO", montana = "MT", nebraska = "NE", nevada = "NV", newHampshire = "NH"
    case newJersey = "NJ", newMexico = "NM", newYork = "NY", northCarolina = "NC", northDakota = "ND"
    case ohio = "OH", oklahoma = "OK", oregon = "OR", pennsylvania = "PA", rhodeIsland = "RI"
    case southCarolina = "SC", southDakota = "SD", tennessee = "TN", texas = "TX", utah = "UT"
    case vermont = "VT", virginia = "VA", washington = "WA", westVirginia = "WV", wisconsin = "WI"
    case wyoming = "WY"
    case alberta = "AB", britishColumbia = "BC", manitoba = "MB", newBrunswick = "NB"
    case newfoundlandAndLabrador = "NL", novaScotia = "NS", ontario = "ON", princeEdwardIsland = "PE"
    case quebec = "QC", saskatchewan = "SK", northwestTerritories = "NT", nunavut = "NU", yukon = "YT"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Plate"

    // "Washington" is the state; DC answers only to its own names (spec, "Decisions").
    static let caseDisplayRepresentations: [PlateRegion: DisplayRepresentation] = [
        .alabama: "Alabama", .alaska: "Alaska", .arizona: "Arizona", .arkansas: "Arkansas",
        .california: "California", .colorado: "Colorado", .connecticut: "Connecticut",
        .delaware: "Delaware",
        .districtOfColumbia: DisplayRepresentation(
            title: "District of Columbia",
            synonyms: ["DC", "D.C.", "Washington DC", "Washington D.C."]
        ),
        .florida: "Florida", .georgia: "Georgia", .hawaii: "Hawaii", .idaho: "Idaho",
        .illinois: "Illinois", .indiana: "Indiana", .iowa: "Iowa", .kansas: "Kansas",
        .kentucky: "Kentucky", .louisiana: "Louisiana", .maine: "Maine", .maryland: "Maryland",
        .massachusetts: "Massachusetts", .michigan: "Michigan", .minnesota: "Minnesota",
        .mississippi: "Mississippi", .missouri: "Missouri", .montana: "Montana",
        .nebraska: "Nebraska", .nevada: "Nevada", .newHampshire: "New Hampshire",
        .newJersey: "New Jersey", .newMexico: "New Mexico", .newYork: "New York",
        .northCarolina: "North Carolina", .northDakota: "North Dakota", .ohio: "Ohio",
        .oklahoma: "Oklahoma", .oregon: "Oregon", .pennsylvania: "Pennsylvania",
        .rhodeIsland: "Rhode Island", .southCarolina: "South Carolina",
        .southDakota: "South Dakota", .tennessee: "Tennessee", .texas: "Texas", .utah: "Utah",
        .vermont: "Vermont", .virginia: "Virginia",
        .washington: DisplayRepresentation(title: "Washington", synonyms: ["Washington State"]),
        .westVirginia: "West Virginia", .wisconsin: "Wisconsin", .wyoming: "Wyoming",
        .alberta: "Alberta",
        .britishColumbia: DisplayRepresentation(title: "British Columbia", synonyms: ["BC", "B.C."]),
        .manitoba: "Manitoba", .newBrunswick: "New Brunswick",
        .newfoundlandAndLabrador: DisplayRepresentation(
            title: "Newfoundland and Labrador",
            synonyms: ["Newfoundland", "Labrador"]
        ),
        .novaScotia: "Nova Scotia", .ontario: "Ontario",
        .princeEdwardIsland: DisplayRepresentation(title: "Prince Edward Island", synonyms: ["PEI", "P.E.I."]),
        .quebec: DisplayRepresentation(title: "Quebec", synonyms: ["Québec"]),
        .saskatchewan: "Saskatchewan",
        .northwestTerritories: DisplayRepresentation(title: "Northwest Territories", synonyms: ["NWT"]),
        .nunavut: "Nunavut",
        .yukon: DisplayRepresentation(title: "Yukon", synonyms: ["Yukon Territory"]),
    ]

    @MainActor
    var location: Location {
        guard let location = Location.byCode[rawValue] else {
            preconditionFailure("PlateRegion \(rawValue) has no Location")
        }
        return location
    }

    #if DEBUG
    /// Fails fast in debug builds if a region is added to one list and not the other.
    @MainActor
    static func assertMatchesLocations() {
        let codes = Set(allCases.map(\.rawValue))
        let expected = Set(Location.allLocations.map(\.code))
        assert(codes == expected,
               "PlateRegion out of step with Location.allLocations: missing \(expected.subtracting(codes)), extra \(codes.subtracting(expected))")
        for region in allCases {
            let title = String(localized: caseDisplayRepresentations[region]?.title ?? "")
            assert(title == region.location.name, "PlateRegion \(region.rawValue) title \"\(title)\" ≠ \"\(region.location.name)\"")
        }
    }
    #endif
}

extension Location {
    static let byCode: [String: Location] = Dictionary(uniqueKeysWithValues: allLocations.map { ($0.code, $0) })
}
```

- [ ] **Step 2: Create `Intents/IntentAnswers.swift`** (the pure builder: no Core Data, no AppIntents)

```swift
import Foundation

/// A trip as the intents read it: plain values, no Core Data.
struct TripSnapshot {
    struct Sighting {
        let code: String
        let name: String
        let spottedBy: String?
        let seenDate: Date?
    }

    let name: String
    let isClosed: Bool
    /// Oldest first.
    let sightings: [Sighting]
}

/// One row of the "who's spotted the most" tally.
struct Spotter: Equatable {
    let name: String
    let count: Int
    /// Sightings with no `spottedByName`. Shown last, never leads the spoken line.
    let isUnknown: Bool
}

extension TripSnapshot {
    static let usCodes = Set(Location.usStates.map(\.code))
    static let caCodes = Set(Location.canadaLocations.map(\.code))

    var seenCodes: Set<String> { Set(sightings.map(\.code)) }
    var usSeen: Int { seenCodes.intersection(Self.usCodes).count }
    var caSeen: Int { seenCodes.intersection(Self.caCodes).count }

    /// Unseen plates in the grid's order: US then Canada.
    var unseen: [Location] {
        let seen = seenCodes
        return Location.allLocations.filter { !seen.contains($0.code) }
    }

    func sighting(of code: String) -> Sighting? {
        sightings.first { $0.code == code }
    }

    /// Spotters by count (then name), with an "Unknown" row last for uncredited sightings.
    var tally: [Spotter] {
        var counts: [String: Int] = [:]
        var unknown = 0
        for sighting in sightings {
            if let name = IntentAnswers.cleanName(sighting.spottedBy) {
                counts[name, default: 0] += 1
            } else {
                unknown += 1
            }
        }
        var ranked = counts
            .map { Spotter(name: $0.key, count: $0.value, isUnknown: false) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCompare($1.name) == .orderedAscending }
        if unknown > 0 {
            ranked.append(Spotter(name: "Unknown", count: unknown, isUnknown: true))
        }
        return ranked
    }
}

/// What Siri says. Values in, sentence out. Copy is the spec's
/// (`docs/superpowers/specs/2026-10-09-appIntentsDesign.md`, "The six intents").
enum IntentAnswers {

    static func count(_ trip: TripSnapshot) -> String {
        switch (trip.usSeen, trip.caSeen) {
        case (0, 0): "Nothing spotted on \(trip.name) yet."
        case (let us, 0): "On \(trip.name) you've seen \(states(us))."
        case (0, let ca): "On \(trip.name) you've seen \(ca) from Canada."
        case (let us, let ca): "On \(trip.name) you've seen \(states(us)) and \(ca) from Canada."
        }
    }

    // MARK: Helpers shared by every answer

    /// "today", "yesterday", "on Tuesday" (2–6 days ago), else "on Sep 30".
    static func spokenDay(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? .max
        if (2...6).contains(days) { return "on " + date.formatted(.dateTime.weekday(.wide)) }
        return "on " + date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func states(_ count: Int) -> String {
        count == 1 ? "1 state" : "\(count) states"
    }

    /// "A", "A and B", "A, B, and C".
    static func list(_ items: [String]) -> String {
        ListFormatter.localizedString(byJoining: items)
    }

    /// A display name worth saying aloud, or nil for nil / empty / whitespace.
    static func cleanName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Trip-name matching for `TripQuery`: "the Utah trip" finds "Utah 2026".
    static func tripName(_ name: String, matches query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if name.localizedStandardContains(trimmed) { return true }
        var stripped = trimmed.lowercased()
        if stripped.hasPrefix("the ") { stripped.removeFirst(4) }
        if stripped.hasSuffix(" trip") { stripped.removeLast(5) }
        return !stripped.isEmpty && name.localizedStandardContains(stripped)
    }
}
```

- [ ] **Step 3: Create `Intents/IntentTrips.swift`**

```swift
import AppIntents
import CoreData

/// What Siri says when an intent can't do what was asked (spec, "Edge cases").
nonisolated enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case storeUnavailable
    case noTrips
    case noOpenTrip
    case tripNotFound
    case tripClosed(String)
    case cannotEdit(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .storeUnavailable: "I couldn't open your trips just now."
        case .noTrips: "You don't have any trips yet. Start one in TripSpotter."
        case .noOpenTrip: "You don't have an open trip. Start one in TripSpotter."
        case .tripNotFound: "I couldn't find that trip."
        case .tripClosed(let name): "\(name) is closed."
        case .cannotEdit(let name): "You can't add to \(name)."
        }
    }
}

/// The intents' only door into Core Data. Works from a background launch:
/// `PersistenceController.shared` loads its stores synchronously in `init`,
/// and nothing here depends on a view existing.
@MainActor
enum IntentTrips {

    static var context: NSManagedObjectContext { PersistenceController.shared.viewContext }

    /// Every trip, open first, newest first (the trip list's order).
    static func allTrips() throws -> [Trip] {
        guard PersistenceController.shared.setupError == nil else { throw IntentFailure.storeUnavailable }
        let request = Trip.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Trip.isClosed, ascending: true),
            NSSortDescriptor(keyPath: \Trip.createdDate, ascending: false),
        ]
        do {
            return try context.fetch(request)
        } catch {
            throw IntentFailure.storeUnavailable
        }
    }

    /// The trip a request means: the one named, else the current trip.
    /// Never reads `tripID` when no trip is named, so a joined trip with a nil
    /// `tripID` can still be the current trip.
    static func resolve(_ entity: TripEntity?) throws -> Trip {
        let trips = try allTrips()
        if let entity {
            guard let trip = trips.first(where: { $0.tripID?.uuidString == entity.id }) else {
                throw IntentFailure.tripNotFound
            }
            return trip
        }
        guard !trips.isEmpty else { throw IntentFailure.noTrips }
        guard let current = currentTrip(in: trips) else { throw IntentFailure.noOpenTrip }
        return current
    }

    /// Spec, "Decisions": the open trip with the most recent activity — latest
    /// sighting, else creation date.
    static func currentTrip(in trips: [Trip]) -> Trip? {
        trips.filter { !$0.isClosed }.max { lastActivity($0) < lastActivity($1) }
    }

    private static func lastActivity(_ trip: Trip) -> Date {
        let sightings = (trip.plateSightings as? Set<PlateSighting>) ?? []
        return sightings.compactMap(\.seenDate).max() ?? trip.createdDate ?? .distantPast
    }

    static func snapshot(of trip: Trip) -> TripSnapshot {
        TripSnapshot(
            name: trip.name,
            isClosed: trip.isClosed,
            sightings: trip.plateSightingsArray.map {
                TripSnapshot.Sighting(code: $0.locationCode, name: $0.locationName,
                                      spottedBy: $0.spottedByName, seenDate: $0.seenDate)
            }
        )
    }
}
```

- [ ] **Step 4: Create `Intents/TripEntity.swift`**

```swift
import AppIntents

/// A trip as Siri names it. Trips without a `tripID` (a joined trip the
/// backfill can't repair) have no entity; they're still reachable as the
/// current trip.
nonisolated struct TripEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Trip"
    static let defaultQuery = TripQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    @MainActor
    init?(_ trip: Trip) {
        guard let id = trip.tripID?.uuidString else { return nil }
        self.init(id: id, name: trip.name)
    }
}

/// Trips by name. None or several matches make Siri ask "Which trip?".
nonisolated struct TripQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [TripEntity] {
        try IntentTrips.allTrips().compactMap(TripEntity.init).filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [TripEntity] {
        try IntentTrips.allTrips().compactMap(TripEntity.init).filter { IntentAnswers.tripName($0.name, matches: string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TripEntity] {
        try IntentTrips.allTrips().compactMap(TripEntity.init)
    }
}
```

- [ ] **Step 5: Create `Intents/TripIntents.swift`** with the count intent

```swift
import AppIntents

// The read-only trip questions. Each answers in the background, locked or not
// (spec, "Decisions": locked phone).

nonisolated struct TripCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Trip Count"
    static let description = IntentDescription("How many states and Canadian plates you've seen on a trip.")

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = try IntentTrips.snapshot(of: IntentTrips.resolve(trip))
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.count(snapshot)))
    }
}
```

- [ ] **Step 6: Create `Intents/TripSpotterShortcuts.swift`**

```swift
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
```

- [ ] **Step 7: Add the debug assert to `App/myRoadTripTrackerApp.swift`**

Add this initializer inside `struct myRoadTripTrackerApp`, after the `@State private var persistenceController` line:

```swift
    init() {
        #if DEBUG
        PlateRegion.assertMatchesLocations()
        #endif
    }
```

- [ ] **Step 8: Build gate** — run the Global Constraints build command. Expected: no errors.

- [ ] **Step 9: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/Intents myRoadTripTracker/myRoadTripTracker/App/myRoadTripTrackerApp.swift
git commit -m "feat: answer \"how many states have we seen\" through Siri"
```

---

### Task 2: Have-we-seen, plates-left and top-spotter

**Outcome:** "Have we seen Ohio?", "Which states are left?" and "Who's spotted the most?" answer by voice for the current trip.

**Files:**
- Modify: `Intents/IntentAnswers.swift`, `Intents/TripIntents.swift`, `Intents/TripSpotterShortcuts.swift`

**Interfaces:**
- Consumes (Task 1): `TripSnapshot`, `Spotter`, `IntentAnswers.spokenDay/states/list/cleanName`, `IntentTrips.resolve/snapshot`, `TripEntity`, `PlateRegion.location`
- Produces: `IntentAnswers.haveWeSeen(_:in:now:)`, `left(_:)`, `topSpotter(_:)`; `HaveWeSeenIntent` (params `region: PlateRegion`, `trip: TripEntity?`), `PlatesLeftIntent` (`trip`), `TopSpotterIntent` (`trip`)

- [ ] **Step 1: Add the builders to `IntentAnswers`** (insert after `count(_:)`)

```swift
    static func haveWeSeen(_ location: Location, in trip: TripSnapshot, now: Date = .now) -> String {
        guard let sighting = trip.sighting(of: location.code) else {
            return "Not yet. \(location.name)'s still out there."
        }
        let day = sighting.seenDate.map { " " + spokenDay($0, now: now) } ?? ""
        if let who = cleanName(sighting.spottedBy) {
            return "Yes — \(who) spotted \(location.name)\(day)."
        }
        return "Yes — \(location.name) was spotted\(day)."
    }

    static func left(_ trip: TripSnapshot) -> String {
        let unseen = trip.unseen
        if unseen.isEmpty { return "You've seen every plate on \(trip.name)!" }
        if trip.sightings.isEmpty { return "All \(Location.allLocations.count) to go." }
        if unseen.count <= 8 { return "Still missing: \(list(unseen.map(\.name)))." }
        let usLeft = unseen.filter { TripSnapshot.usCodes.contains($0.code) }.count
        let caLeft = unseen.count - usLeft
        let parts = [usLeft > 0 ? states(usLeft) : nil, caLeft > 0 ? "\(caLeft) from Canada" : nil].compactMap { $0 }
        return "\(list(parts)) to go — they're on the card."
    }

    static func topSpotter(_ trip: TripSnapshot) -> String {
        guard !trip.sightings.isEmpty else { return "Nobody's spotted a plate on \(trip.name) yet." }
        let named = trip.tally.filter { !$0.isUnknown }
        guard let top = named.first else { return "Nobody's been credited with a plate on \(trip.name) yet." }
        let leaders = named.filter { $0.count == top.count }
        if leaders.count > 1 {
            return "\(list(leaders.map(\.name))) are tied with \(top.count)."
        }
        if named.count == 1 {
            return top.count == trip.sightings.count
                ? "\(top.name) has spotted all \(top.count)."
                : "\(top.name) has spotted \(top.count)."
        }
        let second = named[1]
        return "\(top.name) leads \(trip.name) with \(top.count). \(second.name) has \(second.count)."
    }
```

- [ ] **Step 2: Append the three intents to `Intents/TripIntents.swift`**

```swift
nonisolated struct HaveWeSeenIntent: AppIntent {
    static let title: LocalizedStringResource = "Have We Seen a Plate"
    static let description = IntentDescription("Whether a state or province is already ticked off, and who spotted it.")

    @Parameter(title: "Plate", requestValueDialog: "Which plate?")
    var region: PlateRegion

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = try IntentTrips.snapshot(of: IntentTrips.resolve(trip))
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.haveWeSeen(region.location, in: snapshot)))
    }
}

nonisolated struct PlatesLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Plates Left"
    static let description = IntentDescription("The states and provinces you haven't spotted yet.")

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = try IntentTrips.snapshot(of: IntentTrips.resolve(trip))
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.left(snapshot)))
    }
}

nonisolated struct TopSpotterIntent: AppIntent {
    static let title: LocalizedStringResource = "Top Spotter"
    static let description = IntentDescription("Who has spotted the most plates on a trip.")

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = try IntentTrips.snapshot(of: IntentTrips.resolve(trip))
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.topSpotter(snapshot)))
    }
}
```

- [ ] **Step 3: Add the three shortcuts to `TripSpotterShortcuts.appShortcuts`** (after the count shortcut)

```swift
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
```

- [ ] **Step 4: Build gate.** Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/Intents
git commit -m "feat: answer have-we-seen, plates-left and top-spotter through Siri"
```

---

### Task 3: "We saw Maine" — marking a plate by voice

**Outcome:** "We saw Maine in TripSpotter" adds Maine to the current trip, credits the speaker, and gives the upload a chance to reach the other phones before iOS suspends the app.

**Files:**
- Modify: `Services/LocationManager.swift`, `Services/PersistenceController.swift`, `Intents/IntentTrips.swift`, `Intents/IntentAnswers.swift`, `Intents/TripSpotterShortcuts.swift`
- Create: `Intents/MarkPlateIntent.swift`

**Interfaces:**
- Consumes (Tasks 1–2): `IntentTrips.resolve/snapshot/context`, `IntentFailure`, `IntentAnswers.spokenDay/cleanName`, `PlateRegion.location`, `CloudKitUserHelper.currentUserID()`, `PersistenceController.canEdit(_:)`, `NSManagedObjectContext.trySave(contextInfo:)`
- Produces: `LocationManager.requestFixIfAuthorized(timeout: Duration) async -> CLLocation?`; `PersistenceController.awaitExport(after: Date, timeout: Duration) async`; `IntentTrips.MarkOutcome { case added(number: Int), alreadySeen(TripSnapshot.Sighting) }`; `IntentTrips.speakerName(for:) async -> String`; `IntentTrips.markPlate(_:on:) async throws -> MarkOutcome`; `IntentAnswers.marked(_:number:tripName:)`, `alreadySeen(_:sighting:now:)`; `MarkPlateIntent` (params `region`, `trip`)

- [ ] **Step 1: Add `requestFixIfAuthorized` to `LocationManager`** (after `requestCurrentLocation`)

```swift
    /// One fix for a Siri request: never prompts for permission, gives up after `timeout`.
    /// Returns nil when not already authorized, when iOS won't locate a background launch,
    /// or on timeout; the caller then records `0,0` (privacy invariants, CLAUDE.md).
    func requestFixIfAuthorized(timeout: Duration) async -> CLLocation? {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return nil
        }
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self.resumeLocationContinuations(with: nil)
        }
        let location = await withCheckedContinuation { continuation in
            locationContinuations.append(continuation)
            manager.requestLocation()
        }
        timeoutTask.cancel()
        return location
    }

    /// Drain and resume all pending location continuations exactly once.
    private func resumeLocationContinuations(with location: CLLocation?) {
        let pending = locationContinuations
        locationContinuations = []
        for continuation in pending {
            continuation.resume(returning: location)
        }
    }
```

- [ ] **Step 2: Add `awaitExport` to `PersistenceController`** (new `// MARK: - Export` section before `// MARK: - Sharing`)

```swift
    // MARK: - Export

    /// Waits until CloudKit reports an export that finished after `date`, or until `timeout`.
    /// A Siri mark runs in a short background launch; this gives the new sighting a chance
    /// to upload before iOS suspends the app (spec, "Sync after a voice mark").
    func awaitExport(after date: Date, timeout: Duration) async {
        let center = NotificationCenter.default
        var observer: NSObjectProtocol?
        let exported = AsyncStream<Void> { continuation in
            observer = center.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: persistentContainer,
                queue: .main
            ) { note in
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event,
                      event.type == .export,
                      let end = event.endDate, end >= date else { return }
                continuation.yield()
            }
        }
        defer { if let observer { center.removeObserver(observer) } }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { for await _ in exported { return } }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }
```

- [ ] **Step 3: Add marking to `IntentTrips`** (inside the enum, after `snapshot(of:)`)

```swift
    enum MarkOutcome {
        /// `number` is how many distinct plates the trip now has.
        case added(number: Int)
        case alreadySeen(TripSnapshot.Sighting)
    }

    /// The name a tap would credit: your display name on this trip, else the
    /// default display name, else "Me". Never creates a `TripParticipant`.
    static func speakerName(for trip: Trip) async -> String {
        let userID = await CloudKitUserHelper.currentUserID()
        if let participant = trip.participantsArray.first(where: { $0.cloudKitUserID == userID }),
           let name = IntentAnswers.cleanName(participant.displayName) {
            return name
        }
        return IntentAnswers.cleanName(UserDefaults.standard.string(forKey: "defaultDisplayName")) ?? "Me"
    }

    /// Adds `region` to `trip` the way `PlateSightingsGrid.markAsSeen` does.
    static func markPlate(_ region: PlateRegion, on trip: Trip) async throws -> MarkOutcome {
        guard !trip.isClosed else { throw IntentFailure.tripClosed(trip.name) }
        guard PersistenceController.shared.canEdit(trip) else { throw IntentFailure.cannotEdit(trip.name) }
        let location = region.location
        if let existing = snapshot(of: trip).sighting(of: location.code) { return .alreadySeen(existing) }

        let name = await speakerName(for: trip)
        let fix = await LocationManager().requestFixIfAuthorized(timeout: .seconds(3))

        // A tap or a sync may have added it while we waited.
        if let existing = snapshot(of: trip).sighting(of: location.code) { return .alreadySeen(existing) }

        let sighting = PlateSighting(
            context: context,
            locationCode: location.code,
            locationName: location.name,
            latitude: fix?.coordinate.latitude ?? 0.0,
            longitude: fix?.coordinate.longitude ?? 0.0,
            spottedByName: name
        )
        sighting.trip = trip
        let savedAt = Date.now
        do {
            try context.trySave(contextInfo: "intentMarkPlate")
        } catch {
            context.delete(sighting)
            throw IntentFailure.storeUnavailable
        }
        await PersistenceController.shared.awaitExport(after: savedAt, timeout: .seconds(5))
        return .added(number: snapshot(of: trip).seenCodes.count)
    }
```

- [ ] **Step 4: Add the two builders to `IntentAnswers`** (after `topSpotter(_:)`)

```swift
    static func marked(_ location: Location, number: Int, tripName: String) -> String {
        "Got it — \(location.name) is number \(number) on \(tripName)."
    }

    static func alreadySeen(_ location: Location, sighting: TripSnapshot.Sighting, now: Date = .now) -> String {
        let day = sighting.seenDate.map { " " + spokenDay($0, now: now) } ?? ""
        if let who = cleanName(sighting.spottedBy) {
            return "\(location.name)'s already on the list — \(who) spotted it\(day)."
        }
        if !day.isEmpty {
            return "\(location.name)'s already on the list — spotted\(day)."
        }
        return "\(location.name)'s already on the list."
    }
```

- [ ] **Step 5: Create `Intents/MarkPlateIntent.swift`**

```swift
import AppIntents

/// "We saw Maine in TripSpotter." The only intent that writes. Runs locked
/// (spec, "Decisions"): plate names are low-stakes.
nonisolated struct MarkPlateIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark a Plate"
    static let description = IntentDescription("Ticks off a state or province on your current trip.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Plate", requestValueDialog: "Which plate did you see?")
    var region: PlateRegion

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target = try IntentTrips.resolve(trip)
        let location = region.location
        let outcome = try await IntentTrips.markPlate(region, on: target)
        let line = switch outcome {
        case .added(let number): IntentAnswers.marked(location, number: number, tripName: target.name)
        case .alreadySeen(let sighting): IntentAnswers.alreadySeen(location, sighting: sighting)
        }
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}
```

- [ ] **Step 6: Add the shortcut as the first entry in `TripSpotterShortcuts.appShortcuts`**

```swift
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
```

- [ ] **Step 7: Build gate.** Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/Intents myRoadTripTracker/myRoadTripTracker/Services/LocationManager.swift myRoadTripTracker/myRoadTripTracker/Services/PersistenceController.swift
git commit -m "feat: mark a plate by voice (\"We saw Maine in TripSpotter\")"
```

---

### Task 4: "Open my trip", plus trip names Siri can say

**Outcome:** "Open my trip in TripSpotter" lands on the current trip's detail screen, and phrases with a trip name ("Who's winning Utah in TripSpotter") know the user's real trip names.

**Files:**
- Create: `Services/IntentRoute.swift`, `Intents/OpenTripIntent.swift`
- Modify: `Views/ContentView.swift`, `Intents/TripSpotterShortcuts.swift`

**Interfaces:**
- Consumes: `IntentTrips.resolve`, `TripEntity`, `TripSpotterShortcuts`
- Produces: `@Observable @MainActor final class IntentRoute` with `static let shared`, `private(set) var pendingTrip: NSManagedObjectID?`, `func open(_:)`, `func take() -> NSManagedObjectID?`; `OpenTripIntent` (param `trip`)

- [ ] **Step 1: Create `Services/IntentRoute.swift`**

```swift
import CoreData
import Observation

/// The trip a Siri or Spotlight request asked the app to open.
///
/// `OpenTripIntent` posts here and `ContentView` follows, so navigation stays in
/// one place. A request that arrives before `ContentView` exists (cold launch,
/// onboarding) waits until it appears.
@Observable @MainActor
final class IntentRoute {
    static let shared = IntentRoute()

    private(set) var pendingTrip: NSManagedObjectID?

    func open(_ trip: NSManagedObjectID) {
        pendingTrip = trip
    }

    /// The pending trip, cleared as it is handed over.
    func take() -> NSManagedObjectID? {
        defer { pendingTrip = nil }
        return pendingTrip
    }
}
```

- [ ] **Step 2: Create `Intents/OpenTripIntent.swift`**

```swift
import AppIntents

/// "Open my trip in TripSpotter." Opens the app, which needs the phone unlocked;
/// iOS asks for that itself.
nonisolated struct OpenTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Trip"
    static let description = IntentDescription("Opens a trip in TripSpotter — your current trip unless you name one.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        let target = try IntentTrips.resolve(trip)
        IntentRoute.shared.open(target.objectID)
        return .result()
    }
}
```

If `supportedModes` isn't available, use `static let openAppWhenRun = true` instead and say so in the commit message.

- [ ] **Step 3: Hook `ContentView` up.** In `tripList`, right after the existing `.onChange(of: trips.count) { … }` modifier, add:

```swift
        .onChange(of: IntentRoute.shared.pendingTrip, initial: true) { _, _ in
            guard let objectID = IntentRoute.shared.take() else { return }
            navigationPath = NavigationPath()
            navigationPath.append(objectID)
        }
        .task {
            TripSpotterShortcuts.updateAppShortcutParameters()
        }
        .onChange(of: trips.map(\.name)) { _, _ in
            // Keeps trip-name phrases ("Who's winning Utah…") current after a create, rename or delete.
            TripSpotterShortcuts.updateAppShortcutParameters()
        }
```

- [ ] **Step 4: Add the shortcut as the last entry in `TripSpotterShortcuts.appShortcuts`**

```swift
        AppShortcut(
            intent: OpenTripIntent(),
            phrases: [
                "Open my trip in \(.applicationName)",
                "Open \(\.$trip) in \(.applicationName)",
            ],
            shortTitle: "Open Trip",
            systemImageName: "car"
        )
```

- [ ] **Step 5: Build gate.** Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/Services/IntentRoute.swift myRoadTripTracker/myRoadTripTracker/Intents myRoadTripTracker/myRoadTripTracker/Views/ContentView.swift
git commit -m "feat: open the current trip from Siri and keep trip-name phrases current"
```

---

### Task 5: Siri cards

**Outcome:** Each spoken answer comes with a card that looks like TripSpotter's trip cards and reads well on Siri's light and dark panels.

**Files:**
- Create: `Intents/IntentSnippets.swift`
- Modify: `Intents/TripIntents.swift`, `Intents/MarkPlateIntent.swift`

**Interfaces:**
- Consumes: `TripSnapshot` and its extension members, `Location.byCode`, `Location.flagImageName`, `DualProgressRingView(usProgress:usSeenCount:usTotalCount:caProgress:caSeenCount:caTotalCount:)`
- Produces: `CountCard(trip:)`, `MarkCard(location:trip:)`, `SeenCard(location:trip:)`, `PlatesLeftCard(trip:)`, `TopSpotterCard(trip:)`

- [ ] **Step 1: Create `Intents/IntentSnippets.swift`**

```swift
import SwiftUI

// The cards Siri shows under its spoken line. They use the trip cards' green
// panel with white text (`TripCardView`), so they read as TripSpotter on Siri's
// light and dark panels alike. Spec: docs/superpowers/specs/2026-10-09-appIntentsDesign.md.

private enum SnippetStyle {
    static func panel(closed: Bool) -> Color {
        closed ? Color(white: 0.38) : Color(red: 0.2, green: 0.65, blue: 0.35)
    }
}

/// The frame every card shares: trip name on the left, a short fact on the right.
private struct SnippetShell<Content: View>: View {
    let title: String
    var trailing: String = ""
    var isClosed = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if isClosed {
                    Image(systemName: "lock.fill").font(.caption).accessibilityHidden(true)
                }
                Text(title).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                Text(trailing).font(.subheadline.weight(.semibold)).opacity(0.85).fixedSize()
            }
            content
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SnippetStyle.panel(closed: isClosed).gradient, in: .rect(cornerRadius: 16))
    }
}

/// A flag the way `TripCardView` draws its recent-sightings row.
private struct Flag: View {
    let assetName: String
    var width: CGFloat = 28

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: width * 0.64)
            .clipShape(.rect(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.6), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

private struct TripRing: View {
    let trip: TripSnapshot

    var body: some View {
        let usTotal = TripSnapshot.usCodes.count
        let caTotal = TripSnapshot.caCodes.count
        DualProgressRingView(
            usProgress: Double(trip.usSeen) / Double(usTotal),
            usSeenCount: trip.usSeen,
            usTotalCount: usTotal,
            caProgress: Double(trip.caSeen) / Double(caTotal),
            caSeenCount: trip.caSeen,
            caTotalCount: caTotal
        )
    }
}

struct CountCard: View {
    let trip: TripSnapshot

    var body: some View {
        SnippetShell(title: trip.name, isClosed: trip.isClosed) {
            HStack(spacing: 16) {
                TripRing(trip: trip)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(trip.usSeen) of \(TripSnapshot.usCodes.count) US").font(.title3.weight(.bold))
                    Text("\(trip.caSeen) of \(TripSnapshot.caCodes.count) Canada").font(.subheadline.weight(.semibold)).opacity(0.85)
                    HStack(spacing: -4) {
                        ForEach(Array(trip.sightings.suffix(5).reversed()), id: \.code) { sighting in
                            if let location = Location.byCode[sighting.code] {
                                Flag(assetName: location.flagImageName)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

struct MarkCard: View {
    let location: Location
    let trip: TripSnapshot

    var body: some View {
        let sighting = trip.sighting(of: location.code)
        SnippetShell(title: trip.name, trailing: "No. \(trip.seenCodes.count)", isClosed: trip.isClosed) {
            HStack(spacing: 14) {
                Flag(assetName: location.flagImageName, width: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name).font(.title3.weight(.bold)).lineLimit(2).minimumScaleFactor(0.8)
                    if let who = IntentAnswers.cleanName(sighting?.spottedBy) {
                        Text("by \(who)").font(.subheadline).opacity(0.85)
                    }
                }
                Spacer(minLength: 0)
                TripRing(trip: trip)
            }
        }
    }
}

struct SeenCard: View {
    let location: Location
    let trip: TripSnapshot

    var body: some View {
        let sighting = trip.sighting(of: location.code)
        SnippetShell(title: trip.name, isClosed: trip.isClosed) {
            HStack(spacing: 14) {
                Flag(assetName: location.flagImageName, width: 64)
                    .saturation(sighting == nil ? 0 : 1)
                    .opacity(sighting == nil ? 0.6 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name).font(.title3.weight(.bold)).lineLimit(2).minimumScaleFactor(0.8)
                    Text(status(sighting)).font(.subheadline).opacity(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: sighting == nil ? "circle.dashed" : "checkmark.circle.fill")
                    .font(.title2)
                    .accessibilityHidden(true)
            }
        }
    }

    private func status(_ sighting: TripSnapshot.Sighting?) -> String {
        guard let sighting else { return "Not yet" }
        let who = IntentAnswers.cleanName(sighting.spottedBy).map { "Spotted by \($0)" } ?? "Spotted"
        guard let date = sighting.seenDate else { return who }
        return "\(who) · \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

struct PlatesLeftCard: View {
    let trip: TripSnapshot

    private let columns = [GridItem(.adaptive(minimum: 38), spacing: 6)]

    var body: some View {
        let unseen = trip.unseen
        SnippetShell(title: trip.name, trailing: unseen.isEmpty ? "" : "\(unseen.count) left", isClosed: trip.isClosed) {
            if unseen.isEmpty {
                Label("Every plate spotted!", systemImage: "party.popper.fill").font(.title3.weight(.bold))
            } else {
                section("US", unseen.filter { TripSnapshot.usCodes.contains($0.code) })
                section("Canada", unseen.filter { TripSnapshot.caCodes.contains($0.code) })
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ locations: [Location]) -> some View {
        if !locations.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption.weight(.bold)).opacity(0.85)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(locations) { location in
                        Text(location.code)
                            .font(.caption.weight(.bold).monospaced())
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(.white.opacity(0.18), in: .rect(cornerRadius: 6))
                            .accessibilityLabel(location.name)
                    }
                }
            }
        }
    }
}

struct TopSpotterCard: View {
    let trip: TripSnapshot

    var body: some View {
        let tally = Array(trip.tally.prefix(6))
        let topCount = tally.first(where: { !$0.isUnknown })?.count
        SnippetShell(title: trip.name, trailing: "\(trip.sightings.count) plates", isClosed: trip.isClosed) {
            if tally.isEmpty {
                Text("No plates yet").font(.title3.weight(.bold))
            } else {
                VStack(spacing: 8) {
                    ForEach(tally, id: \.name) { spotter in
                        HStack(spacing: 8) {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .opacity(!spotter.isUnknown && spotter.count == topCount ? 1 : 0)
                                .accessibilityHidden(true)
                            Text(spotter.name).font(.body.weight(.semibold)).lineLimit(1)
                                .opacity(spotter.isUnknown ? 0.7 : 1)
                            Spacer(minLength: 8)
                            Text("\(spotter.count)").font(.body.weight(.bold).monospacedDigit())
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Return the cards from the four read intents** in `Intents/TripIntents.swift`. Change each `perform()` return type to `some IntentResult & ProvidesDialog & ShowsSnippetView` and its return to pass `view:`:

```swift
// TripCountIntent
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.count(snapshot)),
                       view: CountCard(trip: snapshot))
// HaveWeSeenIntent
        let location = region.location
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.haveWeSeen(location, in: snapshot)),
                       view: SeenCard(location: location, trip: snapshot))
// PlatesLeftIntent
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.left(snapshot)),
                       view: PlatesLeftCard(trip: snapshot))
// TopSpotterIntent
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.topSpotter(snapshot)),
                       view: TopSpotterCard(trip: snapshot))
```

- [ ] **Step 3: Return the card from `MarkPlateIntent`.** Change the return type to `some IntentResult & ProvidesDialog & ShowsSnippetView` and the last line to:

```swift
        return .result(dialog: IntentDialog(stringLiteral: line),
                       view: MarkCard(location: location, trip: IntentTrips.snapshot(of: target)))
```

- [ ] **Step 4: Build gate.** Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/Intents
git commit -m "feat: show a trip card with each Siri answer"
```

---

### Task 6: "Ask Siri" what's-new card

**Outcome:** Existing users learn that the feature exists, plus one phrase that's sure to work, the first time they're on the trip list with at least one trip.

**Files:**
- Create: `Services/WhatsNew.swift`, `Views/WhatsNewSheet.swift`
- Modify: `Views/ContentView.swift`

**Interfaces:**
- Produces: `struct Announcement: Identifiable, Equatable` (`ID.siri`), `enum WhatsNew { static let all; static func next(seen:hasTrips:) -> Announcement? }`, `enum WhatsNewStore { static var seen: Set<String>; static func markSeen(_:) }`, `WhatsNewSheet(announcement:)`

- [ ] **Step 1: Create `Services/WhatsNew.swift`**

```swift
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
    // sure to match and says what that first question will be.
    static let all: [Announcement] = [
        Announcement(id: .siri, title: "Ask Siri", systemImage: "mic.fill", lines: [
            .init(text: "Log plates and check your trip without opening the app — handy from the passenger seat or on CarPlay."),
            .init(text: "Say \u{201C}We saw Maine in TripSpotter\u{201D}", isKey: true),
            .init(text: "Or ask \u{201C}How many states have we seen in TripSpotter?\u{201D} The first time, Siri asks to turn on TripSpotter's shortcuts. Say yes."),
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
```

- [ ] **Step 2: Create `Views/WhatsNewSheet.swift`**

```swift
import SwiftUI

/// A what's-new card as a medium-height sheet over the trip list. Closing it
/// any way (Got it, swipe down) marks it seen.
struct WhatsNewSheet: View {
    let announcement: Announcement
    @Environment(\.dismiss) private var dismiss

    private static let green = Color(red: 0.2, green: 0.65, blue: 0.35)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: announcement.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Self.green.gradient, in: .circle)
                        .accessibilityHidden(true)
                    Text("NEW")
                        .font(.caption2.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(Self.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Self.green.opacity(0.15), in: .capsule)
                        .accessibilityHidden(true)
                }
                Text(announcement.title)
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                ForEach(announcement.lines.indices, id: \.self) { index in
                    let line = announcement.lines[index]
                    Text(line.text)
                        .font(line.isKey ? .body.weight(.semibold) : .body)
                        .foregroundStyle(line.isKey ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                dismiss()
            } label: {
                Text("Got it")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.green)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            WhatsNewStore.markSeen(announcement.id)
        }
    }
}
```

- [ ] **Step 3: Present it from `ContentView`**

Add state next to the other `@State` properties:

```swift
    @State private var whatsNewCard: Announcement?
```

In `tripList`, replace the existing

```swift
        .onAppear {
            isPulsing = trips.isEmpty
        }
```

with

```swift
        .onAppear {
            isPulsing = trips.isEmpty
            presentWhatsNewIfDue()
        }
        .onChange(of: trips.isEmpty) { _, _ in
            presentWhatsNewIfDue()
        }
        .sheet(item: $whatsNewCard) { card in
            WhatsNewSheet(announcement: card)
        }
```

Add this method next to `confirmLeft(_:)`:

```swift
    /// Shows the next what's-new card when the trip list is on screen with nothing
    /// else over it; otherwise it waits for the list's next appearance.
    private func presentWhatsNewIfDue() {
        guard whatsNewCard == nil, navigationPath.isEmpty,
              !showingDeleteAlert, !showingLeaveAlert, leaveError == nil,
              persistenceController.shareAcceptanceError == nil else { return }
        whatsNewCard = WhatsNew.next(seen: WhatsNewStore.seen, hasTrips: !trips.isEmpty)
    }
```

- [ ] **Step 4: Build gate.** Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/Services/WhatsNew.swift myRoadTripTracker/myRoadTripTracker/Views/WhatsNewSheet.swift myRoadTripTracker/myRoadTripTracker/Views/ContentView.swift
git commit -m "feat: announce Siri with a one-time what's-new card"
```

---

### Task 7: Visual check, docs, PR (controller runs this, not a subagent)

**Outcome:** Proof that the cards and the sheet look right in light and dark mode, docs that match the code, and a PR ready for "merge".

- [ ] **Step 1: Throwaway render harness (never committed).** Add a temporary `#if DEBUG` branch in `myRoadTripTrackerApp.body`: when `ProcessInfo.processInfo.arguments.contains("-renderHarness")`, show a `ScrollView` holding all five cards built from fake `TripSnapshot`s. Use: zero sightings; 23 US + 4 Canada with three named spotters and one nil; one with a tie; a closed trip; and one with every plate seen. Above them, a `WhatsNewSheet(announcement: WhatsNew.all[0])` in a fixed-height frame.
- [ ] **Step 2: Render it.** Boot the iPhone 17 simulator (iOS 26.x), build for it, then `simctl install` and `simctl launch <udid> com.tentenbits.myRoadTripTracker -renderHarness`. Take a `simctl io screenshot` with `simctl ui <udid> appearance light`, then again with `dark`. Repeat with Dynamic Type at accessibility XL (`simctl ui <udid> content_size accessibility-extra-large`).
- [ ] **Step 3: Inspect every screenshot** for clipping, "…" truncation, overlapping text, unreadable contrast and missing flags. Fix the views and re-shoot as needed.
- [ ] **Step 4: Remove the harness.** Confirm `git status` shows no harness changes.
- [ ] **Step 5: Docs.** In `CLAUDE.md`, add `Intents/      App Intents: Siri/Spotlight intents, PlateRegion, TripEntity, cards` to the source-layout block, and add `IntentRoute, WhatsNew` to the `Services/` line. Commit: `docs: add Intents/ to the source layout`.
- [ ] **Step 6: Full build** (the gate command once more, from a clean tree).
- [ ] **Step 7: Push and open the PR** (`gh pr create`): why, what changed, how it was verified (build plus screenshots), and the device checklist below as unchecked items. Don't merge until Sam says "merge".

**Device checklist (TestFlight, needs Sam and a second iCloud device):**
- [ ] "We saw Maine in TripSpotter": Siri asks once to turn shortcuts on, then marks Maine.
- [ ] Every phrase in `TripSpotterShortcuts`, spoken once.
- [ ] "Washington" logs WA; "DC" logs DC; "PEI" logs PE.
- [ ] A voice mark on device A shows up on device B within about a minute.
- [ ] A voice mark with the phone locked works; "Open my trip" asks for unlock.
- [ ] Note whether a background voice mark got a GPS pin or `0,0`.
- [ ] The what's-new card shows once on the trip list, not again after "Got it".
- [ ] CarPlay, if available: one question and one mark.
