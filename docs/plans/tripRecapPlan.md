# Trip Recap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shareable end-of-trip Recap card — deterministic stats + pin map + optional on-device AI narrative — generated when an owner closes a trip, synced to all participants, viewable anytime, and exportable as an image.

**Architecture:** Two additive optional attributes on the existing `Trip` entity store the synced narrative. Stats and the map are recomputed live from already-synced Core Data; the on-device Foundation Models LLM only writes prose over numbers it is handed (with a deterministic template fallback). Delivery to other participants is an in-app "recap ready" badge on the trip tile (no notification permission). Outward sharing is a rendered image via the system share sheet.

**Tech Stack:** Swift, SwiftUI, Core Data + `NSPersistentCloudKitContainer`, MapKit (`MKMapSnapshotter`), Foundation Models (`import FoundationModels`, iOS 26+), `ImageRenderer`, `ShareLink`.

---

## Project-specific ground rules (read before starting)

- **No test target exists.** Do NOT write XCTest files or run `xcodebuild test`. Verification for every task is: compile with the build command below, plus the manual checks noted per task.
- **Do not edit `project.pbxproj`.** New `.swift` files in the source dir are auto-discovered (`PBXFileSystemSynchronizedRootGroup`). Just create files in `myRoadTripTracker/myRoadTripTracker/`.
- **CloudKit attributes must be `optional="YES"` in the model AND `Optional` in Swift.** `Date`/`UUID` cannot carry compile-time defaults in the XML.
- **`Date` and `Math.random` cautions do not apply** — this is app Swift code; `Date()` and `Calendar` are fine here.
- After model changes, **the CloudKit schema must be deployed to production** before a TestFlight build will sync the new fields (final task covers this as a manual checklist item).

### Build command (the verification command referenced throughout)

```bash
xcodebuild -project myRoadTripTracker/myRoadTripTracker.xcodeproj \
           -scheme myRoadTripTracker \
           -destination 'platform=iOS Simulator,name=iPhone 16' \
           build
```
Expected on success: `** BUILD SUCCEEDED **`.

---

## File structure

| File | Responsibility | Action |
|---|---|---|
| `Resources/myRoadTripTracker.xcdatamodeld/myRoadTripTracker.xcdatamodel/contents` | Add `recapNarrative`, `recapGeneratedDate` to `Trip` | Modify |
| `Models/Trip+CoreDataProperties.swift` | Expose the two new `@NSManaged` properties | Modify |
| `Services/RecapStats.swift` | Pure computation of all recap numbers from a `Trip` + template narrative | Create |
| `Services/RecapNarrativeGenerator.swift` | Foundation Models wrapper with availability gating | Create |
| `Services/RecapMapRenderer.swift` | `MKMapSnapshotter` → pin image | Create |
| `Views/TripRecapView.swift` | The recap card UI, share button, "mark viewed" | Create |
| `Views/TripDetailView.swift` | Recap toolbar button + generate-on-close hook | Modify |
| `Views/TripCardView.swift` | "Recap ready" in-app badge | Modify |

---

## Task 1: Data model — add recap attributes to `Trip`

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/Resources/myRoadTripTracker.xcdatamodeld/myRoadTripTracker.xcdatamodel/contents`
- Modify: `myRoadTripTracker/myRoadTripTracker/Models/Trip+CoreDataProperties.swift`

- [ ] **Step 1: Add the two attributes to the `Trip` entity in the model XML**

In `contents`, the `Trip` entity currently ends its attribute list with `isClosed`. Add the two new optional attributes immediately after the `isClosed` line (before the `<relationship ...>` lines):

```xml
        <attribute name="isClosed" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
        <attribute name="recapNarrative" optional="YES" attributeType="String"/>
        <attribute name="recapGeneratedDate" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
