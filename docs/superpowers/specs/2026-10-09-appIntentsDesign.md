# Siri and Spotlight (App Intents) — Design Spec

**Date:** 2026-10-09
**Status:** agreed in conversation (scope = intents 1–6, "current trip" rule, marking while locked).
**Reference implementation:** `~/code/apple/blobAttack` PR #126 — spec `docs/superpowers/specs/2026-10-09-appIntents-design.md`, code in `blobAttack/intents/`. KB playbook: `~/code/groverKnowledge/playbooks/appIntentsSiri.md`.

---

## Why

On a road trip the phone is in a passenger's hand, a cup holder, or on CarPlay. Opening TripSpotter, finding the trip, and tapping a tile is the slow path. Saying "We saw Maine in TripSpotter" or "How many states have we seen in TripSpotter?" is the fast one. Apple's App Intents framework hands the app's actions to Siri, Spotlight, the Shortcuts app, the Action button and CarPlay, with no setup by the user.

## Success looks like

- A plate is logged by voice in one sentence, credited to the speaker's display name, and appears on the other participants' phones the same way a tapped plate does.
- The four trip questions get a short spoken answer plus a card, without the app opening, on a locked phone and on CarPlay.
- Nothing about the privacy invariants changes: one-shot location only, never a prompt from Siri, `0,0` when there is no fix.

## How App Intents work (short version)

- **Intent** — one action: a struct with a title, `@Parameter` inputs and `perform()`. Metadata is extracted at build time.
- **App enum** — a fixed value list the system can speak (our 64 regions).
- **App entity + query** — the app's things looked up by name (trips), with free disambiguation ("Which trip? A or B").
- **App Shortcut** — a phrase tied to an intent. Live from install. **Every phrase must contain the app name** (`\(.applicationName)`), at most one parameter per phrase, at most 10 shortcuts per app.
- **Result** — spoken dialog, optional SwiftUI snippet card, optionally the app opening.

TripSpotter fits no Apple Intelligence schema domain, so this is App Shortcuts + Spotlight, not free-form conversation.

---

## Decisions

