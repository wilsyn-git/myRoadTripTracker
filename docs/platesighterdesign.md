# Plate Sighter — Visual Redesign

**Date:** 2026-04-25
**Status:** Approved (design)
**Goal:** Replace the flat plate list with a tile-grid that makes spotting plates feel rewarding. The current list is functional but bland; tapping should produce a satisfying "collected!" reveal.

This document is the spec. A separate implementation plan lives alongside it.

---

## 1. Layout

- **Container:** `ScrollView` with `LazyVGrid` (3 columns, equal width, `spacing: 6`), replacing the current `List` host inside `PlatesTabView`.
- **Sections:** Two — "US States & DC" (51 locations) and "Canada" (13 locations). Same grouping as today.
- **Section header:** title (left) + `X/Y` count (right) on one row, with a thin (~3pt) gradient progress bar (`#F59E0B → #FBBF24`) below it that fills proportionally to `seenCount(in: locations) / locations.count`.
- **Toolbar:** unchanged. The existing "All / Not Seen" filter dropdown in `TripDetailView`'s toolbar continues to work as today.

## 2. The Tile

Each location gets one tile, sized via a `GridItem(.flexible(), spacing: 6)`, aspect ratio ~1:1.1.

| Element       | Spec                                                                |
|---------------|---------------------------------------------------------------------|
| Background    | `Color(.systemBackground)`, 8pt corner radius, hairline border `Color(.separator)` at `0.5pt` |
| Flag image    | 44 × 28 pt, `.cornerRadius(3)`, centered horizontally, top-padded ~10pt |
| State code    | Below the flag — `.system(.caption, design: .monospaced)`, `.bold()` |
| State name    | Below the code — `.caption2`, `Color(.secondaryLabel)`, single line, `.minimumScaleFactor(0.8)` |
| Padding       | `.padding(6)` overall                                               |

### Unseen state

- Flag: `.grayscale(1.0)` and tile opacity `0.45`.
- No checkmark.

### Seen state

- Flag at full color.
- Green check badge top-right: `Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)`, offset ~3pt from corners.
- Soft elevation: `.shadow(color: .black.opacity(0.06), radius: 1, y: 1)`.

### Recording-GPS state (transient)

While `LocationManager.requestCurrentLocation()` is in flight for *this* tile:

- A thin (2pt) blue (`Color.blue`) ring traces around the tile's rounded-rect outline using a `Trim` from 0 → 1 over ~0.8s, repeating.
- The flag itself stays greyscale until the location resolves; then the reveal animation starts.

Other tiles remain interactive — the user can queue more plates while one is resolving.

### Closed-trip state

When `trip.isClosed == true`:

- The entire scrolling grid wrapper gets `.opacity(0.55)` and `.disabled(true)`.
- A pill banner appears above the first section header: an `HStack` with `Image(systemName: "lock.fill")` + `Text("Trip closed — read only")`, padded, in a subtle muted-grey capsule.

## 3. Reveal animation (tap on unseen)

Sequence, all running on the same tile:

1. **Tap intent** — light haptic (`UIImpactFeedbackGenerator(style: .soft).impactOccurred()`), tile scale dips to 0.95 (~80ms).
2. **GPS fetch** — blue ring spinner described above.
3. **On resolved location**, run all of the following in parallel:
   - Flag desaturates: `.grayscale` animates 1.0 → 0.0 over 250ms.
   - Tile bounces: scale animates 0.95 → 1.15 → 1.10 → 1.0 over ~600ms via `.spring(response: 0.4, dampingFraction: 0.5)`.
   - Spark/confetti burst overlay (see below).
   - Success haptic (`UINotificationFeedbackGenerator().notificationOccurred(.success)`).
   - Green checkmark badge fades in (~150ms) at the end of the bounce.

**Spark/confetti burst** — a `ZStack` overlay sized ~140% of the tile, containing 8 small filled `Circle`s in alternating amber (`#F59E0B`) and gold (`#FBBF24`), positioned around the tile center at 8 evenly distributed angles. Each animates: `scale 0 → 1` and `offset 0 → ~24pt outward` over ~500ms with ease-out, opacity `0 → 1 → 0`. Implemented with `withAnimation(.easeOut(duration: 0.5))` and `Transition`/`@State` flags. No SpriteKit, no Lottie — pure SwiftUI.

The reveal also runs when GPS is **denied** — same animation, just with `(0,0)` as the stored coordinate. The user shouldn't be punished visually for declining permission.

## 4. Tap on a seen tile → detail sheet

A `.sheet(item: $sightingToInspect)` presented from `PlateSightingsGrid`. Medium detent (`.presentationDetents([.medium])`), drag-handle visible.

Sheet contents:

