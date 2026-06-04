import SwiftUI
import CoreData
import PhotosUI

struct ObservationsSection: View {
    @ObservedObject var trip: Trip
    let currentUserName: String
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var addedCategories: [String] = []

    private let predefinedCategories = [
        "Weirdest thing we've seen",
        "Coolest car",
        "Funniest billboard",
        "Weirdest billboard",
        "Best roadside attraction",
        "Most interesting license plate",
    ]

    var body: some View {
        // Group entries by category once instead of re-filtering the full list per section.
        let entries = trip.observationEntriesArray
        let grouped = Dictionary(grouping: entries, by: \.category)

        ForEach(categories(from: entries), id: \.self) { category in
            Section {
                let categoryEntries = grouped[category] ?? []
                if categoryEntries.isEmpty {
                    Text("No entries yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                ForEach(categoryEntries) { entry in
                    ObservationEntryRow(entry: entry, currentUserName: currentUserName) {
                        entry.imageData = nil
                        entry.thumbnailData = nil
                        viewContext.save(contextInfo: "removeObservationImage")
                    }
                }
                if !trip.isClosed {
                    ComposeEntryRow(
                        trip: trip,
                        category: category,
                        authorName: currentUserName
                    )
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
                    let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, !categories(from: trip.observationEntriesArray).contains(trimmed) {
                        addedCategories.append(trimmed)
                    }
                    newCategoryName = ""
                }
            }
        }
    }

    private func categories(from entries: [ObservationEntry]) -> [String] {
        let entryCategories = Set(entries.map(\.category))
        var categories = predefinedCategories
        let custom = entryCategories
            .union(addedCategories)
            .filter { !predefinedCategories.contains($0) }
            .sorted()
        categories.append(contentsOf: custom)
        return categories
    }
}

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

struct CameraPicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, dismiss: dismiss)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImagePicked: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImagePicked = onImagePicked
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
