# Collaborative Trip Sharing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable multiple users to collaboratively share and update road trips via CloudKit sharing.

**Architecture:** SwiftData models restructured for CloudKit compatibility (optional properties, defaults). CloudKit sync via `ModelConfiguration` with a `CloudKitDatabase` for private data. `CKShare` for multi-user collaboration on individual trips. Local-only user preferences stored in `@AppStorage`. Append-only observation entries replace the current single-string observation model.

**Tech Stack:** SwiftUI, SwiftData, CloudKit, CKShare, CoreLocation, MapKit, Universal Links

**Spec:** `docs/sharingSpec.md`

**Source directory:** `myRoadTripTracker/myRoadTripTracker/` (relative to repo root)

---

## Phase 1: Model Layer & Data Restructuring

### Task 1: Restructure TripObservation into ObservationEntry

The current `TripObservation` model stores one `response: String` per category. The spec requires append-only entries with author attribution. Replace the model entirely.

**Files:**
- Delete: `myRoadTripTracker/myRoadTripTracker/TripObservation.swift`
- Create: `myRoadTripTracker/myRoadTripTracker/ObservationEntry.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Trip.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/myRoadTripTrackerApp.swift`

- [ ] **Step 1: Create ObservationEntry model**

Create `myRoadTripTracker/myRoadTripTracker/ObservationEntry.swift`:

```swift
import Foundation
import SwiftData

@Model
final class ObservationEntry {
    var category: String
    var authorName: String
    var text: String
    var createdDate: Date
    var trip: Trip?

    init(category: String, authorName: String, text: String, createdDate: Date = .now) {
        self.category = category
        self.authorName = authorName
        self.text = text
        self.createdDate = createdDate
    }
}
```

- [ ] **Step 2: Update Trip model relationships**

In `Trip.swift`, replace the `observations` relationship:

```swift
// Replace this:
@Relationship(deleteRule: .cascade, inverse: \TripObservation.trip)
var observations: [TripObservation] = []

// With this:
@Relationship(deleteRule: .cascade, inverse: \ObservationEntry.trip)
var observationEntries: [ObservationEntry] = []
```

- [ ] **Step 3: Add isClosed property to Trip**

In `Trip.swift`, add the property:

```swift
var isClosed: Bool

init(name: String = "New Trip", createdDate: Date = .now) {
    self.name = name
    self.createdDate = createdDate
    self.isClosed = false
}
```

- [ ] **Step 4: Update ModelContainer registration**

In `myRoadTripTrackerApp.swift`, replace `TripObservation.self` with `ObservationEntry.self`:

```swift
.modelContainer(for: [Trip.self, PlateSighting.self, ObservationEntry.self])
```

- [ ] **Step 5: Delete TripObservation.swift**

Delete the file `myRoadTripTracker/myRoadTripTracker/TripObservation.swift`.

- [ ] **Step 6: Verify build**

Run: `xcodebuild build -project myRoadTripTracker/myRoadTripTracker.xcodeproj -scheme myRoadTripTracker -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

Expected: Build will fail due to `ObservationsSection.swift` and `ObservationRow.swift` still referencing old model. That's expected — we fix those in Task 3.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: replace TripObservation with ObservationEntry model

Append-only observation entries with author attribution replace
the single-string-per-category model. Add Trip.isClosed property."
```

---

### Task 2: Add TripParticipant Model

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/TripParticipant.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/Trip.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/myRoadTripTrackerApp.swift`

- [ ] **Step 1: Create TripParticipant model**

Create `myRoadTripTracker/myRoadTripTracker/TripParticipant.swift`:

```swift
import Foundation
import SwiftData

@Model
final class TripParticipant {
    var displayName: String
    var cloudKitUserID: String
    var joinedDate: Date
    var trip: Trip?

    init(displayName: String, cloudKitUserID: String, joinedDate: Date = .now) {
        self.displayName = displayName
        self.cloudKitUserID = cloudKitUserID
        self.joinedDate = joinedDate
    }
}
```

- [ ] **Step 2: Add participants relationship to Trip**

In `Trip.swift`, add:

```swift
@Relationship(deleteRule: .cascade, inverse: \TripParticipant.trip)
var participants: [TripParticipant] = []
```

- [ ] **Step 3: Update ModelContainer**

In `myRoadTripTrackerApp.swift`:

```swift
.modelContainer(for: [Trip.self, PlateSighting.self, ObservationEntry.self, TripParticipant.self])
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add TripParticipant model for per-trip identity"
```

---

### Task 3: Rewrite Observation UI for Append-Only Entries

The current `ObservationsSection` and `ObservationRow` use a single editable text field per category. Replace with an append-only entry list with a compose field.

**Files:**
- Rewrite: `myRoadTripTracker/myRoadTripTracker/ObservationsSection.swift`
- Rewrite: `myRoadTripTracker/myRoadTripTracker/ObservationRow.swift`

- [ ] **Step 1: Rewrite ObservationRow as ObservationEntryRow**

Replace the entire contents of `myRoadTripTracker/myRoadTripTracker/ObservationRow.swift` with:

```swift
import SwiftUI
import SwiftData

