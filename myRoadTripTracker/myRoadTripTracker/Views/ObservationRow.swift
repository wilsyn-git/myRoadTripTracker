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
                // No fallback to `Date()` — an unknown time must not render as now.
                // Time alone for today; older notes add the date, so days on a long trip
                // don't look alike.
                if let createdDate = entry.createdDate {
                    Text(createdDate, format: Calendar.current.isDateInToday(createdDate)
                         ? .dateTime.hour().minute()
                         : .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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
            } else if entry.hasPhoto {
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
            // Decoded off main so scrolling the notes feed doesn't hitch.
            thumbnail = await ImageProcessor.decodedForDisplay(entry.thumbnailData)
        }
        .contextMenu {
            if entry.hasPhoto, entry.authorName == currentUserName {
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
}