```

- [ ] **Step 2: Add matching `@NSManaged` properties in Swift**

In `Trip+CoreDataProperties.swift`, add the two properties to the first `extension Trip` block, after the `isClosed` line:

```swift
    @NSManaged public var tripID: UUID?
    @NSManaged public var name: String
    @NSManaged public var createdDate: Date?
    @NSManaged public var isClosed: Bool
    @NSManaged public var recapNarrative: String?
    @NSManaged public var recapGeneratedDate: Date?
    @NSManaged public var plateSightings: NSSet?
    @NSManaged public var observationEntries: NSSet?
    @NSManaged public var participants: NSSet?
```

- [ ] **Step 3: Build to verify the model + property compile**

Run the build command. Expected: `** BUILD SUCCEEDED **`. (A mismatch between the XML attribute name and the Swift property name surfaces here or at runtime; double-check both are exactly `recapNarrative` / `recapGeneratedDate`.)

- [ ] **Step 4: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/Resources/myRoadTripTracker.xcdatamodeld \
        myRoadTripTracker/myRoadTripTracker/Models/Trip+CoreDataProperties.swift
git commit -m "feat(recap): add recapNarrative/recapGeneratedDate to Trip"
```

---

## Task 2: `RecapStats` — deterministic stat computation

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/Services/RecapStats.swift`

- [ ] **Step 1: Create `RecapStats.swift` with the full implementation**

```swift
import Foundation

/// One participant's plate count, for the recap leaderboard.
struct SpotterTally: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

/// All numbers the recap card needs, computed deterministically from a Trip.
/// Performs no Core Data writes.
struct RecapStats {
    let usSeenCount: Int
    let usTotalCount: Int
    let caSeenCount: Int
    let caTotalCount: Int
    let totalSightings: Int
    let dayCount: Int                 // inclusive days from first to last sighting; 0 if none
    let spotterTallies: [SpotterTally] // sorted by count desc, then name
    let rareCatches: [String]          // location NAMES of rare regions caught
    let observationCount: Int
    let observationsWithPhoto: Int

    /// Region codes considered "rare" (remote / low-population).
    static let rareCodes: Set<String> = ["AK", "HI", "NL", "PE", "NT", "NU", "YT"]

    var mvp: SpotterTally? { spotterTallies.first }

    /// True when there is genuinely nothing to recap.
    var isEmpty: Bool { totalSightings == 0 && observationCount == 0 }