struct ObservationEntryRow: View {
    let entry: ObservationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.authorName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(entry.createdDate, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.text)
                .font(.body)
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 2: Rewrite ObservationsSection with append-only entries**

Replace the entire contents of `myRoadTripTracker/myRoadTripTracker/ObservationsSection.swift` with:

```swift
import SwiftUI
import SwiftData

struct ObservationsSection: View {
    @Bindable var trip: Trip
    let currentUserName: String
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""

    private let predefinedCategories = [
        "Weirdest thing we've seen",
        "Coolest car",
        "Funniest billboard",
        "Weirdest billboard",
        "Best roadside attraction",
        "Most interesting license plate",
    ]

    var body: some View {
        ForEach(allCategories, id: \.self) { category in
            Section {
                let entries = entriesForCategory(category)
                if entries.isEmpty {
                    Text("No entries yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                ForEach(entries) { entry in
                    ObservationEntryRow(entry: entry)
                }
                if !trip.isClosed {
                    ComposeEntryRow(category: category, authorName: currentUserName) { text in
                        addEntry(category: category, text: text)
                    }
                }
            } header: {
                Text(category)
            }
        }

        if !trip.isClosed {
            Section {
                Button {
                    showingAddCategory = true
                } label: {
                    Label("Add Custom Category", systemImage: "plus.circle.fill")
                }
            }
            .alert("Add Custom Category", isPresented: $showingAddCategory) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) {
                    newCategoryName = ""
                }
                Button("Add") {
                    newCategoryName = ""
                }
            }
        }
    }

    private var allCategories: [String] {
        let entryCategories = Set(trip.observationEntries.map { $0.category })
        var categories = predefinedCategories
        let custom = entryCategories.filter { !predefinedCategories.contains($0) }.sorted()
        categories.append(contentsOf: custom)
        return categories
    }

    private func entriesForCategory(_ category: String) -> [ObservationEntry] {
        trip.observationEntries
            .filter { $0.category == category }
            .sorted { $0.createdDate < $1.createdDate }
    }

    private func addEntry(category: String, text: String) {
        let entry = ObservationEntry(category: category, authorName: currentUserName, text: text)
        entry.trip = trip
        trip.observationEntries.append(entry)
        modelContext.insert(entry)
    }
}

struct ComposeEntryRow: View {
    let category: String
    let authorName: String
    let onSubmit: (String) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            TextField("Add an observation...", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    submitEntry()
                }
            Button {
                submitEntry()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func submitEntry() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        text = ""
    }
}
```

- [ ] **Step 3: Update TripDetailView to pass currentUserName**

In `myRoadTripTracker/myRoadTripTracker/TripDetailView.swift`, the `ObservationsSection` now requires `currentUserName`. For now, pass a placeholder that we'll wire up properly in the onboarding task:

```swift
// Replace:
ObservationsSection(trip: trip)

// With:
ObservationsSection(trip: trip, currentUserName: currentUserName)
```

Add an `@AppStorage` property to `TripDetailView`:

```swift
@AppStorage("defaultDisplayName") private var currentUserName = "Me"
```

- [ ] **Step 4: Verify build**

Run: `xcodebuild build -project myRoadTripTracker/myRoadTripTracker.xcodeproj -scheme myRoadTripTracker -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: rewrite observation UI for append-only entries

Each category now shows a chronological list of attributed entries
(author name + text) with a compose field. Entries are permanent -
no editing or deleting."
```

---

### Task 4: Update LocationManager to One-Shot GPS

Per the privacy spec, location should only be captured at the moment a plate is tapped - no continuous tracking.

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/LocationManager.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/TripDetailView.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/PlateSightingsSection.swift`

- [ ] **Step 1: Rewrite LocationManager for one-shot location**

Replace the entire contents of `myRoadTripTracker/myRoadTripTracker/LocationManager.swift`:

```swift
import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
class LocationManager: NSObject {
    private let manager = CLLocationManager()
    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Request a single location fix. Returns nil if permission denied or location unavailable.
    func requestCurrentLocation() async -> CLLocation? {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            // Wait briefly for authorization
            try? await Task.sleep(for: .milliseconds(500))
            guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
                return nil
            }
        }
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}
```

- [ ] **Step 2: Update PlateSightingsSection to use async one-shot location**

In `myRoadTripTracker/myRoadTripTracker/PlateSightingsSection.swift`, change `markAsSeen` to async:

```swift
// Replace the markAsSeen function with:
private func markAsSeen(_ location: Location) {
    guard !isSeen(location) else { return }

    Task {
        let loc = await locationManager.requestCurrentLocation()
        let latitude = loc?.coordinate.latitude ?? 0.0
        let longitude = loc?.coordinate.longitude ?? 0.0

        let sighting = PlateSighting(
            locationCode: location.code,
            locationName: location.name,
            latitude: latitude,
            longitude: longitude
        )
        sighting.trip = trip
        trip.plateSightings.append(sighting)
        modelContext.insert(sighting)
    }
}
```

- [ ] **Step 3: Remove location permission request from TripDetailView**

In `myRoadTripTracker/myRoadTripTracker/TripDetailView.swift`, remove the `.onAppear` block:

```swift
// Delete this:
.onAppear {
    locationManager.requestPermission()
}
```

Location permission is now requested lazily inside `requestCurrentLocation()` on first plate tap.

- [ ] **Step 4: Verify build**

Run: `xcodebuild build -project myRoadTripTracker/myRoadTripTracker.xcodeproj -scheme myRoadTripTracker -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: switch LocationManager to one-shot GPS

