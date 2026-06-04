# Trip Recap — Design

**Date:** 2026-06-04
**Status:** Approved design, pre-implementation
**Feature area:** TripSpotter end-of-trip summary

## Overview

A shareable end-of-trip **Recap** card that combines:

- computed trip **stats** (plates seen, day span, MVP spotter, rare catches, observation counts),
- a **pin map** of where plates were spotted,
- an optional **AI-written narrative** blurb (on-device, private),

generated when the owner closes a trip, viewable anytime, synced to all
participants, and exportable as an image.

The guiding principle: **the model writes the words, code computes the numbers.**
All stats and the map are derived deterministically from synced data; the
on-device LLM only produces prose flavor over numbers it is handed. This avoids
the recap ever displaying a fabricated count.

## Privacy alignment

This feature is fully consistent with the app's privacy posture:

- Narrative generation runs **entirely on-device** via Apple's Foundation Models
  framework — nothing leaves the phone, no API key, no network.
- No Contacts access, no phone numbers, no auto-sent messages (see Delivery).
- The map renders **pins only** — no routes or lines (honors the existing map
  invariant).

## Data model change (CloudKit)

Two additive **optional** attributes on the existing `Trip` entity. Per the
project's CloudKit rule, they are optional in **both** the `.xcdatamodeld` model
and in Swift:

| Attribute | Type | Purpose |
|---|---|---|
| `recapNarrative` | `String?` | The generated blurb, synced to all participants. |
| `recapGeneratedDate` | `Date?` | When it was generated. Timestamps the snapshot and drives the "recap ready" in-app badge. |

`recapGeneratedDate` is a `Date` and therefore (per the project's xcdatamodeld
rule) cannot carry a compile-time default — it must be optional.

**Deployment note:** these additive attributes require **one CloudKit production
schema deploy** in the CloudKit Dashboard before any TestFlight/App Store build
will sync them. Development and production are separate environments.

## Components

Each unit has one clear purpose and can be understood and tested independently.

### `RecapStats`
A plain Swift struct plus a pure function `RecapStats(trip:)` that computes
everything the card needs from a `Trip`:

- US states seen out of 50; Canadian provinces/territories seen out of 13.
- Total sightings; trip day span (first → last `seenDate`).
- Per-spotter tallies (from `spottedByName`) → **MVP** (top spotter).
- **Rare catches** — which low-frequency regions were caught (e.g. AK, HI, and
  the farther/less-populous Canadian regions such as NU, NT, YT, PE, NL).
- Observation count and number of observations with a photo.

Performs **no** Core Data writes. Reads only the trip's already-synced
relationships. Fully unit-testable in isolation (though the project currently
has no test target — see Verification).

### `RecapNarrativeGenerator`
Wraps `FoundationModels`:

1. Checks `SystemLanguageModel.default.availability`.
2. If available, feeds the computed `RecapStats` to a `LanguageModelSession` and
   returns a short (2–3 sentence) upbeat blurb.
3. If unavailable (device ineligible, Apple Intelligence off, or model not yet
   downloaded), returns `nil` — the caller falls back to a template.

The narrative is a single short paragraph, so a plain prompt is sufficient;
guided generation is not required.

### `RecapMapRenderer`
Wraps `MKMapSnapshotter`. Turns the trip's sighting coordinates
(`hasValidCoordinate` only) into a static **pin** image sized for the card. Pins
only — no routes.

### `TripRecapView`
The SwiftUI card that assembles narrative + stats + map image + observation
stats, with a **Share** button. Designed to render cleanly both on screen and
when rasterized for sharing.

## Data flow

### Generation — on close (owner only)
Closing a trip is already owner-gated (`.disabled(!isOwner)` in
`TripDetailView`).

1. Owner toggles `isClosed → true`.
2. If `RecapNarrativeGenerator` reports the model available, generate the blurb.
3. Save `recapNarrative` + `recapGeneratedDate` on the `Trip`.
4. CloudKit syncs both fields to all participants.

If the owner's device cannot generate (no Apple Intelligence), the fields stay
`nil` and every participant simply sees the template narrative.

### Viewing — anytime
A **Recap** button in `TripDetailView`'s toolbar opens `TripRecapView` at any
time (open or closed trip):

- Stats and the map are **recomputed/rendered live** from synced data.
- Narrative = stored `recapNarrative` if present; otherwise a **template
  fallback** built from `RecapStats` (e.g. "32 states, 6 days — Maya spotted the
  most").

So non-AI devices and pre-close views always get a complete, correct card — they
just lack the prose flourish.

## Delivery

### Path A — in-app, to everyone on the trip
Because all participants are already connected through the shared CloudKit store,
the recap fields sync to everyone automatically. To signal "a recap is ready,"
show an **in-app badge** on the trip tile (e.g. a ✨ / "Recap ready" marker),
mirroring the existing orange "new notes" dot pattern.

This requires **no notification permission** and is consistent with the app,
which currently uses zero system notifications. A real `UNUserNotificationCenter`
local notification was considered and **deliberately rejected** as too heavy for
this app's lightweight, permission-light posture.

The badge's "seen" state is tracked per-trip in `UserDefaults` (same approach as
the observations "last viewed" timestamp keyed by trip ID).

### Path B — share outward
A **Share** button renders `TripRecapView` to a `UIImage` (via `ImageRenderer`)
and hands it to `UIActivityViewController` — the same component already used for
share links. The user picks Messages / AirDrop / social / etc. and chooses
recipients themselves. Good for sharing the trip with people who don't have the
app.

## Error & edge handling

- **Foundation Models unavailable** → template narrative (card still complete).
- **Map snapshot fails or no valid coordinates** → card renders without the map,
  gracefully.
- **Empty trip** (no sightings *and* no observations) → show a gentle empty
  state instead of a recap card.
- **Reopened / edited closed trip** → stats and map reflect the current state;
  the stored narrative remains as of its `recapGeneratedDate` (timestamped, so
  the snapshot moment is clear).

## Out of scope

Explicitly not part of this feature:

- Phone numbers / Contacts access.
- Auto-sending texts or any silent messaging (iOS does not permit it, and the
  app holds no contact info by design).
- Route lines or paths on the map (pins-only invariant).
- Per-person customized cards (the recap is a shared, consistent artifact).
- Image Playground generated cover art — a possible future flourish, not now.

## Verification

The project has **no unit-test or UI-test targets**; do not invent
`xcodebuild test`. Verification is build + run on simulator/device with iCloud
signed in:

- The **template** narrative path is testable on the **simulator**.
- The **Foundation Models** path requires a real Apple-Intelligence-capable
  device (iPhone 15 Pro or newer with the feature enabled and the model
  downloaded).
- Cross-device sync of `recapNarrative` requires two real iCloud accounts (one
  owner, one share recipient), exercised against the **production** CloudKit
  environment after the schema deploy.

## Open follow-ups (not blocking)

- Exact visual design of `TripRecapView` (layout, colors, card framing) — to be
  refined during implementation; should match the existing tile aesthetic
  (colored gradient, white text, rounded corners).
- Final "rare catch" region list and whether rare catches affect any scoring.