    init(trip: Trip) {
        let sightings = trip.plateSightingsArray
        let observations = trip.observationEntriesArray

        let usCodes = Set(Location.usStates.map(\.code))
        let caCodes = Set(Location.canadaLocations.map(\.code))

        usTotalCount = usCodes.count
        caTotalCount = caCodes.count
        usSeenCount = sightings.filter { usCodes.contains($0.locationCode) }.count
        caSeenCount = sightings.filter { caCodes.contains($0.locationCode) }.count
        totalSightings = sightings.count

        // Day span (inclusive). plateSightingsArray is sorted ascending by seenDate.
        let dates = sightings.compactMap(\.seenDate)
        if let first = dates.first, let last = dates.last {
            let cal = Calendar.current
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: first), to: cal.startOfDay(for: last)).day ?? 0
            dayCount = days + 1
        } else {
            dayCount = 0
        }

        // Per-spotter tallies.
        var counts: [String: Int] = [:]
        for s in sightings {
            let name = s.spottedByName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            counts[name, default: 0] += 1
        }
        spotterTallies = counts
            .map { SpotterTally(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }

        // Rare catches (unique region names, ordered by the canonical list).
        let seenRareCodes = Set(sightings.map(\.locationCode)).intersection(Self.rareCodes)
        rareCatches = Location.allLocations
            .filter { seenRareCodes.contains($0.code) }
            .map(\.name)

        observationCount = observations.count
        observationsWithPhoto = observations.filter { $0.imageData != nil || $0.thumbnailData != nil }.count
    }

    /// Deterministic fallback blurb used when the AI model is unavailable.
    func templateNarrative(tripName: String) -> String {
        var parts: [String] = []
        let regions = usSeenCount + caSeenCount
        if dayCount > 0 {
            parts.append("\(regions) plate\(regions == 1 ? "" : "s") spotted over \(dayCount) day\(dayCount == 1 ? "" : "s").")
        } else if regions > 0 {
            parts.append("\(regions) plate\(regions == 1 ? "" : "s") spotted.")
        }
        if let mvp {
            parts.append("\(mvp.name) led the way with \(mvp.count).")
        }
        if !rareCatches.isEmpty {
            parts.append("Rare finds: \(rareCatches.joined(separator: ", ")).")
        }
        if parts.isEmpty {
            return "Your \(tripName) recap."
        }
        return parts.joined(separator: " ")
    }

    /// Compact description handed to the language model as prompt input.
    func promptDescription(tripName: String) -> String {
        var lines: [String] = []
        lines.append("Trip name: \(tripName)")
        lines.append("US states spotted: \(usSeenCount) of \(usTotalCount)")
        lines.append("Canadian provinces/territories spotted: \(caSeenCount) of \(caTotalCount)")
        lines.append("Total plates: \(totalSightings)")
        if dayCount > 0 { lines.append("Trip length: \(dayCount) days") }
        if let mvp { lines.append("Top spotter: \(mvp.name) with \(mvp.count) plates") }
        if !rareCatches.isEmpty { lines.append("Rare catches: \(rareCatches.joined(separator: ", "))") }
        lines.append("Observations recorded: \(observationCount) (\(observationsWithPhoto) with photos)")
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/Services/RecapStats.swift
git commit -m "feat(recap): add RecapStats deterministic computation + template narrative"
```

---

## Task 3: `RecapNarrativeGenerator` — on-device AI narrative

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/Services/RecapNarrativeGenerator.swift`

- [ ] **Step 1: Create `RecapNarrativeGenerator.swift`**

```swift
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Generates a short recap blurb on-device via Foundation Models.
/// Returns nil when the model is unavailable (caller falls back to RecapStats.templateNarrative).
enum RecapNarrativeGenerator {

    static func generate(from stats: RecapStats, tripName: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return nil }

            let instructions = """
            You write a short, warm, upbeat recap of a family road-trip license-plate \
            spotting game. Use ONLY the facts provided — never invent numbers or places. \
            Keep it to 2-3 sentences. No hashtags, no emoji.
            """
            let session = LanguageModelSession(instructions: instructions)
            let prompt = "Write the recap from these facts:\n\(stats.promptDescription(tripName: tripName))"
            do {
                let response = try await session.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build command. Expected: `** BUILD SUCCEEDED **`. (Compiles against the iOS 26 SDK; the `#available` guard keeps it safe on the 18.1 deployment target.)

- [ ] **Step 3: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/Services/RecapNarrativeGenerator.swift
git commit -m "feat(recap): add on-device Foundation Models narrative generator"
```

---

## Task 4: `RecapMapRenderer` — pin snapshot image

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/Services/RecapMapRenderer.swift`

- [ ] **Step 1: Create `RecapMapRenderer.swift`**

```swift
import MapKit
import UIKit
import CoreLocation

/// Renders a static map image with pins for a trip's sightings. Pins only — no routes.
enum RecapMapRenderer {

    static func snapshot(for sightings: [PlateSighting], size: CGSize) async -> UIImage? {
        let coords = sightings.filter(\.hasValidCoordinate).map(\.coordinate)
        guard !coords.isEmpty else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = region(for: coords)
        options.size = size
        options.mapType = .standard

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await snapshotter.start()
            return draw(coords: coords, on: snapshot, size: size)
        } catch {
            return nil
        }
    }

    private static func region(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        var minLat = coords[0].latitude, maxLat = coords[0].latitude
        var minLon = coords[0].longitude, maxLon = coords[0].longitude
        for c in coords {
            minLat = min(minLat, c.latitude);  maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        // 1.6x padding, with sane minimums so a single point isn't fully zoomed in.
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.6, 2.0),
                                    longitudeDelta: max((maxLon - minLon) * 1.6, 2.0))
        return MKCoordinateRegion(center: center, span: span)
    }

    private static func draw(coords: [CLLocationCoordinate2D],
                             on snapshot: MKMapSnapshotter.Snapshot,
                             size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            snapshot.image.draw(at: .zero)
            let cg = ctx.cgContext
            let pinRadius: CGFloat = 5
            for coord in coords {
                let point = snapshot.point(for: coord)
                guard point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else { continue }
                let rect = CGRect(x: point.x - pinRadius, y: point.y - pinRadius,
                                  width: pinRadius * 2, height: pinRadius * 2)
                cg.setFillColor(UIColor.systemRed.cgColor)
                cg.fillEllipse(in: rect)
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(1.5)
                cg.strokeEllipse(in: rect)
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/Services/RecapMapRenderer.swift
git commit -m "feat(recap): add MKMapSnapshotter-based pin map renderer"
```

---

## Task 5: `TripRecapView` — the card UI + share + mark-viewed

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/Views/TripRecapView.swift`

- [ ] **Step 1: Create `TripRecapView.swift`**

`RecapCardContent` is factored out so the exact same visual is used both on screen and for the shared image (no recursive rendering). `TripRecapView` owns the sheet chrome, async map load, share image rendering, and the per-trip "last viewed recap" timestamp.

```swift
import SwiftUI
import CoreData

/// The visual recap card. Pure layout over precomputed inputs so it can be both
/// displayed and rasterized for sharing.
struct RecapCardContent: View {
    let tripName: String
    let stats: RecapStats
    let narrative: String
    let mapImage: UIImage?

    private var cardColor: Color { Color(red: 0.2, green: 0.65, blue: 0.35) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tripName)
                .font(.largeTitle).fontWeight(.bold)

            Text(narrative)
                .font(.body)

            if let mapImage {
                Image(uiImage: mapImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 12))
            }

            HStack(spacing: 24) {
                statBlock(value: "\(stats.usSeenCount)/\(stats.usTotalCount)", label: "US")
                statBlock(value: "\(stats.caSeenCount)/\(stats.caTotalCount)", label: "Canada")
                if stats.dayCount > 0 {
                    statBlock(value: "\(stats.dayCount)", label: stats.dayCount == 1 ? "Day" : "Days")
                }
            }

            if let mvp = stats.mvp {
                Label("MVP: \(mvp.name) (\(mvp.count))", systemImage: "trophy.fill")
                    .font(.headline)
            }
            if !stats.rareCatches.isEmpty {
                Label("Rare: \(stats.rareCatches.joined(separator: ", "))", systemImage: "star.fill")
                    .font(.subheadline)
            }
            if stats.observationCount > 0 {
                Label("\(stats.observationCount) note\(stats.observationCount == 1 ? "" : "s"), \(stats.observationsWithPhoto) with photos",
                      systemImage: "text.bubble.fill")
                    .font(.subheadline)
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardColor.gradient, in: RoundedRectangle(cornerRadius: 20))
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2).fontWeight(.bold)
            Text(label).font(.caption).opacity(0.85)
        }
    }
}