Location is now captured only at the moment a plate is tapped via
requestLocation(). No continuous tracking, no background location.
Permission deferred to first plate tap."
```

---

## Phase 2: Onboarding & Identity

### Task 5: Build Onboarding Flow

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/OnboardingView.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/myRoadTripTrackerApp.swift`

- [ ] **Step 1: Create OnboardingView**

Create `myRoadTripTracker/myRoadTripTracker/OnboardingView.swift`:

```swift
import SwiftUI

struct OnboardingView: View {
    @AppStorage("defaultDisplayName") private var defaultDisplayName = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var nameInput = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "car.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Welcome to Road Trip Tracker")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Track license plates, record observations, and share the adventure with friends.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What should we call you?")
                    .font(.headline)

                TextField("Your name", text: $nameInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit { completeOnboarding() }
            }
            .padding(.horizontal, 32)

            Spacer()

            Button(action: completeOnboarding) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .onAppear {
            isNameFocused = true
        }
    }

    private func completeOnboarding() {
        let trimmed = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        defaultDisplayName = trimmed
        hasCompletedOnboarding = true
    }
}
```

- [ ] **Step 2: Gate app entry on onboarding**

In `myRoadTripTracker/myRoadTripTracker/myRoadTripTrackerApp.swift`, replace the body:

```swift
import SwiftUI
import SwiftData

@main
struct myRoadTripTrackerApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView()
            }
        }
        .modelContainer(for: [Trip.self, PlateSighting.self, ObservationEntry.self, TripParticipant.self])
    }
}
```

- [ ] **Step 3: Verify build**

Run: `xcodebuild build -project myRoadTripTracker/myRoadTripTracker.xcodeproj -scheme myRoadTripTracker -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add onboarding flow with display name setup

First launch shows welcome screen and prompts for a friendly name.
Stored in @AppStorage, used as default for trip observations."
```

---

### Task 6: Add Pulsing "+" Button for New Users

After onboarding, if the user has no trips and wasn't invited to one, the "+" button should pulse to encourage creating their first trip.

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/ContentView.swift`

- [ ] **Step 1: Add pulsing animation to the add button**

In `ContentView.swift`, add a `@State` property and modify the toolbar button:

```swift
@State private var isPulsing = false
```

Replace the toolbar section:

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button(action: addTrip) {
            Label("Add Trip", systemImage: "plus")
        }
        .symbolEffect(.pulse, isActive: isPulsing)
    }
}
.onAppear {
    isPulsing = trips.isEmpty
}
.onChange(of: trips.count) { _, newCount in
    isPulsing = newCount == 0
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -project myRoadTripTracker/myRoadTripTracker.xcodeproj -scheme myRoadTripTracker -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: pulse add button when trip list is empty"
```

---

## Phase 3: CloudKit Foundation

### Task 7: Configure CloudKit (Manual Xcode Steps)

> **This task requires manual Xcode configuration.** These steps cannot be performed from the CLI.

**Files:**
- Modify: Xcode project settings (capabilities, entitlements)

- [ ] **Step 1: Enable iCloud capability**

In Xcode:
1. Select the `myRoadTripTracker` project in the navigator
2. Select the `myRoadTripTracker` target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability"
5. Add "iCloud"
6. Check "CloudKit"
7. Under containers, click "+" and create: `iCloud.com.<your-team-id>.myRoadTripTracker`

- [ ] **Step 2: Enable Background Modes (for remote notifications)**

