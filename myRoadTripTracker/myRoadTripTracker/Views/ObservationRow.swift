import SwiftUI

struct ObservationEntryRow: View {
    @ObservedObject var entry: ObservationEntry
    var currentUserName: String = ""
    var onDeleteImage: (() -> Void)?
    @State private var showingFullImage = false
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.authorName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(entry.createdDate ?? Date(), style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if !entry.text.isEmpty {
                Text(entry.text)
                    .font(.body)
            }
            if let thumbnail {
                Button {
                    showingFullImage = true
                } label: {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                // .borderless keeps the tap target on the image only (not the whole List
                // row) and makes it a real, VoiceOver-actionable control.
                .buttonStyle(.borderless)
                .accessibilityLabel("View photo full screen")
            } else if entry.imageData != nil {
                // Placeholder while the thumbnail decodes off-main, and for entries that
                // have a full image but no thumbnail.
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(height: 60)
            }
        }
        .padding(.vertical, 2)
        .task(id: entry.thumbnailData) {
            thumbnail = await Self.decodedThumbnail(from: entry.thumbnailData)
        }
        .contextMenu {
            if entry.imageData != nil, entry.authorName == currentUserName {
                Button(role: .destructive) {
                    onDeleteImage?()
                } label: {
                    Label("Remove Image", systemImage: "trash")
                }
            }
        }
        .fullScreenCover(isPresented: $showingFullImage) {
            FullImageView(imageData: entry.imageData)
        }
    }

    /// Decode + bitmap-prepare the thumbnail off the main thread so scrolling the notes feed
    /// doesn't hitch. `preparingForDisplay()` forces the actual decode that `UIImage(data:)`
    /// otherwise defers to first display.
    private static func decodedThumbnail(from data: Data?) async -> UIImage? {
        guard let data else { return nil }
        return await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.preparingForDisplay()
        }.value
    }
}
