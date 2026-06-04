import SwiftUI
import CoreData
import CoreLocation

enum PlateFilter: String, CaseIterable {
    case all = "All"
    case notSeen = "Not Seen"
}

// MARK: - PlateSightingsGrid

struct PlateSightingsGrid: View {
    @ObservedObject var trip: Trip
    var locationManager: LocationManager
    var plateFilter: PlateFilter = .all
    var currentUserName: String
    @Environment(\.managedObjectContext) private var viewContext
    @State private var recordingCodes: Set<String> = []
    @State private var revealingCodes: Set<String> = []
    @State private var sightingToInspect: PlateSighting?

    private var sightings: [PlateSighting] {
        trip.plateSightingsArray
    }

    private func filtered(_ locations: [Location], seenCodes: Set<String>) -> [Location] {
        switch plateFilter {
        case .all:
            return locations
        case .notSeen:
            return locations.filter { !seenCodes.contains($0.code) }
        }
    }

    private func isSeen(_ location: Location) -> Bool {
        sightings.contains { $0.locationCode == location.code }
    }

    private func sighting(for location: Location) -> PlateSighting? {
        sightings.first { $0.locationCode == location.code }
    }

    var body: some View {
        // Build the seen-code lookup once per render so each tile does an O(1) membership
        // check instead of scanning every sighting.
        let seenCodes = Set(sightings.map(\.locationCode))

        ScrollView {
            VStack(spacing: 16) {
                if trip.isClosed {
                    closedTripBanner
                }
                sectionView(title: "US States & DC", locations: Location.usStates, seenCodes: seenCodes)
                sectionView(title: "Canada", locations: Location.canadaLocations, seenCodes: seenCodes)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .sheet(item: $sightingToInspect) { sighting in
            PlateSightingDetailSheet(sighting: sighting, trip: trip)
        }
    }

    private var closedTripBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
            Text("Trip closed \u{2014} read only")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray5), in: Capsule())
    }

    private func sectionView(title: String, locations: [Location], seenCodes: Set<String>) -> some View {
        let visible = filtered(locations, seenCodes: seenCodes)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: title, locations: locations, seenCodes: seenCodes)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(visible) { location in
                    PlateTileView(
                        location: location,
                        isSeen: seenCodes.contains(location.code),
                        isRecording: recordingCodes.contains(location.code),
                        isRevealing: revealingCodes.contains(location.code),
                        onTapUnseen: { markAsSeen(location) },
                        onTapSeen: { sightingToInspect = sighting(for: location) }
                    )
                    .contextMenu {
                        if seenCodes.contains(location.code), !trip.isClosed {
                            Button("Remove sighting", role: .destructive) {
                                unmarkAsSeen(location)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(title: String, locations: [Location], seenCodes: Set<String>) -> some View {
        let seen = locations.filter { seenCodes.contains($0.code) }.count
        let total = locations.count
        let progress = total > 0 ? Double(seen) / Double(total) : 0

        return VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(seen)/\(total)")
                    .fontWeight(.semibold)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.96, green: 0.62, blue: 0.04),
                                    Color(red: 0.98, green: 0.75, blue: 0.15)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 3)
        }
    }

    private func markAsSeen(_ location: Location) {
        guard !trip.isClosed, !isSeen(location), !recordingCodes.contains(location.code) else { return }

        recordingCodes.insert(location.code)

        Task {
            let loc = await locationManager.requestCurrentLocation()
            let latitude = loc?.coordinate.latitude ?? 0.0
            let longitude = loc?.coordinate.longitude ?? 0.0

            recordingCodes.remove(location.code)
            revealingCodes.insert(location.code)

            let sighting = PlateSighting(
                context: viewContext,
                locationCode: location.code,
                locationName: location.name,
                latitude: latitude,
                longitude: longitude,
                spottedByName: currentUserName
            )
            sighting.trip = trip
            viewContext.save(contextInfo: "markAsSeen")

            try? await Task.sleep(for: .milliseconds(800))
            revealingCodes.remove(location.code)
        }
    }

    private func unmarkAsSeen(_ location: Location) {
        guard let sighting = sightings.first(where: { $0.locationCode == location.code }) else { return }
        viewContext.delete(sighting)
        viewContext.save(contextInfo: "unmarkAsSeen")
    }
}

// MARK: - PlateTileView

struct PlateTileView: View {
    let location: Location
    let isSeen: Bool
    let isRecording: Bool
    let isRevealing: Bool
    let onTapUnseen: () -> Void
    let onTapSeen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tileScale: CGFloat = 1.0
    @State private var grayscaleAmount: Double = 1.0
    @State private var showCheckmark = false
    @State private var showBurst = false
    @State private var trimEnd: CGFloat = 0