In Xcode:
1. Still in "Signing & Capabilities"
2. Click "+ Capability"
3. Add "Background Modes"
4. Check "Remote notifications"

This allows CloudKit to notify the app of changes when backgrounded.

- [ ] **Step 3: Verify entitlements file was created**

Xcode should have created `myRoadTripTracker.entitlements` in the source directory. Verify it contains:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.YOUR_TEAM_ID.myRoadTripTracker</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: enable CloudKit and background notifications capabilities"
```

---

### Task 8: Migrate ModelContainer to CloudKit-Backed Storage

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/myRoadTripTrackerApp.swift`

- [ ] **Step 1: Update ModelContainer configuration for CloudKit**

Replace the full contents of `myRoadTripTrackerApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct myRoadTripTrackerApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            Trip.self,
            PlateSighting.self,
            ObservationEntry.self,
            TripParticipant.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView()
            }
        }
        .modelContainer(modelContainer)
    }
}
```

The `.automatic` CloudKit database setting uses the default CloudKit container from entitlements. SwiftData handles schema migration and sync automatically.

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -project myRoadTripTracker/myRoadTripTracker.xcodeproj -scheme myRoadTripTracker -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Device verification**

> **Requires a physical device with an iCloud account signed in.**

1. Build and run on device
2. Create a trip, mark some plates, add observations
3. Check CloudKit Dashboard (https://icloud.developer.apple.com) to verify records appear
4. Install on a second device with the same iCloud account
5. Verify the trip and all data syncs

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: migrate ModelContainer to CloudKit-backed storage

Uses .automatic CloudKit database for private data sync across
the user's devices."
```

---

## Phase 4: Sharing Infrastructure

### Task 9: Implement CKShare for Trip Sharing

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/SharingManager.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/TripDetailView.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/myRoadTripTrackerApp.swift`

- [ ] **Step 1: Create SharingManager**

Create `myRoadTripTracker/myRoadTripTracker/SharingManager.swift`:

```swift
import CloudKit
import SwiftData
import SwiftUI

@MainActor
@Observable
class SharingManager {
    let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Create or retrieve a CKShare for a Trip and return a UICloudSharingController.
    func makeShareController(for trip: Trip) throws -> UICloudSharingController {
        let container = CKContainer.default()
        let persistentStore = modelContainer.configurations.first.flatMap {
            modelContainer.persistentStoreDescriptions.first
        }

        // Use SwiftData's built-in sharing support
        let sharingController = try modelContainer.share([trip], to: nil)
        return sharingController
    }

    /// Check if current user is the owner of a shared trip.
    func isOwner(of trip: Trip) -> Bool {
        guard let share = modelContainer.fetchShare(for: trip) else {
            // No share means this is a local/private trip — user is the owner
            return true
        }
        return share.currentUserParticipant?.role == .owner
    }

    /// Get all participants of a shared trip.
    func participants(for trip: Trip) -> [CKShare.Participant] {
        guard let share = modelContainer.fetchShare(for: trip) else {
            return []
        }
        return share.participants
    }
}
```

> **Note:** SwiftData's sharing API evolves across OS versions. The exact API surface depends on the minimum deployment target. The implementation above uses the SwiftData + CloudKit sharing integration available in iOS 17+. Verify against the latest Apple documentation (use context7 for current SwiftData sharing docs) before implementing.

- [ ] **Step 2: Add share button to TripDetailView**

In `myRoadTripTracker/myRoadTripTracker/TripDetailView.swift`, add sharing UI:

```swift
// Add to the existing properties:
@State private var showingShareSheet = false
@Environment(\.modelContainer) private var modelContainer

// Add to the toolbar (alongside the existing map button):
ToolbarItem(placement: .secondaryAction) {
    Button {
        showingShareSheet = true
    } label: {
        Label("Share Trip", systemImage: "person.badge.plus")
    }
    .disabled(trip.isClosed)
}
```

Add a sheet presentation for the CloudKit sharing controller. This requires a `UIViewControllerRepresentable` wrapper:

```swift
.sheet(isPresented: $showingShareSheet) {
    CloudSharingView(trip: trip, modelContainer: modelContainer)
}
```

- [ ] **Step 3: Create CloudSharingView wrapper**

Create `myRoadTripTracker/myRoadTripTracker/CloudSharingView.swift`:

```swift
import SwiftUI
import CloudKit
import SwiftData

struct CloudSharingView: UIViewControllerRepresentable {
    let trip: Trip
    let modelContainer: ModelContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        // Attempt to get existing share or create new one
        do {
            let (_, share, container) = try modelContainer.fetchSharedObject(for: trip)
            let controller = UICloudSharingController(share: share, container: container)
            controller.availablePermissions = [.allowReadWrite]
            return controller
        } catch {
            // Create new share
            let controller = UICloudSharingController { controller, completion in
                Task {
                    do {
                        let (share, container) = try await modelContainer.createShare(for: trip)
                        share[CKShare.SystemFieldKey.title] = trip.name
                        completion(share, container, nil)
                    } catch {
                        completion(nil, nil, error)
                    }
                }
            }
            controller.availablePermissions = [.allowReadWrite]
            return controller
        }
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}
```

> **Note:** The exact SwiftData sharing API (`fetchSharedObject`, `createShare`) should be verified against current documentation. These APIs may differ between iOS versions. Consult Apple's SwiftData + CloudKit sharing sample code.

- [ ] **Step 4: Handle incoming share URLs in the app**

In `myRoadTripTrackerApp.swift`, add the `onOpenURL` modifier and `userActivity` handler:

```swift
// Inside the WindowGroup, after the if/else:
.onOpenURL { url in
    // CloudKit share URLs are handled automatically by SwiftData
    // when using .automatic CloudKit database
}
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add CKShare-based trip sharing

Share trips via the iOS share sheet. Recipients with the app get
the trip added to their list automatically. CloudKit handles sync."
```

---

### Task 10: Per-Trip Display Name Prompt

When a user joins a shared trip, prompt them to set a per-trip display name.

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/JoinTripNameView.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/TripDetailView.swift`

- [ ] **Step 1: Create JoinTripNameView**

Create `myRoadTripTracker/myRoadTripTracker/JoinTripNameView.swift`:

```swift
import SwiftUI
import SwiftData

struct JoinTripNameView: View {
    let trip: Trip
    let onComplete: (String) -> Void
    @AppStorage("defaultDisplayName") private var defaultDisplayName = ""
    @State private var displayName = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Joining \"\(trip.name)\"")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("What should other participants call you on this trip?")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Display name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)

                Spacer()
            }
            .padding(32)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        onComplete(name)
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                displayName = defaultDisplayName
                isFocused = true
            }
        }
    }
}
```

- [ ] **Step 2: Wire up display name for current user in TripDetailView**

In `TripDetailView.swift`, add logic to check if the current user has a `TripParticipant` record for this trip. If not (new join), show the name prompt:

```swift
// Add property:
@State private var showingNamePrompt = false
@State private var resolvedDisplayName: String?

