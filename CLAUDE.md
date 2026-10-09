# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**TripSpotter** — iOS app for collaboratively tracking license plate sightings on road trips.

- Bundle ID: `com.tentenbits.myRoadTripTracker`
- CloudKit container: `iCloud.com.tentenbits.myRoadTripTracker`
- iOS 18.1+ / Xcode 26+
- TestFlight active

## Build / Run / Test

Open `myRoadTripTracker/myRoadTripTracker.xcodeproj` in Xcode. There is no `Package.swift`, no `Podfile`, no Fastlane — Xcode is the build system.

```bash
# Build (CLI; useful for verifying compilation without launching the simulator)
xcodebuild -project myRoadTripTracker/myRoadTripTracker.xcodeproj \
           -scheme myRoadTripTracker \
           -destination 'platform=iOS Simulator,name=iPhone 17' \
           build
```

If that destination is gone, run `xcodebuild -showdestinations -project ... -scheme myRoadTripTracker`
and pick a current one rather than guessing — the installed simulator set moves with Xcode updates.

There are no unit-test or UI-test targets. Do not invent `xcodebuild test` commands or pretend a test suite exists. If a change calls for verification, build + run on a real device or simulator with iCloud signed in (CloudKit sharing requires real iCloud accounts to fully exercise).

CloudKit schema must be deployed to **production** in the CloudKit Dashboard before any TestFlight/App Store build can sync — development and production are separate environments.

## Shipping to TestFlight

Uploads run through the `iosPush` CLI, **from `myRoadTripTracker/` — not the repo root**, since the
`.xcodeproj` sits one level down and the CLI resolves both the project and the build number relative
to its working directory:

```bash
cd myRoadTripTracker
iosPush --dry-run   # prints resolved config, uploads nothing
iosPush
```

Afterwards, commit the build bump `agvtool` wrote into `project.pbxproj` (`git add -u`,
`chore: bump build to N`).

Full process, config-file layout, and failure triage: **[docs/releaseProcess.md](docs/releaseProcess.md)**.

## Architecture (the part you can't infer from `ls`)

The app is **Core Data + `NSPersistentCloudKitContainer`** with a **two-store** setup, migrated from an earlier SwiftData implementation. The two-store split is what makes collaborative sharing work.

- `Services/PersistenceController.swift` configures **two `NSPersistentStoreDescription`s on the same container**: one bound to the **private** CloudKit database, one bound to the **shared** database. Owner-created trips live in the private store; trips you've accepted via a share URL live in the shared store. Both feed the same `viewContext`.
- The container subscribes to `.NSPersistentStoreRemoteChange` and processes **persistent history** (`NSPersistentHistoryChangeRequest.fetchHistory(after: token)` → `viewContext.mergeChanges(fromContextDidSave:)`). `automaticallyMergesChangesFromParent` alone is **not** sufficient for live UI updates from CloudKit pushes — the history processor is what makes real-time sync work.
- "Am I the owner of this trip?" is answered by `privatePersistentStore.contains(managedObject: trip)`. Helpers in `Services/CoreDataHelpers.swift`.
- Share creation: `container.share([trip], to: nil)` → `persistUpdatedShare(share, in: privatePersistentStore)` (must be `await`ed via `withCheckedThrowingContinuation` before returning the `CKShare` to the UI, or share URL/metadata will be missing) → present via `UIActivityViewController`.
- Share acceptance is split between **`AppDelegate.swift`** (which contains the `SceneDelegate`) handling both `windowScene(_:userDidAcceptCloudKitShareWith:)` (running) and `scene(_:willConnectTo:options:)` (cold launch). Calls `container.acceptShareInvitations(from:into: sharedPersistentStore)`. **Both methods are required** — implementing only one drops cold-launch acceptances.
- `Info.plist` must contain `CKSharingSupported = true`. Without it, tapping a share URL shows "newer version needed."
- `CKShare.publicPermission = .readWrite` is set so URL recipients can join. Existing shares created with `.none` need this explicitly updated — do not assume new code paths will fix old shares.

### Source layout (`myRoadTripTracker/myRoadTripTracker/`)

