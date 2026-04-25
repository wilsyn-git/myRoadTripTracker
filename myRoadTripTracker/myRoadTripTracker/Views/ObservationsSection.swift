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
        ForEach(allCategories, id: \.self) { category in
            Section {
                let entries = entriesForCategory(category)
                if entries.isEmpty {
                    Text("No entries yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                ForEach(entries) { entry in
                    ObservationEntryRow(entry: entry, currentUserName: currentUserName) {
                        entry.imageData = nil
                        entry.thumbnailData = nil
                        viewContext.save(contextInfo: "removeObservationImage")
                    }
                }
                if !trip.isClosed {
                    ComposeEntryRow(category: category, authorName: currentUserName) { text, imageData, thumbnailData in
                        addEntry(category: category, text: text, imageData: imageData, thumbnailData: thumbnailData)
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
                    let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, !allCategories.contains(trimmed) {
                        addedCategories.append(trimmed)
                    }
                    newCategoryName = ""
                }
            }
        }
    }

    private var allCategories: [String] {
        let entries = trip.observationEntriesArray
        let entryCategories = Set(entries.map { $0.category })
        var categories = predefinedCategories
        let custom = entryCategories
            .union(addedCategories)
            .filter { !predefinedCategories.contains($0) }
            .sorted()
        categories.append(contentsOf: custom)
        return categories
    }

    private func entriesForCategory(_ category: String) -> [ObservationEntry] {
        trip.observationEntriesArray
            .filter { $0.category == category }
    }

    private func addEntry(category: String, text: String, imageData: Data? = nil, thumbnailData: Data? = nil) {
        // TODO: remove debug prefix after fixing image save
        let debugPrefix = "[img:\(imageData?.count ?? 0) thumb:\(thumbnailData?.count ?? 0)] "
        let entry = ObservationEntry(
            context: viewContext,
            category: category,
            authorName: currentUserName,
            text: debugPrefix + text,
            imageData: imageData,
            thumbnailData: thumbnailData
        )
        entry.trip = trip
        viewContext.save(contextInfo: "addObservation")
    }
}

struct ComposeEntryRow: View {
    let category: String
    let authorName: String
    let onSubmit: (String, Data?, Data?) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedImage {
                HStack {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Button("Remove", systemImage: "xmark.circle.fill") {
                        self.selectedImage = nil
                        self.selectedItem = nil
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                }
            }
            HStack {
                TextField("Add an observation...", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit { submitEntry() }

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
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImage == nil)
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedItem, matching: .images)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    selectedImage = uiImage
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                selectedImage = image
            }
            .ignoresSafeArea()
        }
    }

    private func submitEntry() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || selectedImage != nil else { return }

        var imageData: Data?
        var thumbnailData: Data?
        if let selectedImage, let processed = ImageProcessor.processImage(selectedImage) {
            imageData = processed.imageData
            thumbnailData = processed.thumbnailData
        }

        onSubmit(trimmed, imageData, thumbnailData)
        text = ""
        selectedImage = nil
        selectedItem = nil
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
