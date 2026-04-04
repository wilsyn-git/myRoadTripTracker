import CloudKit
import CoreData
import LinkPresentation
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
    @ObservedObject var trip: Trip
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
                            Text("Preparing share...")
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
        do {
            let share = try await persistenceController.shareTrip(trip)
            isSyncing = false
            if let url = share.url {
                shareURL = url
                showingSheet = true
            } else {
                isPresented = false
                sharingError = "Failed to create share link. Please try again."
                showingError = true
            }
        } catch {
            isSyncing = false
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
