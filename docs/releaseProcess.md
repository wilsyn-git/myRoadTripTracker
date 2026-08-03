# Release Process (TestFlight)

How a build gets from this repo to TestFlight. Uploads go through the `iosPush` CLI
(`~/.local/bin/iosPush`), which handles preflight, build bump, archive, export, and the
`altool` upload in one shot. Do not reimplement those steps by hand.

## The one thing that trips everyone up

**Run `iosPush` from `myRoadTripTracker/`, not the repo root.**

```bash
cd myRoadTripTracker    # the directory containing myRoadTripTracker.xcodeproj
iosPush
```

The `.xcodeproj` lives one level below the repo root. From the root, `iosPush` fails outright
with `no .xcworkspace or .xcodeproj in ...`. Worse, if you work around that with
`--project myRoadTripTracker/myRoadTripTracker.xcodeproj`, the CLI *appears* to resolve — but it
still runs `agvtool` in its own working directory, where there is no project, so the build number
reads as `<unknown>` and the bump step is unreliable. Running from `myRoadTripTracker/` fixes both.

## Normal upload

```bash
cd myRoadTripTracker
iosPush --dry-run    # optional: prints resolved config, uploads nothing
iosPush
```

A healthy dry run looks like this — if `export options`, `current build`, or `creds source` show
`<NOT FOUND>` or `<unknown>`, stop and fix that before uploading:

```
    project:          myRoadTripTracker.xcodeproj
    scheme:           myRoadTripTracker
    export options:   ./ExportOptions.plist
    bump strategy:    agvtool
    current build:    60
    next build:       61
    creds source:     /Users/<you>/.appstoreconnect/config
```

Pass `--build N` only to force a specific build number. Avoid `--no-bump` unless you deliberately
intend to reuse a build number — App Store Connect rejects duplicates.

Archive and upload together run past ten minutes on a cold build. Run it in the background or give
it a generous timeout rather than killing it midway.

## Afterwards: commit the bump

`agvtool` writes the new `CURRENT_PROJECT_VERSION` into `project.pbxproj`. That edit is expected and
is the one sanctioned automated change to that file — see the "do not edit `project.pbxproj`
programmatically" rule in `CLAUDE.md`, which is about adding file references, not version bumps.

```bash
git add -u
git commit -m 'chore: bump build to N'
```

Commit it promptly. Skipping this leaves the repo claiming an older build than what actually shipped;
builds 58–60 drifted this way before being caught.

## Configuration files

| File | Tracked? | Notes |
| --- | --- | --- |
| `myRoadTripTracker/ExportOptions.plist` | yes | App Store Connect export method, team ID, automatic signing. Deliberately placed beside the `.xcodeproj` rather than inside the file-system synchronized source group, so Xcode does not bundle it into the app. |
| `~/.appstoreconnect/config` | no — local secret | API key credentials. Never edit or commit. If `iosPush` reports it missing, the user must create it; do not guess values. |

Both projects here share team `Y4D6SPW6PL` with automatic signing and no bundle-specific
provisioning profiles, so `ExportOptions.plist` is portable between this repo and `~/code/iosJournal`.

## When it fails

`iosPush` tails the relevant log itself; read what it prints rather than guessing.

- **Preflight** (missing `ExportOptions.plist`, missing credentials, missing `agvtool`) — stop and
  fix the named file. Do not fabricate config or team IDs.
- **Archive** — `myRoadTripTracker/build/archive.log`
- **Export** — `myRoadTripTracker/build/export.log`

`build/` is gitignored, so these logs stay local.

## Before the build can actually sync

CloudKit schema changes must be deployed to **production** in the CloudKit Dashboard before a
TestFlight build can sync. Development and production are separate environments, and
`initializeCloudKitSchema()` runs only in `DEBUG`, so it never touches production.

Changing only Swift code — including writing to attributes that already exist in the model — needs no
schema deploy. Confirm with `git status` on `Resources/myRoadTripTracker.xcdatamodeld` when unsure.

## Verifying the upload landed

Processing in App Store Connect takes roughly 5–15 minutes after `UPLOAD SUCCEEDED`. The build is not
installable until that finishes. Check the real state in App Store Connect rather than assuming the
upload's success message means it is ready to test.
