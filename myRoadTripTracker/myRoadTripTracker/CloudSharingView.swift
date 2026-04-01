//
//  CloudSharingView.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/30/26.
//

import CloudKit
import CoreData
import LinkPresentation
import SwiftData
import SwiftUI

/// Activity item source that provides a CKShare URL with rich link metadata.
final class ShareActivityItem: NSObject, UIActivityItemSource {
    let url: URL
    let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.url = url
        return metadata
    }
}

/// Presents UIActivityViewController with a CKShare URL.
struct CloudSharingView: UIViewControllerRepresentable {
    let shareURL: URL
    let tripName: String
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let item = ShareActivityItem(url: shareURL, title: tripName)
        let controller = UIActivityViewController(
            activityItems: [item],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss()
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

/// ViewModifier that creates/fetches a CKShare then presents the standard share sheet.
/// Retries automatically if the trip hasn't synced to iCloud yet.
struct CloudSharingSheet: ViewModifier {
    let trip: Trip
    let persistenceController: PersistenceController
    @Binding var isPresented: Bool
    @State private var shareURL: URL?
    @State private var sharingError: String?
    @State private var showingError = false
    @State private var showingSheet = false
    @State private var isSyncing = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, shouldPresent in
                guard shouldPresent else { return }
                Task {
                    await prepareShare()
                }
            }
            .sheet(isPresented: $showingSheet, onDismiss: { isPresented = false }) {
                if let shareURL {
                    CloudSharingView(
                        shareURL: shareURL,
                        tripName: trip.name,
                        onDismiss: {
                            showingSheet = false
                        }
                    )
                }
            }
            .overlay {
                if isSyncing {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Syncing to iCloud...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .alert("Sharing Unavailable", isPresented: $showingError) {
                Button("OK") { sharingError = nil }
            } message: {
                Text(
                    sharingError
                        ?? "Unable to share this trip. Please make sure you're signed into iCloud and try again."
                )
            }
    }

    @MainActor
    private func prepareShare() async {
        isSyncing = true
        // Retry up to 5 times with 2-second delays to wait for CloudKit sync
        for attempt in 1...5 {
            do {
                let url = try await persistenceController.shareTrip(trip)
                isSyncing = false
                shareURL = url
                showingSheet = true
                return
            } catch is PersistenceController.SharingError where attempt < 5 {
                print("[CloudSharingSheet] Trip not synced yet, retrying in 2s (attempt \(attempt)/5)")
                try? await Task.sleep(for: .seconds(2))
            } catch {
                isSyncing = false
                isPresented = false
                sharingError = error.localizedDescription
                showingError = true
                return
            }
        }
        isSyncing = false
        isPresented = false
        sharingError = "Trip hasn't synced to iCloud yet. Please check your internet connection and try again in a moment."
        showingError = true
    }
}

extension View {
    func cloudSharingSheet(
        for trip: Trip, persistenceController: PersistenceController,
        isPresented: Binding<Bool>
    ) -> some View {
        modifier(
            CloudSharingSheet(
                trip: trip, persistenceController: persistenceController,
                isPresented: isPresented))
    }
}
