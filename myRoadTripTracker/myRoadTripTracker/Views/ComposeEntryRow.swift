import SwiftUI
import CoreData
import PhotosUI

struct ComposeEntryRow: View {
    @ObservedObject var trip: Trip
    let category: String
    let authorName: String
    @Environment(\.managedObjectContext) private var viewContext
    @State private var text = ""
    @FocusState private var isFocused: Bool
    @State private var selectedItem: PhotosPickerItem?
    @State private var attachment: Attachment?
    @State private var isLoadingImage = false
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var saveError: String?

    struct Attachment {
        let imageData: Data
        let thumbnailData: Data
        let preview: UIImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let saveError {
                Text("Save failed: \(saveError)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if let attachment {
                HStack {
                    Image(uiImage: attachment.preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Button("Remove", systemImage: "xmark.circle.fill") {
                        clearAttachment()
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                }
            } else if isLoadingImage {
                ProgressView("Loading photo...")
                    .font(.caption)
            }
            HStack {
                TextField("Add an observation...", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)

                Menu {
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                }

                Button("Submit", systemImage: "arrow.up.circle.fill") {
                    submitEntry()
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .disabled(isLoadingImage || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachment == nil))
            }
        }
        // Each Button gets its own tap target — without this, multiple Buttons in a
        // List row activate together on a single tap.
        .buttonStyle(.borderless)
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedItem, matching: .images)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            isLoadingImage = true
            Task {
                defer { isLoadingImage = false }
                guard let data = try? await newItem.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data),
                      let processed = ImageProcessor.processImage(uiImage) else { return }
                attachment = Attachment(
                    imageData: processed.imageData,
                    thumbnailData: processed.thumbnailData,
                    preview: uiImage
                )
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                guard let processed = ImageProcessor.processImage(image) else { return }
                attachment = Attachment(
                    imageData: processed.imageData,
                    thumbnailData: processed.thumbnailData,
                    preview: image
                )
            }
            .ignoresSafeArea()
        }
    }

    private func clearAttachment() {
        attachment = nil
        selectedItem = nil
    }

    private func submitEntry() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || attachment != nil else { return }

        saveError = nil
        let entry = ObservationEntry(
            context: viewContext,
            category: category,
            authorName: authorName,
            text: trimmed,
            imageData: attachment?.imageData,
            thumbnailData: attachment?.thumbnailData
        )
        entry.trip = trip

        do {
            try viewContext.trySave(contextInfo: "addObservation")
        } catch {
            let nsError = error as NSError
            saveError = "[\(nsError.domain) \(nsError.code)] \(nsError.localizedDescription)"
            return
        }

        text = ""
        clearAttachment()
    }
}