- **Header row:** large flag image (~80×52), state name (`.title3.bold()`), state code below in `.caption.monospaced()`.
- **Spotted line:** "Spotted *[relative date]*" using `Text(seenDate, style: .relative)`. If `seenDate` is `nil`, show "Spotted recently".
- **Location line:**
  - If `latitude == 0 && longitude == 0` → "No location recorded" in `.secondary` color. **View on map** button is hidden.
  - Otherwise → `String(format: "%.4f, %.4f", lat, lon)` in `.system(.body, design: .monospaced)`.
- **Buttons row** (`HStack`, equal-width):
  - **View on map** (filled, `.borderedProminent`) → presents `PlateSightingsMapView(sightings: [sighting])` so only this one pin appears, centered on it. Hidden when there's no location.
  - **Remove** (`.borderedProminent`, `.tint(.red)`) → confirmation alert ("Remove the *[State]* plate sighting? This deletes the location data.") with Cancel / Remove. On confirm: `viewContext.delete(sighting)` and dismiss the sheet.

If `trip.isClosed`, the **Remove** button is hidden (since the rest of the grid is also disabled in that state).

## 5. Long-press → context menu

In addition to tap behavior, `.contextMenu` on each tile provides:

- For **unseen** tiles: nothing (no menu) — tap is the only path.
- For **seen** tiles: `Button("Remove sighting", role: .destructive)` — bypasses the sheet for power users. Same delete logic.

## 6. Filter behavior

The toolbar dropdown's "All / Not Seen" filter (already in `TripDetailView`) is unchanged. When `.notSeen` is active, only unseen tiles are rendered in each section. Section headers' `X/Y` count and progress bar continue to reflect the *full* per-section progress (not the filtered view), so users can still see how close they are.

## 7. File / view changes

| File                                    | Change                                                                                |
|-----------------------------------------|---------------------------------------------------------------------------------------|
| `Views/PlateSightingsSection.swift`     | Rename to `PlateSightingsGrid.swift`. Internal `Section` + `ForEach` becomes a `LazyVGrid` host with two grouped sections drawn manually (header + grid + spacer). Drop the alert binding (replaced by sheet/detail flow). |
| `Views/PlateSightingsSection.swift` (`PlateRow`) | Rename `PlateRow` → `PlateTileView`. New layout (flag big, code+name stacked). Owns reveal animation and recording-state ring. Holds `@State` for animation flags. |
| `Views/PlateSightingsSection.swift` (new) | New view `PlateSightingDetailSheet` — header, spotted line, location line, View on map / Remove buttons. |
| `Views/TripDetailView.swift` (`PlatesTabView`) | Replace `List { PlateSightingsSection(...) }` with `PlateSightingsGrid(...)` directly. The grid manages its own `ScrollView`. |

No model or persistence changes. No `Location.swift` changes. No new permissions.

## 8. Section progress bar — implementation note

Use a simple `GeometryReader`-free `RoundedRectangle` with `.frame(maxWidth: .infinity, maxHeight: 3)` overlaid by a leading-aligned filled rectangle whose width is set via `.frame(width: containerWidth * progress)`. Or, more idiomatic SwiftUI: a `ProgressView(value:)` with a custom `ProgressViewStyle` that paints the gradient. Either is fine — pick whichever is cleaner.

## 9. Accessibility

- Each tile: `.accessibilityElement(children: .combine)`, label `"<state name>, <seen|not seen>"`, hint `"Double-tap to <mark as seen|view details>"`.
- The reveal animation respects `@Environment(\.accessibilityReduceMotion)` — when reduce-motion is on, skip the burst and the bounce; just crossfade greyscale → color and play the haptic.
- Confetti burst is `.accessibilityHidden(true)`.
- Closed-trip banner is in the accessibility tree.

## 10. Out of scope (v1)

- Reverse geocoding the coordinates to a place name in the detail sheet (e.g., "near Boulder"). v1 shows raw coords. Future enhancement.
- Per-region grouping (Northeast/Midwest/etc.).
- An "Activity" or "Recently spotted" section.
- Sound effects on reveal — deferred; haptic + visual is enough for v1.
- Empty state copy when 0 plates are seen — the all-greyscale grid is sufficient.
- Sync-status indicator on individual tiles — the existing trip-level mechanism (or lack thereof) is unchanged.

## 11. Privacy invariants honored

- One-shot GPS only; no continuous tracking. (Same as today.)
- No user attribution on `PlateSighting`. (Same.)
- GPS denied → `(0,0)` sentinel, plate still markable. (Same; per spec §10.3.)
- Detail sheet's "View on map" button reuses the existing `PlateSightingsMapView` and shows a single pin only — no lines or routes.
