# SwiftUI Review — Issues to Work Through (2026-06-04)

Findings from a `/swiftui-pro` review of the Views layer. Target is **iOS 18.1+**, so
every fix below stays within that range (no iOS 26-only APIs). No code has been changed yet.

Ordered by impact. Check items off as we go.

---

## Priority 1 — Per-keystroke Core Data save on trip name ✅ DONE
- [x] **File:** `Views/TripDetailView.swift` (lines 60–69)
- **Resolution:** Replaced `.onChange(of: trip.name)` per-keystroke save with a save on
  focus-loss (`.onChange(of: isNameFieldFocused)`), plus an `.onDisappear` safety-net save.
  Build verified (iPhone 17 sim). 16 saves-per-rename → 1; no more partial-name sync.
- **Problem:** `.onChange(of: trip.name) { viewContext.save(...) }` writes persistent
  history and schedules a CloudKit export on *every keystroke*. Coalesced uploads still
  mean history churn for collaborators on every letter.
- **Fix:** Save on focus-loss instead.
  ```swift
  .focused($isNameFieldFocused)
  .onChange(of: isNameFieldFocused) { _, focused in
      if !focused { viewContext.save(contextInfo: "tripNameChange") }
  }
  ```
- **Impact:** Only finding with a real collaborative-sync cost.

---

## Priority 2 — Empty SF Symbol name used as a checkmark hack ✅ DONE
- [x] **File:** `Views/TripDetailView.swift` (line 110)
- **Resolution:** Replaced the `ForEach`-of-`Button`s (with `systemImage: "checkmark" : ""`)
  with a `Picker` inside the `Menu` — native checkmarks, no empty-symbol warning. Also
  upgraded the menu trigger from a bare `Image` to a `Label("Filter Plates", …)` so VoiceOver
  has a spoken name. Build verified (iPhone 17 sim).
- **Problem:** `Label(filter.rawValue, systemImage: plateFilter == filter ? "checkmark" : "")`
  — an empty `systemImage` is undefined and logs an asset-not-found warning.
- **Fix:** Use a `Picker` inside the `Menu` for native checkmarks.
  ```swift
  Picker("Filter", selection: $plateFilter) {
      ForEach(PlateFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
  }
  ```

---

## Priority 3 — `.onTapGesture` on tappable images (VoiceOver) ✅ DONE
- [x] **File:** `Views/ObservationRow.swift` (line 30) — thumbnail → `Button` (`.borderless`)
  + `accessibilityLabel("View photo full screen")`. Tap target stays on the image.
