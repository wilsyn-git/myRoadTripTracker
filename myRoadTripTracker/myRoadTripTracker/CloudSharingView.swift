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
struct CloudSharingSheet: ViewModifier {
    let trip: Trip
    let persistenceController: PersistenceController
    @Binding var isPresented: Bool
    @State private var shareURL: URL?
    @State private var sharingError: String?
    @State private var showingError = false
    @State private var showingSheet = false

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
        do {
            let url = try await persistenceController.shareTrip(trip)
            shareURL = url
            showingSheet = true
        } catch {
            isPresented = false
            sharingError = error.localizedDescription
            showingError = true
        }
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