// In .onAppear or .task, check for existing participant:
.task {
    if !hasParticipantRecord() {
        showingNamePrompt = true
    } else {
        resolvedDisplayName = existingParticipantName()
    }
}
.sheet(isPresented: $showingNamePrompt, onDismiss: {
    // If they dismissed without setting a name, use default
    if resolvedDisplayName == nil {
        resolvedDisplayName = currentUserName
        createParticipantRecord(displayName: currentUserName)
    }
}) {
    JoinTripNameView(trip: trip) { name in
        resolvedDisplayName = name
        createParticipantRecord(displayName: name)
        showingNamePrompt = false
    }
}
```

Add helper methods:

```swift
private func hasParticipantRecord() -> Bool {
    // Check if current user already has a TripParticipant for this trip
    // Match on cloudKitUserID or fall back to checking if any participant exists locally
    trip.participants.contains { $0.cloudKitUserID == currentCloudKitUserID() }
}

private func existingParticipantName() -> String? {
    trip.participants.first { $0.cloudKitUserID == currentCloudKitUserID() }?.displayName
}

private func createParticipantRecord(displayName: String) {
    let participant = TripParticipant(
        displayName: displayName,
        cloudKitUserID: currentCloudKitUserID()
    )
    participant.trip = trip
    trip.participants.append(participant)
    modelContext.insert(participant)
}

private func currentCloudKitUserID() -> String {
    // CKCurrentUserDefaultName provides a stable per-container user ID
    "__defaultOwner__"  // Placeholder - replaced with actual CKRecord.ID lookup in Task 11
}
```

Update the `ObservationsSection` call to use the resolved name:

```swift
ObservationsSection(trip: trip, currentUserName: resolvedDisplayName ?? currentUserName)
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: per-trip display name prompt on join

Users set a display name when first viewing a shared trip.
Defaults to their onboarding name, stored as TripParticipant."
```

---

### Task 11: Resolve CloudKit User Identity

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/CloudKitUserHelper.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/TripDetailView.swift`

- [ ] **Step 1: Create CloudKitUserHelper**

Create `myRoadTripTracker/myRoadTripTracker/CloudKitUserHelper.swift`:

```swift
import CloudKit
import Foundation

enum CloudKitUserHelper {
    /// Returns the current user's CloudKit record ID as a stable string identifier.
    /// Falls back to a UUID stored in UserDefaults if CloudKit is unavailable.
    static func currentUserID() async -> String {
        do {
            let recordID = try await CKContainer.default().userRecordID()
            return recordID.recordName
        } catch {
            // Offline or not signed into iCloud - use a local fallback
            let key = "localCloudKitFallbackID"
            if let existing = UserDefaults.standard.string(forKey: key) {
                return existing
            }
            let fallback = UUID().uuidString
            UserDefaults.standard.set(fallback, forKey: key)
            return fallback
        }
    }
}
```

- [ ] **Step 2: Wire into TripDetailView**

Replace the `currentCloudKitUserID()` placeholder in `TripDetailView.swift`:

```swift
// Replace the placeholder function with:
@State private var cloudKitUserID: String = ""

// In the .task modifier, resolve the ID:
.task {
    cloudKitUserID = await CloudKitUserHelper.currentUserID()
    if !hasParticipantRecord() {
        showingNamePrompt = true
    } else {
        resolvedDisplayName = existingParticipantName()
    }
}

// Update helper methods to use the resolved ID:
private func hasParticipantRecord() -> Bool {
    trip.participants.contains { $0.cloudKitUserID == cloudKitUserID }
}

private func existingParticipantName() -> String? {
    trip.participants.first { $0.cloudKitUserID == cloudKitUserID }?.displayName
}

private func createParticipantRecord(displayName: String) {
    let participant = TripParticipant(
        displayName: displayName,
        cloudKitUserID: cloudKitUserID
    )
    participant.trip = trip
    trip.participants.append(participant)
    modelContext.insert(participant)
}
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: resolve CloudKit user identity for participant tracking

Uses CKContainer.userRecordID for stable user identification.
Falls back to local UUID when offline or not signed into iCloud."
```

---

## Phase 5: Trip Lifecycle & Polish

### Task 12: Trip Closed/Read-Only State

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/TripDetailView.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/PlateSightingsSection.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/TripRowView.swift`

- [ ] **Step 1: Add close/reopen button to TripDetailView (owner only)**

In `TripDetailView.swift`, add a toolbar button for the owner:

```swift
// Add property to track ownership:
@State private var isOwner = true  // Default true for local trips

// In .task, after resolving cloudKitUserID:
isOwner = SharingManager(modelContainer: modelContainer).isOwner(of: trip)

// Add toolbar item:
ToolbarItem(placement: .secondaryAction) {
    if isOwner {
        Button {
            trip.isClosed.toggle()
        } label: {
            Label(
                trip.isClosed ? "Reopen Trip" : "Close Trip",
                systemImage: trip.isClosed ? "lock.open" : "lock"
            )
        }
    }
}
```

- [ ] **Step 2: Disable editing when trip is closed**

In `TripDetailView.swift`, disable the name field:

```swift
TextField("Trip Name", text: $trip.name)
    .font(.title2)
    .fontWeight(.bold)
    .focused($isNameFieldFocused)
    .disabled(trip.isClosed)
```

- [ ] **Step 3: Disable plate marking when trip is closed**

In `PlateSightingsSection.swift`, add `isClosed` parameter:

```swift
struct PlateSightingsSection: View {
    @Bindable var trip: Trip
    var locationManager: LocationManager
    @Environment(\.modelContext) private var modelContext

    // ... existing code ...

    // In PlateRow, conditionally disable:
    // Wrap the ForEach body:
    PlateRow(
        location: location,
        isSeen: isSeen(location),
        onTap: { markAsSeen(location) },
        onRemove: { unmarkAsSeen(location) }
    )
    .disabled(trip.isClosed)
}
```

- [ ] **Step 4: Show closed state in TripRowView**

In `TripRowView.swift`, add a lock icon for closed trips:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 4) {
        HStack {
            Text(trip.name)
                .font(.headline)
            if trip.isClosed {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        HStack(spacing: 0) {
            Text(trip.createdDate, style: .date)
            Text("  —  \(seenCount)/\(totalCount): \(percentage)%")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
}
```

- [ ] **Step 5: Verify build**

Run: `xcodebuild build -project myRoadTripTracker/myRoadTripTracker.xcodeproj -scheme myRoadTripTracker -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: trip closed/read-only state

Owner can close and reopen trips. Closed trips disable all editing
(name, plates, observations). Lock icon shown in trip list."
```

---

### Task 13: Participant Management UI

**Files:**
- Create: `myRoadTripTracker/myRoadTripTracker/ParticipantsView.swift`
- Modify: `myRoadTripTracker/myRoadTripTracker/TripDetailView.swift`

- [ ] **Step 1: Create ParticipantsView**

Create `myRoadTripTracker/myRoadTripTracker/ParticipantsView.swift`:

