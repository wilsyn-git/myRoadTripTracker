import SwiftUI

struct FullImageView: View {
    let imageData: Data?
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var didDecode = false

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else if didDecode {
                    ContentUnavailableView("Image Unavailable", systemImage: "photo")
                } else {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Decode once, off main, rather than in `body` on every render (#39).
            .task {
                image = await ImageProcessor.decodedForDisplay(imageData)
                didDecode = true
            }
        }
    }
}