```
App/         myRoadTripTrackerApp.swift, AppDelegate.swift (+SceneDelegate)
Models/      <Entity>+CoreDataClass.swift / +CoreDataProperties.swift  (4 entities)
Services/    PersistenceController, CoreDataHelpers, CloudKitUserHelper,
             LocationManager, Location (64 NA regions), ImageProcessor
Views/       SwiftUI views (ContentView, TripCardView, TripDetailView,
             PlateSightings*, Observations*, CloudSharingView, ...)
Resources/   Info.plist, .entitlements, .xcdatamodeld, Assets.xcassets,
             PrivacyInfo.xcprivacy
```

Note: the top-level `ARCHITECTURE.md` and `README.md` still describe an older flat layout (everything in `myRoadTripTracker/`). The actual current layout is the one above. If updating those docs, sync the structure.

### Data model (`Resources/myRoadTripTracker.xcdatamodeld`)

Four entities, all `usedWithCloudKit="YES"`:

- **Trip** — share root. Cascading to-many: `plateSightings`, `observationEntries`, `participants`.
- **PlateSighting** — region code/name + lat/lon + `seenDate` + `spottedByName` (optional per-trip display name of who marked it).
- **ObservationEntry** — append-only notes with `authorName`.
- **TripParticipant** — `displayName`, `cloudKitUserID`, `joinedDate`.

## Sharp edges (will bite you again)

These are non-obvious things that have already cost time on this project. Honor them before "cleaning up."

1. **Do not edit `project.pbxproj` programmatically.** This project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+ auto file discovery). New `.swift` files in the source dir are picked up automatically. Adding explicit `PBXFileReference` entries (e.g. via the `pbxproj` Python library) creates duplicate compile targets and breaks the build. The `.xcdatamodeld` is also auto-discovered.

2. **CloudKit-synced attributes must be `optional="YES"` in the model AND `Optional` in Swift** — even if your convenience init always sets a value. CloudKit can deliver partially-synced records with nil fields; non-optional `@NSManaged` Date/UUID properties crash on nil. Date and UUID specifically *cannot* have compile-time defaults in `.xcdatamodeld` XML, so they **must** be optional.

3. **`codeGenerationType="manual/none"` is not a valid value** in `.xcdatamodeld` XML — it crashes Xcode on project open. Use `"class"` or `"category"`, or omit the attribute.

4. **Don't capture `[weak self]` inside `loadPersistentStores` during `init` of an `@Observable` class.** The macro's backing storage isn't fully initialized during init, so `weak self` is nil in the callback. Use local variables in the closure and assign to `self` after.

5. **Assign `persistentStoreDescriptions` as a full array**, not via `.append()`. The `@NSCopying` semantics make append unreliable: `container.persistentStoreDescriptions = [private, shared]`.

6. **`NotificationCenter` observers should be closure-based** (`addObserver(forName:object:queue:using:)`), not `@objc` selector-based. `@objc` runtime dispatch interacts badly with `@MainActor`-isolated classes here.

7. **Do not introduce a dual SwiftData + Core Data stack** on the same SQLite file. Two `NSPersistentStoreCoordinator`s have WAL visibility issues and the CloudKit mirroring delegates conflict ("There is another instance of this persistent store actively syncing with CloudKit in this process"). The migration away from SwiftData was deliberate.

## Privacy invariants (non-negotiable)

The product spec is privacy-forward; these constraints come up in design discussions and must hold:

- **Location:** one-shot GPS only, requested at first plate tap. **No background, no Always permission, no route tracking.** If permission is denied, plates can still be marked with coords `0,0`.
- **Plate sightings carry optional author attribution** via `spottedByName` (set from the marker's per-trip display name, shown as "by <name>" in `PlateSightingDetailSheet`). This is intentional — do not remove it. (Earlier specs called for no attribution here; that invariant was relaxed.)
- **Map shows pins only** — no lines, routes, or animated paths.

## Other repo notes

- `ARCHITECTURE.md` is a hand-maintained context doc (not generated). It lags the code occasionally — trust source over docs and update the doc when you notice drift.
- Work items live in GitHub Issues — `gh issue list`; `/next` applies.
- Auto-memory at `~/.claude/projects/-Users-sam-code-apple-myRoadTripTracker/memory/` contains additional CloudKit/Xcode lessons; consult it when debugging sync or project-file issues.
- No Cursor rules, no Copilot instructions, no CI in this repo.