| Question | Decision |
|---|---|
| Scope | Six intents (below). Add-a-note and undo/unmark are later. |
| "Current trip" with no trip named | The open (`isClosed == false`) trip with the most recent activity: latest `PlateSighting.seenDate`, else `createdDate`. Normally there is only one open trip. |
| No open trip | Siri says "You don't have an open trip. Start one in TripSpotter." Nothing is written. |
| A named trip that matches none or several | Siri asks "Which trip?" via the trip query. |
| Region already seen | "Maine's already on the list — Sam spotted it yesterday." Nothing is written. |
| Who gets credit | The speaker's `TripParticipant.displayName` on that trip (matched by `CloudKitUserHelper.currentUserID()`), else `UserDefaults` `defaultDisplayName`, else "Me" — the same name a tap would use. The intent never creates a `TripParticipant`. |
| Location for a voice mark | One fix, **only if when-in-use is already granted**, with a 3 s timeout; otherwise `0,0`. Siri never triggers the permission prompt. iOS may refuse a fix to a background launch; then the plate is logged without a map pin, the same as a denied-permission tap. |
| "Washington" vs "DC" | "Washington" is the state. DC answers to "DC", "D.C.", "Washington DC", "District of Columbia". |
| Locked phone | All five background intents run locked (plate names and counts are low-stakes). "Open my trip" needs unlock, which iOS asks for itself. |
| Sync after a voice mark | After saving, the intent waits up to 5 s for `NSPersistentCloudKitContainer.eventChangedNotification` to report an `.export` that ended after the save, then returns. If iOS suspends the app before the upload, the plate syncs on next launch — device-tested. |
| Closed trip named explicitly | Questions answer normally (a closed trip's count is still interesting). Marking refuses: "Summer Trip is closed." |
| Extension vs app target | App target, as in blobAttack. An extension would need the Core Data stack shared across targets. |
| Siri's first-run "turn on shortcuts" ask | iOS gives the app no switch to open; the first recognised request asks once. A one-time **"Ask Siri" what's-new card** teaches a phrase that is sure to match and says "say yes" (below). The TestFlight "What to Test" note repeats it. |

---

## The six intents

| # | Intent | Example phrases | Opens app? | Answer |
|---|---|---|---|---|
| 1 | `MarkPlateIntent(region, trip?)` | "We saw \(region) in TripSpotter" · "We just saw \(region) in TripSpotter" · "Tick off \(region) in TripSpotter" · "Mark \(region) in TripSpotter" | No | "Got it — Maine is number 24 on Summer Trip." Card: flag + region name + new US/Canada counts. |
| 2 | `TripCountIntent(trip?)` | "How many states have we seen in TripSpotter" · "How many plates have we seen in TripSpotter" · "How many states on \(trip) in TripSpotter" | No | "On Summer Trip you've seen 23 states and 4 from Canada." Card: `DualProgressRingView` + "23 of 51 US · 4 of 13 Canada". |
| 3 | `HaveWeSeenIntent(region, trip?)` | "Have we seen \(region) in TripSpotter" · "Did we see \(region) in TripSpotter" | No | Yes: "Yes — Dana spotted Ohio on Tuesday." No: "Not yet. Ohio's still out there." Card: flag tile seen/unseen, with spotter + date when seen. |
| 4 | `PlatesLeftIntent(trip?)` | "Which states are left in TripSpotter" · "What plates are left in TripSpotter" · "What's left on \(trip) in TripSpotter" | No | ≤ 8 left in total: names them ("Still missing: Hawaii, Alaska and Maine."). More: "28 states and 9 from Canada to go — they're on the card." Card: unseen region codes as chips, US then Canada. |
| 5 | `TopSpotterIntent(trip?)` | "Who's spotted the most in TripSpotter" · "Who's winning in TripSpotter" · "Who's winning \(trip) in TripSpotter" | No | "Dana leads Summer Trip with 14. Sam has 9." Tie: "Dana and Sam are tied with 12." One spotter: "Sam has spotted all 9." Card: ranked rows, name + count. Sightings with no `spottedByName` are counted as "Unknown" and never lead the spoken line. |
| 6 | `OpenTripIntent(trip?)` | "Open my trip in TripSpotter" · "Open \(trip) in TripSpotter" | Yes | App opens on that trip's detail view. No speech. |

Six of Apple's ten shortcuts. Trip-parameter phrase variants are only offered where the phrase has no region (one parameter per phrase); `MarkPlateIntent` and `HaveWeSeenIntent` still take an optional trip in the Shortcuts app.

### Edge cases (all intents)

| Case | Answer |
|---|---|
| No trips at all | "You don't have any trips yet. Start one in TripSpotter." |
| Store failed to load | "I couldn't open your trips just now." |
| Trip with zero sightings | Count: "Nothing spotted on Summer Trip yet." Left: "All 64 to go." Top spotter: "Nobody's spotted a plate on Summer Trip yet." |
| Everything seen | Left: "You've seen every plate on Summer Trip!" |
| Shared trip the user can't edit (`canEdit` false) | Marking refuses: "You can't add to Summer Trip." |

---

## "Ask Siri" what's-new card

Announces the feature once, as blobAttack's Siri card did (`blobAttack/models/whatsNew.swift`). TripSpotter has no what's-new system yet, so this adds a small one shaped like blobAttack's — a list of announcements plus a seen-set — without its remote switches, pager or Settings replay (TripSpotter has no Settings screen). A second card later is one entry in the list.

**Words**

- Title: **Ask Siri**
- "Log plates and check your trip without opening the app — handy from the passenger seat or on CarPlay."
- Key line (bold): Say "We saw Maine in TripSpotter"
- "Or ask "How many states have we seen in TripSpotter?" The first time, Siri asks to turn on TripSpotter's shortcuts. Say yes."
- "Missed it? In the Shortcuts app, open TripSpotter, tap ⓘ and turn Siri on." (Added after TestFlight 62: a "no" to Siri's first-run question isn't asked again.)

**When it shows**

- On the trip list (`ContentView`), as a sheet at the medium detent, once per phone.
- Only after onboarding is complete **and** the user has at least one trip — Siri has nothing to answer about without one. A brand-new user sees it the first time they come back to the list after creating a trip.
- Not while a share acceptance or another alert/sheet is up on the list; it waits for the next appearance.
- Closing it any way (Got it, swipe down) marks it seen. Seen IDs live in `UserDefaults` under `whatsNew.seen` as raw strings, so an ID from a newer build survives.

**Look**

- System sheet background (follows light/dark), a `mic.fill` / `waveform` symbol in a circle of the app's open-trip green (`TripCardView`'s `Color(red: 0.2, green: 0.65, blue: 0.35)`), a small "NEW" capsule, the title, the three lines, and a full-width "Got it" button in the same green.
- Dynamic Type safe (scrolls if the text is large); VoiceOver reads the title first.
- Checked in light and dark mode before calling it done.

---

## Code shape

New folder `myRoadTripTracker/Intents/` (auto-discovered — **no `project.pbxproj` edits**, sharp edge 1).

