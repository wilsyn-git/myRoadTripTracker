import UIKit

enum ImageProcessor {

    static func processImage(_ image: UIImage) -> (imageData: Data, thumbnailData: Data)? {
        guard let imageData = resized(image, maxEdge: 1024).jpegData(compressionQuality: 0.8),
              let thumbnailData = resized(image, maxEdge: 200).jpegData(compressionQuality: 0.6)
        else { return nil }

        return (imageData, thumbnailData)
    }

    // Always go through the renderer with `.standard` range so the output
    // is 8-bit sRGB. JPEG cannot encode HDR/extended-range pixels, so a
    // direct `jpegData` call on a HDR source UIImage returns nil.
    private static func resized(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let size = image.size
        let longestEdge = max(size.width, size.height)
        let newSize: CGSize = longestEdge > maxEdge
            ? CGSize(width: size.width * (maxEdge / longestEdge),
                     height: size.height * (maxEdge / longestEdge))
            : size

        let format = UIGraphicsImageRendererFormat.default()
        format.preferredRange = .standard
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