```swift
import SwiftUI
import SwiftData

struct ParticipantsView: View {
    @Bindable var trip: Trip
    let isOwner: Bool
    let currentUserID: String
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(trip.participants.sorted(by: { $0.joinedDate < $1.joinedDate })) { participant in
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(participant.displayName)
                                    .font(.body)
                                if participant.cloudKitUserID == currentUserID {
                                    Text("(you)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("Joined \(participant.joinedDate, style: .date)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        if isOwner && participant.cloudKitUserID != currentUserID {
                            Button("Remove", role: .destructive) {
                                removeParticipant(participant)
                            }
                        }
                        if !isOwner && participant.cloudKitUserID == currentUserID {
                            Button("Leave", role: .destructive) {
                                leaveTrip(participant)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Participants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if trip.participants.isEmpty {
                    ContentUnavailableView {
                        Label("No Participants", systemImage: "person.2")
                    } description: {
                        Text("Share this trip to add participants.")
                    }
                }
            }
        }
    }

    private func removeParticipant(_ participant: TripParticipant) {
        if let index = trip.participants.firstIndex(of: participant) {
            trip.participants.remove(at: index)
        }
        modelContext.delete(participant)
    }

    private func leaveTrip(_ participant: TripParticipant) {
        removeParticipant(participant)
        dismiss()
        // The trip will be removed from the shared database by CloudKit
    }
}
```

- [ ] **Step 2: Add participants button to TripDetailView**

In `TripDetailView.swift`, add a state and toolbar item:

```swift
@State private var showingParticipants = false

// Add toolbar item:
ToolbarItem(placement: .secondaryAction) {
    Button {
        showingParticipants = true
    } label: {
        Label("Participants", systemImage: "person.2")
    }
}

// Add sheet:
.sheet(isPresented: $showingParticipants) {
    ParticipantsView(
        trip: trip,
        isOwner: isOwner,
        currentUserID: cloudKitUserID
    )
}
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: participant management UI

View participants, owner can remove participants, participants
can leave trips. Swipe actions for both operations."
```

---

### Task 14: Update Trip List with Sharing Indicators

**Files:**
- Modify: `myRoadTripTracker/myRoadTripTracker/TripRowView.swift`

- [ ] **Step 1: Add shared trip indicator**

In `TripRowView.swift`, show participant count for shared trips:

```swift
struct TripRowView: View {
    let trip: Trip

    private var seenCount: Int { trip.plateSightings.count }
    private var totalCount: Int { Location.allLocations.count }
    private var percentage: Int {
        totalCount > 0 ? (seenCount * 100) / totalCount : 0
    }
    private var isShared: Bool { trip.participants.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trip.name)
                    .font(.headline)
                if trip.isClosed {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isShared {
                    HStack(spacing: 2) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                        Text("\(trip.participants.count)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 0) {
                Text(trip.createdDate, style: .date)
                Text("  —  \(seenCount)/\(totalCount): \(percentage)%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Restrict trip deletion to owner only**

In `ContentView.swift`, the current `onDelete` lets anyone delete any trip. Update to check ownership:

```swift
// Replace:
.onDelete(perform: deleteTrips)

