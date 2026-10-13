# Plate Passport (phase 1)

Issue #78. Also fixes #77, the recap's plate count, which needs the same rule. Mockups, with
the chosen options: https://claude.ai/artifact/7MJSd11dtG1DDPNS1nHwcV

## Goal

Families who play TripSpotter on every trip can see what their trips add up to: the plates
they always see, the ones they've never seen, and how each trip compares. While on a trip,
that history makes the game better. You get a moment when you spot a plate for the first time
ever, and a hint about which plates to watch for.

## Rules that hold everywhere

- **History** means every trip on this phone: your own and the ones shared with you, open or
  closed. Trips with no plates don't count as trips here.
- **A plate counts once per trip.** Sync can leave two sightings of one region on a trip, so
  counts use distinct region codes. The recap does the same (#77).
- **Group-level only.** Nothing totals who spotted what across trips. Trips are shared ad hoc,
  and `spottedByName` is free text per trip, so a person can't be followed from trip to trip.
- **No data model change** and no CloudKit schema deploy. Everything comes from existing fields.
- **History must have something to say.** Features that compare trips stay hidden until
  there's history to compare (thresholds below). A first-ever trip shows no "first time ever"
  badges, no "Watch for" strip and no Passport row.

## 1 · Way in: Passport row (option B)

On the Road Trips screen, a row titled **Plate Passport** with the subtitle
"46 of 64 plates · 6 trips". It comes after the open trips and before Past Trips, and the
whole row opens the Passport screen.

- Shown when at least one **closed** trip has plates, and the search field is empty.
- An icon tile (globe on amber) leads the row. The row follows the inset-grouped list style.

## 2 · Passport screen (option A, stats page)

Top to bottom:

1. **Collection panel** (green panel, like the hero card): "All-time collection", the big
   number "46 of 64", the US and CA progress bars, and "6 trips since March 2024", where the
   date is the month and year of the earliest sighting.
2. **Three stat tiles:**
   - Typical trip: the median plate count of closed trips with plates. Shown only when there
     are 2 or more of them.
   - Record: the highest plate count, labelled with that trip's name.
   - Never seen: how many plates no trip has seen.
3. **Usual suspects** (2+ trips): seen plates ranked by how many trips saw them, then by name.
   Each row has a flag, the name, a small bar and "N of M". The top 6 show, and a button
   expands to all of them.
4. **Still hunting · N:** never-seen plates as grey chips, in the app's usual plate order.
   Hidden when every plate has been seen.
5. **Seen only once · N** (2+ trips): plates exactly one trip saw, as colour chips that can't
   be tapped.
6. **Trips by plates:** every trip with plates, most plates first, each with a bar scaled to
   the record. An open trip says "in progress". Tapping a trip opens it.

It updates live when a trip or sighting changes, like the trip list.

## 3 · First time ever (option B: toast plus lasting badge)

- **First ever** for a plate means the trip with that plate's earliest sighting, across all
  of history. Sightings with no date never count as first.
- Badges and the pill show only when some **other** trip has plates. Otherwise every plate on
  your first trip would be "first".
- **Toast:** when you mark a plate on this phone that no trip has, a capsule toast at the
  bottom says "First time ever: Wyoming!" with the flag, and "Your collection is now 47 of 64".
  It lasts about 3 seconds, and VoiceOver announces it. Plates arriving from collaborators or
  Siri don't toast.
- **1ST badge:** a gold capsule at the top left of the tile, on every plate this trip saw
  first. It stays for the life of the trip. Unmarking the plate removes it.
- **Pill:** above the plate sections, "2 new to your collection this trip", led by a small
  1ST capsule. It's shown on open and closed trips when the number is above zero.

## 4 · Watch for (option A, strip)

- On an **open** trip, above the US section: the heading **Watch for**, the caption "seen on
  most past trips", and a horizontal strip of up to 8 plates.
- The candidates are plates this trip hasn't seen that at least one other trip has, ranked by
  how many other trips saw them, then by name. Each card has a grey flag, the code, the name,
  and "N of M trips", where M is the number of other trips with plates.
- Shown when 2 or more other trips have plates and there's at least one candidate. It's
  independent of the All / Not Seen filter.
- Tapping a card marks the plate seen, exactly like tapping its tile, with a success haptic.
  The card then leaves the strip.

## 5 · What's new

The Plate Passport what's-new card is shown once, the first time the Passport row would
appear.

## Out of scope (later phases)

Pace against your usual trip, distance and geography facts, time-of-day patterns, Siri
questions about history, recap comparisons, and per-person stats.
