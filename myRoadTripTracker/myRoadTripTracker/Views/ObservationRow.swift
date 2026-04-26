import SwiftUI

struct ObservationEntryRow: View {
    @ObservedObject var entry: ObservationEntry
    var currentUserName: String = ""
    var onDeleteImage: (() -> Void)?
    @State private var showingFullImage = false

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
            if let thumbnailData = entry.thumbnailData, let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { showingFullImage = true }
            } else if entry.imageData != nil {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(height: 60)
            }
        }
        .padding(.vertical, 2)
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
}

struct FullImageView: View {
    let imageData: Data?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    ContentUnavailableView("Image Unavailable", systemImage: "photo")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