| File | Holds |
|---|---|
| `Intents/PlateRegion.swift` | `PlateRegion: String, AppEnum` — 64 literal cases keyed by `Location.code`, with `DisplayRepresentation(title:synonyms:)`. Literals are required by the App Intents compiler, so `PlateRegion.location` maps to `Location.allLocations`, and a `#if DEBUG` launch assert checks the two lists match. |
| `Intents/TripEntity.swift` | `TripEntity` (id = `tripID` UUID string, name, isClosed) + `TripQuery: EntityStringQuery` (by id, by name, suggested = all trips, open first). |
| `Intents/TripIntents.swift` | Intents 2–5 (read-only). |
| `Intents/MarkPlateIntent.swift` | Intent 1, the only writer. |
| `Intents/OpenTripIntent.swift` | Intent 6. |
| `Intents/IntentSnippets.swift` | The cards, built from `DualProgressRingView`, the flag assets (`Location.flagImageName`) and `TripCardView`'s styling. |
| `Intents/TripSpotterShortcuts.swift` | `AppShortcutsProvider` + phrases. |
| `Intents/IntentAnswers.swift` | Pure builders: plain values in (seen codes, spotter names, dates), spoken line + card model out. No Core Data, no AppIntents — testable later. |
| `Intents/IntentTrips.swift` | Data access: `currentTrip(in:)`, `trip(for: TripEntity?)`, `speakerName(for:)`, `markPlate(...)` using `PersistenceController.shared.container.viewContext`. |
| `Services/WhatsNew.swift` | `Announcement` (id, title, lines with an `isKey` flag), `WhatsNew.all`, `WhatsNew.next(seen:hasTrips:)`, and `WhatsNewStore` (the seen-set in `UserDefaults`). |
| `Views/WhatsNewSheet.swift` | The card above. |
| `Services/IntentRoute.swift` | `@Observable @MainActor` pending trip `NSManagedObjectID`; `ContentView` takes it and sets `navigationPath`. Same shape as blobAttack's `IntentRoute`. |

**Changed files**

- `LocationManager` — add `requestFixIfAuthorized(timeout:)`: returns `nil` immediately unless already authorized; never calls `ensureAuthorized()`'s prompt path.
- `ContentView` — observe `IntentRoute.shared`, push the requested trip (pop to root first); present `WhatsNewSheet` when `WhatsNew.next` returns a card.
- `PersistenceController` — `awaitExport(after:timeout:)` helper on the `eventChangedNotification` (closure-based observer, sharp edge 6).
- Trip create / rename / delete sites call `TripSpotterShortcuts.updateAppShortcutParameters()` so trip-name phrases stay current; also once at launch.

**Background launches.** iOS can run an intent without `ContentView` existing. Intents reach the stack only through `PersistenceController.shared`, wait for its stores to load, and touch no view state. Marking duplicates `PlateSightingsGrid.markAsSeen`'s insert + `save(contextInfo:)` rather than calling the view.

**Plate writes go to the right store automatically:** assigning `sighting.trip` puts the sighting in the trip's store (private for owned, shared for joined), as the tap path does today.

---

## Testing

There is no test target (per `CLAUDE.md`). Verification for this build:

- **Build gate:** `xcodebuild … build` once per task.
- **Simulator:** run each intent from the Shortcuts app (no iCloud needed for the reads; marking against a local trip).
- **What's-new card:** shows once with ≥ 1 trip, not with zero, never again after Got it or a swipe; light and dark screenshots.
- **Device (TestFlight):** the card's exact phrase first (it must trigger Siri's turn-on ask), then every phrase spoken once; mark on device A while device B watches the trip (sync timing); a voice mark with the phone locked; one CarPlay run if available; check whether a background voice mark gets a GPS fix.
- **Follow-up (proposed, not in this build):** add a unit-test target for `IntentAnswers` and `currentTrip` selection.

## Build order

1. `PlateRegion`, `TripEntity`/`TripQuery`, `IntentTrips.currentTrip`, `TripCountIntent` with a spoken line only + one shortcut — proves the background path end to end.
2. `IntentAnswers` + intents 3–5 (spoken lines).
3. `MarkPlateIntent`, `requestFixIfAuthorized`, `awaitExport`.
4. `OpenTripIntent` + `IntentRoute` + `ContentView` hookup.
5. Snippet cards (light and dark Siri panels).
6. Full phrase set in `TripSpotterShortcuts`, `updateAppShortcutParameters` call sites.
7. "Ask Siri" what's-new card (`WhatsNew`, `WhatsNewSheet`, `ContentView` hookup).

## Not in this design

- Add a note by voice; undo/unmark by voice.
- Start or close a trip by voice.
- Widgets / Control Center controls.
- Replaying what's-new cards later (no Settings screen to put it in).
- Apple Intelligence schemas (no matching domain).