- [x] **File:** `Views/PlateSightingsMapView.swift` (line 53) — annotation flag kept as a tap
  gesture (a `Button` fights the Map's gestures inside an `Annotation`) but added
  `.accessibilityAddTraits(.isButton)` so it's announced as actionable.
- [x] **File:** `Views/PlateSightingsMapView.swift` (line 64) — map-background deselect tap
  **intentionally left** as a gesture (not a navigable control); added a comment. Dismiss
  path for VoiceOver is the detail card itself.
- **Build verified (iPhone 17 sim).**
- **Problem:** Tappable elements that don't need tap location/count should be `Button`s,
  or VoiceOver won't announce them as actionable.
- **Fix (ObservationRow):**
  ```swift
  Button { showingFullImage = true } label: {
      Image(uiImage: uiImage).resizable()...
  }
  .buttonStyle(.plain)
  .accessibilityLabel("View photo full screen")
  ```
- **Note:** Map annotations already have `accessibilityLabel`/`accessibilityHint`, so they're
  partially covered — lower priority than the map recompute below.

---

## Priority 4 — `mappableSightings` recomputed twice & expensive ✅ DONE
- [x] **File:** `Views/PlateSightingsMapView.swift` (lines 13–35)
- **Resolution:** Converted the computed property to a stored `let` computed once in a custom
  `init` (via `static computeMappable(from:)`). `sightings` is immutable for the view's
  lifetime, so `@State`-driven `body` passes (pin taps) no longer recompute it. Extracted a
  named `MappableSighting: Identifiable` struct, which also let the `ForEach` drop its
  `id: \.sighting.objectID`. Build verified (iPhone 17 sim).
- **Problem:** Sorts + filters + neighbor-interpolates (nested scan over `validCoords`), and
  `mapContent` accesses it twice (ForEach line 40, lookup line 71) — runs ≥2× per `body` pass.
- **Fix:** Compute once into a `let`/`@State` when the view appears; sightings are fixed for
  the view's lifetime.

---

## Priority 5 — O(n²) lookups and repeated filtering ✅ DONE
- [x] **File:** `Views/PlateSightingsGrid.swift`
  - `body` now builds `seenCodes = Set(sightings.map(\.locationCode))` once per render and
    threads it through `sectionView` / `sectionHeader` / `filtered`; per-tile checks are now
    O(1). Removed the now-unused `seenCount(in:)`. Tap-path scans (`sighting(for:)`,
    `isSeen` in `markAsSeen`) left as-is — they run on tap, not render.
- [x] **File:** `Views/ObservationsSection.swift`
  - `body` groups entries once via `Dictionary(grouping:by: \.category)`; sections look up by
    key. `allCategories` → `categories(from:)` taking the already-fetched entries; removed
    `entriesForCategory`. Order preserved (grouping keeps source order).
- **Build verified (iPhone 17 sim).**

---

## Priority 6 — Modernization / data-flow polish ✅ DONE (2 fixed, 3 deliberately left)
- [x] **Item 1 — `Views/PlateSightingsGrid.swift`:** Replaced `DispatchQueue.main.asyncAfter`
  in `playRevealAnimation()` with `Task { @MainActor in try? await Task.sleep(...) }`.
  Behavior identical; aligns with the codebase's structured-concurrency style.
- [x] **Item 2a — `Views/ContentView.swift` delete alert:** Switched from `Binding(get:set:)`
  to a discrete `@State showingDeleteAlert` bool + `.alert(_:isPresented:presenting:)`.
  Removed the manual binding; trip passes through non-optional.
- [ ] **Item 2b — `Views/ContentView.swift` share-error alert: LEFT (intentional).**
  Source of truth is `persistenceController.shareAcceptanceError` (external optional). A
  bool-bridge would need an extra `@State` + `.onChange` to sync — *more* code, not less.
  `Binding(get:set:)` is the right tool for bridging external optional state here.
- [ ] **Item 3 — `Views/ObservationRow.swift` image decode: DEFERRED (intentional).**
  `UIImage(data:)` re-decodes thumbnails in `body`. Proper fix (decode in `.task(id:)` →
  `@State`) adds complexity + a one-frame empty flash, for small already-shrunk thumbnails.
  Revisit only if the notes list shows scroll hitching.
- [ ] **Item 4 — `Views/TripCardView.swift` UserDefaults in body: LEFT (intentional).**
  Key is dynamic (`lastViewedObservations_<tripID>`), so `@AppStorage` (static-key only)
  can't apply. Read is cheap and correct; card re-renders on return from notes. A reactive
  fix (per-trip observable store) is disproportionate for a notification dot.
- **Build verified (iPhone 17 sim).**

---

## Priority 7 — File / type organization (one type per file) ✅ DONE (1 deferred)
Done on branch `swiftui-pro-cleanup`. Pure cut/paste moves — no behavior change. New files
auto-discovered via `PBXFileSystemSynchronizedRootGroup` (project.pbxproj untouched).
- [x] `DualProgressRingView.swift` ← TripCardView
- [x] `PlateTileView.swift`, `ConfettiBurstView.swift`, `PlateSightingDetailSheet.swift` ← PlateSightingsGrid
- [x] `ComposeEntryRow.swift`, `CameraPicker.swift` ← ObservationsSection
- [x] `SightingDetailCard.swift` ← PlateSightingsMapView
- [x] `FullImageView.swift` ← ObservationRow
- [x] `PlatesTabView` deleted; `TripDetailView` calls `PlateSightingsGrid` directly
- [ ] **`sectionView`/`sectionHeader` → `PlateSectionView` struct: DEFERRED (intentional).**
      Not a pure move — it's a state-threading refactor (trip, filter, recording/revealing
      sets, callbacks) that the build can't fully vet the way it does a cut/paste. Skipped to
      avoid re-churning PlateSightingsGrid right after P5.
- **Left co-located:** `MappableSighting` (tiny model in PlateSightingsMapView.swift) and
  `CloudSharingView.swift` (CloudKit/UIKit-bridge grouping). Build verified (iPhone 17 sim).

---

### Notes
- `@Observable` services (`LocationManager`, `PersistenceController`) are correctly
  `@MainActor`-annotated — no action needed.
- Confetti burst is already gated behind the non-`reduceMotion` branch — good as-is.