    var body: some View {
        Button {
            if isSeen {
                onTapSeen()
            } else if !isRecording && !isRevealing {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.easeInOut(duration: 0.08)) {
                    tileScale = 0.95
                }
                onTapUnseen()
            }
        } label: {
            tileContent
        }
        .buttonStyle(.plain)
        .scaleEffect(tileScale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(location.name), \(isSeen ? "seen" : "not seen")")
        .accessibilityHint("Double-tap to \(isSeen ? "view details" : "mark as seen")")
        .onChange(of: isRecording) { _, recording in
            if recording {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    trimEnd = 1
                }
            } else {
                withAnimation(.default) {
                    trimEnd = 0
                }
            }
        }
        .onChange(of: isRevealing) { _, revealing in
            if revealing {
                playRevealAnimation()
            }
        }
        .onAppear {
            if isSeen {
                grayscaleAmount = 0
                showCheckmark = true
            }
        }
        .onChange(of: isSeen) { _, seen in
            if !seen {
                showCheckmark = false
                grayscaleAmount = 1.0
                tileScale = 1.0
            }
        }
    }

    private var tileContent: some View {
        VStack(spacing: 2) {
            Image(location.flagImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 28)
                .clipShape(.rect(cornerRadius: 3))
                .grayscale(isSeen && !isRevealing ? 0 : grayscaleAmount)

            Text(location.code)
                .font(.system(.caption, design: .monospaced))
                .bold()

            Text(location.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .aspectRatio(1.0 / 1.1, contentMode: .fit)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .opacity(isSeen || isRecording || isRevealing ? 1.0 : 0.45)
        .shadow(color: isSeen ? .black.opacity(0.06) : .clear, radius: 1, y: 1)
        .overlay(alignment: .topTrailing) {
            if showCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .offset(x: 3, y: -3)
            }
        }
        .overlay {
            if isRecording {
                RoundedRectangle(cornerRadius: 8)
                    .trim(from: 0, to: trimEnd)
                    .stroke(Color.blue, lineWidth: 2)
            }
        }
        .overlay {
            if showBurst {
                ConfettiBurstView()
                    .accessibilityHidden(true)
            }
        }
    }

    private func playRevealAnimation() {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.3)) {
                grayscaleAmount = 0
                showCheckmark = true
                tileScale = 1.0
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }

        withAnimation(.easeOut(duration: 0.25)) {
            grayscaleAmount = 0
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
            tileScale = 1.0
        }

        showBurst = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeIn(duration: 0.15)) {
                showCheckmark = true
            }
            showBurst = false
        }
    }
}

// MARK: - ConfettiBurstView

struct ConfettiBurstView: View {
    @State private var animate = false

    private let particleCount = 8
    private let colors: [Color] = [
        Color(red: 0.96, green: 0.62, blue: 0.04),
        Color(red: 0.98, green: 0.75, blue: 0.15)
    ]

    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { index in
                let angle = Double(index) * (2 * .pi / Double(particleCount))
                Circle()
                    .fill(colors[index % 2])
                    .frame(width: 6, height: 6)
                    .scaleEffect(animate ? 1 : 0)
                    .offset(
                        x: animate ? cos(angle) * 24 : 0,
                        y: animate ? sin(angle) * 24 : 0
                    )
                    .opacity(animate ? 0 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animate = true
            }
        }
    }
}

// MARK: - PlateSightingDetailSheet

struct PlateSightingDetailSheet: View {
    let sighting: PlateSighting
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingRemoveAlert = false
    @State private var showingMap = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(sighting.flagImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 52)
                    .clipShape(.rect(cornerRadius: 4))

                Text("\(sighting.locationCode) — \(sighting.locationName)")
                    .font(.title3.bold())

                VStack(spacing: 4) {
                    if let date = sighting.seenDate {
                        Text("Spotted \(Text(date, style: .relative)) ago")
                            .font(.subheadline)
                    } else {
                        Text("Spotted recently")
                            .font(.subheadline)
                    }

                    if let name = sighting.spottedByName, !name.isEmpty {
                        Text("by \(name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if sighting.hasValidCoordinate {
                        Text(String(format: "%.4f, %.4f", sighting.latitude, sighting.longitude))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No location recorded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    if sighting.hasValidCoordinate {
                        Button {
                            showingMap = true
                        } label: {
                            Text("View on map")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if !trip.isClosed {
                        Button(role: .destructive) {
                            showingRemoveAlert = true
                        } label: {
                            Text("Remove")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(.top, 4)

                Spacer()
            }
            .padding()
            .navigationDestination(isPresented: $showingMap) {
                PlateSightingsMapView(sightings: [sighting], embedded: true)
            }
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.visible)
            .alert("Remove Sighting", isPresented: $showingRemoveAlert) {
                Button("Remove", role: .destructive) {
                    viewContext.delete(sighting)
                    viewContext.save(contextInfo: "removeSighting")
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Remove the \(sighting.locationName) plate sighting? This deletes the location data.")
            }
        }
    }
}