struct TripRecapView: View {
    @ObservedObject var trip: Trip
    @Environment(\.dismiss) private var dismiss

    @State private var stats: RecapStats?
    @State private var narrative: String = ""
    @State private var mapImage: UIImage?
    @State private var shareImage: Image?

    var body: some View {
        NavigationStack {
            Group {
                if let stats, !stats.isEmpty {
                    ScrollView {
                        RecapCardContent(tripName: trip.name, stats: stats,
                                         narrative: narrative, mapImage: mapImage)
                            .padding()
                    }
                } else {
                    ContentUnavailableView {
                        Label("Nothing to Recap Yet", systemImage: "sparkles")
                    } description: {
                        Text("Spot some plates or add notes, and your trip recap will appear here.")
                    }
                }
            }
            .navigationTitle("Trip Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let shareImage {
                        ShareLink(item: shareImage,
                                  preview: SharePreview("Trip Recap", image: shareImage)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task { await load() }
        }
    }

    @MainActor
    private func load() async {
        markRecapViewed()
        let computed = RecapStats(trip: trip)
        stats = computed
        guard !computed.isEmpty else { return }

        narrative = trip.recapNarrative ?? computed.templateNarrative(tripName: trip.name)

        let snapshot = await RecapMapRenderer.snapshot(
            for: trip.plateSightingsArray,
            size: CGSize(width: 600, height: 360)
        )
        mapImage = snapshot
        renderShareImage(stats: computed)
    }

    @MainActor
    private func renderShareImage(stats: RecapStats) {
        let card = RecapCardContent(tripName: trip.name, stats: stats,
                                    narrative: narrative, mapImage: mapImage)
            .frame(width: 360)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let ui = renderer.uiImage {
            shareImage = Image(uiImage: ui)
        }
    }

    private func markRecapViewed() {
        guard let tripID = trip.tripID?.uuidString else { return }
        UserDefaults.standard.set(Date(), forKey: "lastViewedRecap_\(tripID)")
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/Views/TripRecapView.swift
git commit -m "feat(recap): add TripRecapView card with map, stats, and share"
```

---

## Task 6: Wire Recap into `TripDetailView` — button + generate-on-close

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/TripDetailView.swift`

- [ ] **Step 1: Add the `showingRecap` state flag**

In `TripDetailView`, alongside the other `@State` flags (e.g. near `@State private var showingMapView = false`), add:

```swift
    @State private var showingRecap = false
```

- [ ] **Step 2: Add a Recap toolbar button**

In the `.toolbar { ... }` of `tripContent`, add a new `ToolbarItem` after the existing "View Sightings Map" item (the one whose label is "View Sightings Map"), before the close/reopen item:

```swift
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingRecap = true
                } label: {
                    Label("Trip Recap", systemImage: "sparkles")
                }
            }
```

- [ ] **Step 3: Present the recap sheet**

Add a `.sheet` after the existing `.sheet(isPresented: $showingMapView) { ... }` modifier on `tripContent`:

```swift
        .sheet(isPresented: $showingRecap) {
            TripRecapView(trip: trip)
        }
```

- [ ] **Step 4: Generate the recap when the owner closes the trip**

Replace the existing close/reopen button action. The current code is:

```swift
                Button {
                    trip.isClosed.toggle()
                    viewContext.save(contextInfo: "toggleClosed")
                } label: {
```

Change it to capture the prior state and trigger generation on the open→closed transition:

```swift
                Button {
                    let wasClosed = trip.isClosed
                    trip.isClosed.toggle()
                    viewContext.save(contextInfo: "toggleClosed")
                    if !wasClosed {
                        Task { await generateRecap() }
                    }
                } label: {
```

- [ ] **Step 5: Add the `generateRecap()` method**

Add this method inside `struct TripDetailView` (e.g. right after the `tripContent` computed property, before the closing brace of the struct):

```swift
    private func generateRecap() async {
        let stats = RecapStats(trip: trip)
        guard !stats.isEmpty else { return }
        let narrative = await RecapNarrativeGenerator.generate(from: stats, tripName: trip.name)
        await MainActor.run {
            if let narrative { trip.recapNarrative = narrative }
            trip.recapGeneratedDate = Date()
            viewContext.save(contextInfo: "generateRecap")
        }
    }
```

- [ ] **Step 6: Build to verify it compiles**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/Views/TripDetailView.swift
git commit -m "feat(recap): add Recap button and generate-on-close to TripDetailView"
```

---

## Task 7: "Recap ready" badge on `TripCardView`

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/Views/TripCardView.swift`

- [ ] **Step 1: Add a computed flag for an unseen recap**

In `TripCardView`, add after the `newObservationCount` computed property (around line 34):

```swift
    private var hasUnseenRecap: Bool {
        guard let generated = trip.recapGeneratedDate else { return false }
        guard let tripID = trip.tripID?.uuidString else { return true }
        let key = "lastViewedRecap_\(tripID)"
        guard let lastViewed = UserDefaults.standard.object(forKey: key) as? Date else {
            return true
        }
        return generated > lastViewed
    }
```

- [ ] **Step 2: Render the badge in the header row**

In the header `HStack(spacing: 6)`, add a recap indicator immediately after the observation-count block and before the `if isShared {` block:

```swift
                    if hasUnseenRecap {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("New recap available")
                    }
```

- [ ] **Step 3: Build to verify it compiles**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add myRoadTripTracker/myRoadTripTracker/Views/TripCardView.swift
git commit -m "feat(recap): show sparkles badge on tiles with an unseen recap"
```

---

## Task 8: Manual verification + CloudKit production deploy

No code in this task — it is the end-to-end check the build alone cannot cover.

- [ ] **Step 1: Full build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Simulator run (template path)**

Run on the iPhone 16 simulator with iCloud signed in:
- Create a trip, mark several plates (include a rare one like Alaska/Hawaii), add a couple of notes (one with a photo).
- Tap the **Trip Recap** (`sparkles`) toolbar button → card shows stats, MVP, rare catches, observation counts, and a pin map. Narrative is the template sentence (simulator has no Foundation Models).
- Tap **Share** → system share sheet appears with the rendered card image.
- Close the trip → return to the trip list → confirm the **sparkles badge** appears on the tile, and disappears after opening the recap again.
- Empty-trip check: a brand-new trip's recap shows the "Nothing to Recap Yet" state.

- [ ] **Step 3: Device run (AI path)** — requires an Apple-Intelligence-capable device (iPhone 15 Pro+), Apple Intelligence enabled and model downloaded.
- Close a populated trip and open the recap → narrative is a model-written 2-3 sentence blurb (not the template). Verify the numbers in the prose match the stat blocks.

- [ ] **Step 4: CloudKit production schema deploy**
- In the CloudKit Dashboard for `iCloud.com.tentenbits.myRoadTripTracker`, deploy the schema (now including the `recapNarrative` / `recapGeneratedDate` fields on the `CD_Trip` record type) from Development to **Production**. Without this, TestFlight/App Store builds will not sync the new fields.

- [ ] **Step 5: Two-account sync check** (real devices, two iCloud accounts)
- Owner closes a populated trip (recap generated). On the recipient's device that has accepted the share, confirm the same narrative text appears and the recap badge shows. This verifies `recapNarrative` syncs through the shared store.

- [ ] **Step 6: Final commit (if any doc updates)**

If `CLAUDE.md` / `ARCHITECTURE.md` need a note about the recap feature, update and commit:

```bash
git add -A
git commit -m "docs(recap): note Trip Recap feature and CloudKit field deploy"
```

---

## Self-review notes (author check — already applied)

- **Spec coverage:** data-model change (Task 1), `RecapStats`/narrative/map components (Tasks 2-4), `TripRecapView` (Task 5), generate-on-close + anytime view (Task 6), Path A in-app badge (Task 7), Path B share sheet (Task 5 share button), error/empty handling (empty state in Task 5, nil-guards in Tasks 3-4), verification + production deploy (Task 8). All spec sections map to a task.
- **Type consistency:** `RecapStats`, `SpotterTally`, `RecapStats.templateNarrative(tripName:)`, `RecapStats.promptDescription(tripName:)`, `RecapNarrativeGenerator.generate(from:tripName:)`, `RecapMapRenderer.snapshot(for:size:)`, `RecapCardContent`, and the `lastViewedRecap_<tripID>` UserDefaults key are referenced consistently across tasks.
- **No placeholders:** every code step contains complete, copy-ready code.
```
