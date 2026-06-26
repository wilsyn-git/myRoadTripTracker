# Performance Pass (findings 1.1, 1.3, 1.4) — Design Spec

**Date:** 2026-06-26
**Source:** `docs/agy_general.md` Section 1 (performance). Findings 1.1, 1.3, 1.4. Finding **1.2 is intentionally dropped** — `UserDefaults.standard` reads are memory-cached, not the blocking I/O the review claimed; the only real cost in those properties is the `.sorted()`, which 1.1 already removes.

## Goal

Three independent, low-risk performance improvements. The headline is **1.3** — the recap map currently breaks offline, which is a real road-trip UX bug, not a micro-optimization. 1.1 and 1.4 are cheap, clearly-correct cleanups.

## Scope

**In:** 1.1 (TripCardView compute-once), 1.3 (recap-map disk cache + offline), 1.4 (async thumbnail decode). Three independent tasks.
**Out:** 1.2 (dropped, see above). Any CloudKit/schema change. Any `project.pbxproj` edit. Section 3.x (accessibility) — later tier.

---

## 1. `TripCardView` — compute derived values once per render (finding 1.1)

### Problem
`TripCardView.swift` exposes derived values as computed properties — `sightings` (`:7` → `trip.plateSightingsArray`), `usSeenCount` (`:10`), `caSeenCount` (`:17`), `observations` (`:25`), `newObservationCount` (`:27`), `recentSightings` (`:46`), and `participantsArray` reads (`:23`, `:99`, `:103`, `:148`). Each access re-materializes and **re-sorts** a Core Data set. `body` touches these ~8 times per card, so a list of cards repeats the sort work many times on the main thread.

### Design
Introduce a single value, `cardData`, computed **once** at the top of `body` (bound to a `let`), carrying every derived value the card needs:

- US count, CA count, total observation count, new observation count, participant count, and `recentSightings`.
- Counts read the underlying **sets directly without sorting** (`trip.plateSightings as? Set`, etc.) — ordering is irrelevant for a count or a filter.
- `recentSightings` is the **only** value that sorts (by `seenDate`, once) — it needs the newest five.
- `body` and the `.accessibilityLabel` reference `cardData.*` instead of the old computed properties.

Net: from ~8 set-sorts per card render to a single sort (only for the recent flags). The static `usCodes`/`caCodes` sets and the `lastViewedObservations_<id>` UserDefaults read are preserved as-is (the read is cheap; it's the sort that mattered). Behavior is identical.

**Files:** `Views/TripCardView.swift` (self-contained refactor).

---

## 2. Recap map disk cache + offline (finding 1.3) — headline

### Problem
`TripRecapView.load()` (`:135`) calls `RecapMapRenderer.snapshot(...)` on every recap open. `MKMapSnapshotter` fetches map tiles over the network, so each open costs data/battery and **fails entirely when offline** — common on remote road-trip segments.

### Design
Add a small `RecapMapCache` helper (new file — auto-discovered, no `project.pbxproj` edit) backed by the **Caches directory** (`FileManager.default.urls(for: .cachesDirectory, ...)`, subfolder `RecapMaps`):

- `image(for key: String) -> UIImage?` — load a cached PNG from disk.
- `store(_ image: UIImage, for key: String)` — write the PNG.
- **Key:** a *stable* `SHA256` hex (CryptoKit) of a content string built from the coordinate list (each lat/lon formatted to fixed precision, e.g. `%.5f`) plus the render size → filename `recapMap-<hex>.png`. Swift's built-in `Hasher` is seeded per-process and must **not** be used for a persistent filename.

Make `RecapMapRenderer.snapshot(for:size:)` **cache-aware**:
1. Compute the key from `coordinates` + `size`.
2. If `RecapMapCache.image(for: key)` exists, return it.
3. Otherwise render via `MKMapSnapshotter` as today, `RecapMapCache.store(...)` the result, return it.

`TripRecapView` is unchanged. The function is already a nonisolated `async` called via `await` from the `@MainActor load()`, so disk I/O runs off the main actor.

### Behavior
- Second and later opens are instant and **work offline**.
- Cache auto-invalidates on data change: new/removed sightings → different coordinate set → different hash → re-render (network needed only then, which is expected).
- **Eviction:** left to the OS (the Caches directory is purgeable under storage pressure); stale-hash entries are small PNGs. No custom pruner (YAGNI) — noted, not built.

**Files:** `Services/RecapMapCache.swift` (new), `Services/RecapMapRenderer.swift` (make `snapshot` cache-aware).

---

## 3. Async thumbnail decode in `ObservationRow` (finding 1.4)

### Problem
`ObservationEntryRow` decodes its thumbnail synchronously in `body`: `UIImage(data: thumbnailData)` (`ObservationRow.swift:24`). `UIImage(data:)` defers the bitmap decode to first display, so the decode lands on the main thread during scroll, causing hitching as the notes feed grows.

### Design
- Add `@State private var thumbnail: UIImage?`.
- Populate it with `.task(id: entry.thumbnailData)`: if `thumbnailData` is nil, clear `thumbnail`; otherwise decode **off the main thread** via a detached task that runs `UIImage(data:)?.preparingForDisplay()` (forces the bitmap decode + prep off-main), then assign the result back on the main actor.
- `body` shows `Image(uiImage: thumbnail)` when present; while decoding (or when only `imageData` exists without a thumbnail), show the existing placeholder (`photo.on.rectangle.angled`). The full-screen tap behavior and `imageData`/`onDeleteImage` paths are unchanged.

**Files:** `Views/ObservationRow.swift` (self-contained).

---

## Verification

No unit/UI test targets exist, so:

1. **Compile check** (all three):
   ```bash
   xcodebuild -project myRoadTripTracker/myRoadTripTracker.xcodeproj \
              -scheme myRoadTripTracker \
              -destination 'platform=iOS Simulator,name=iPhone 17' build
   ```
   (`iPhone 16` is not installed; use `iPhone 17`.) Expected: `** BUILD SUCCEEDED **`.
2. **1.3 — the one meaningfully hand-checkable item:** open a trip recap (renders + caches the map), enable Airplane Mode, reopen the recap → the map still displays. Add a new sighting → the map re-renders (cache miss on the new coordinate set).
3. **1.1 / 1.4:** code review + scroll-feel sanity check; no deterministic test harness.

## Out of scope (tracked elsewhere)

- Finding 1.2 — dropped (memory-cached reads; not a real cost).
- Section 3.x accessibility (3.1 Dynamic Type, 3.2 map gesture, 3.3 `CKContainer.default()` mismatch) — later tier.
- Owner-revoke-participant (carried over from the 2.4 work) — separate fix.

## References

- `docs/agy_general.md` — Section 1 findings.
- `Views/TripCardView.swift`, `Views/TripRecapView.swift`, `Services/RecapMapRenderer.swift`, `Views/ObservationRow.swift`.