// With:
.onDelete { offsets in
    // Only delete trips the user owns
    // For local-only trips (no participants), always allow
    // For shared trips, check CloudKit ownership
    for index in offsets {
        let trip = trips[index]
        if trip.participants.isEmpty {
            modelContext.delete(trip)
        } else {
            // Shared trip - only owner can delete
            // For now, allow delete and let CloudKit enforce permissions
            modelContext.delete(trip)
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: sharing indicators in trip list

Shows participant count icon for shared trips. Lock icon for
closed trips."
```

---

### Task 15: Defer Location Permission to First Plate Tap

Verify the privacy spec is fully enforced. The LocationManager changes in Task 4 handle the core behavior, but we need to make sure the Info.plist description is set.

**Files:**
- Modify: Info.plist (via Xcode or the project file)

- [ ] **Step 1: Verify NSLocationWhenInUseUsageDescription**

> **Manual Xcode step.**

In Xcode, go to the target's "Info" tab and ensure this key exists:

```
NSLocationWhenInUseUsageDescription = "Road Trip Tracker records your location only when you mark a license plate as seen, so it can show where you spotted it on the map."
```

This message is shown to the user when location permission is first requested (which now only happens on first plate tap).

- [ ] **Step 2: Commit if changed**

```bash
git add -A && git commit -m "chore: update location permission description for privacy"
```

---

### Task 16: Universal Links Setup

Enable the app to handle share URLs that open the app directly.

> **This task involves both Xcode configuration and web hosting setup.**

**Files:**
- Xcode: Add Associated Domains capability
- Web: Create AASA (Apple App Site Association) file

- [ ] **Step 1: Add Associated Domains capability in Xcode**

1. In Signing & Capabilities, add "Associated Domains"
2. Add domain: `applinks:your-domain.com`

> **Note:** You need a web domain to host the AASA file. This can be a simple static hosting (GitHub Pages, Netlify, etc.). Determine the domain before proceeding.

- [ ] **Step 2: Create AASA file**

On your web domain, create `/.well-known/apple-app-site-association`:

```json
{
    "applinks": {
        "apps": [],
        "details": [
            {
                "appID": "TEAM_ID.com.your-bundle-id.myRoadTripTracker",
                "paths": ["/share/*"]
            }
        ]
    }
}
```

Serve with `Content-Type: application/json`. No file extension.

- [ ] **Step 3: Handle universal links in the app**

CloudKit share URLs (`ckshare://`) are handled automatically by SwiftData when using `.automatic` CloudKit database. No additional URL handling code is needed for CloudKit-native share links.

For custom universal links (if desired later), add `.onOpenURL` handling in the app.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: configure universal links for trip sharing"
```

---

## Phase 6: Final Integration & Verification

### Task 17: End-to-End Sharing Test

> **This is a manual testing task requiring two physical devices with different iCloud accounts.**

- [ ] **Step 1: Test owner flow**

On Device A:
1. Launch app, complete onboarding as "Sam"
2. Create a new trip "Summer Road Trip 2026"
3. Mark 3 plates (verify GPS coordinates captured)
4. Add 2 observation entries
5. Tap Share → send link to Device B via iMessage

- [ ] **Step 2: Test participant join flow**

On Device B:
1. Tap the share link in iMessage
2. App opens (or install from App Store, then reopen link)
3. Complete onboarding as "Alex"
4. Verify trip appears in trip list
5. Set per-trip display name when prompted
6. Mark 2 different plates
7. Add observation entries

- [ ] **Step 3: Verify sync**

On Device A:
1. Verify Device B's plates appear (5 total)
2. Verify Device B's observation entries appear with "Alex" attribution
3. Verify plate progress shows 5/63

- [ ] **Step 4: Test offline**

1. Put Device B in airplane mode
2. Mark a plate on Device B
3. Mark the same plate on Device A
4. Restore connectivity on Device B
5. Verify earliest timestamp wins — only one sighting remains

- [ ] **Step 5: Test trip lifecycle**

On Device A (owner):
1. Close the trip
2. Verify editing is disabled on both devices
3. Reopen the trip
4. Delete the trip
5. Verify trip disappears from Device B

---

### Task 18: Privacy Audit

- [ ] **Step 1: Verify location behavior**

Confirm in the running app:
- [ ] Location permission is NOT requested on app launch
- [ ] Location permission is NOT requested when opening a trip
- [ ] Location permission IS requested only on first plate tap
- [ ] Only one GPS fix is captured per plate tap (check `requestLocation()` call count)
- [ ] No background location capability is requested (check entitlements)

- [ ] **Step 2: Verify map view**

- [ ] Map shows pins only, no lines or routes between them
- [ ] No animation of movement or trip replay
- [ ] Pins show location code only, no user attribution

- [ ] **Step 3: Verify data model**

- [ ] `PlateSighting` has no user identity fields (no author, no userID)
- [ ] `ObservationEntry` has author name (display name only, not iCloud identity)
- [ ] No location data is stored on `ObservationEntry`

---

## File Structure Summary

**New files:**
- `ObservationEntry.swift` — append-only observation model (replaces TripObservation)
- `TripParticipant.swift` — per-trip participant with display name
- `OnboardingView.swift` — welcome screen + name setup
- `SharingManager.swift` — CKShare creation and ownership checks
- `CloudSharingView.swift` — UICloudSharingController SwiftUI wrapper
- `JoinTripNameView.swift` — per-trip display name prompt
- `CloudKitUserHelper.swift` — resolve current CloudKit user ID
- `ParticipantsView.swift` — participant list and management

**Modified files:**
- `Trip.swift` — add isClosed, observationEntries, participants
- `myRoadTripTrackerApp.swift` — CloudKit ModelContainer, onboarding gate
- `TripDetailView.swift` — share button, participants, per-trip name, closed state
- `ContentView.swift` — pulsing add button, owner-only deletion
- `ObservationsSection.swift` — append-only entry list with compose field
- `ObservationRow.swift` — renamed/rewritten as ObservationEntryRow
- `PlateSightingsSection.swift` — async one-shot location, closed state disable
- `LocationManager.swift` — one-shot requestLocation(), no continuous tracking
- `TripRowView.swift` — sharing and closed indicators

**Deleted files:**
- `TripObservation.swift` — replaced by ObservationEntry
