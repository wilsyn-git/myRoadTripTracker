import ImageIO
import UIKit

/// Shrinks note photos to a 1024 px image (stored and synced) and a 200 px thumbnail.
///
/// Everything here runs off the main actor (#39). The target builds with MainActor
/// default isolation and approachable concurrency, so a plain `nonisolated async` function
/// would still run on the caller's actor; `@concurrent` is what moves the work off main.
nonisolated enum ImageProcessor {

    struct Processed: Sendable {
        let imageData: Data
        let thumbnailData: Data
        /// The 1024 px image, already decoded, for the compose row's preview.
        let preview: UIImage
    }

    /// From a photo's encoded data (the Photos picker). ImageIO decodes straight to the
    /// target sizes, so the full-resolution photo (up to 48 MP) is never decoded. If that
    /// fails, it falls back to a full decode and a redraw.
    @concurrent
    static func process(data: Data) async -> Processed? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let large = downsample(source, maxPixelSize: 1024),
           let small = downsample(source, maxPixelSize: 200),
           let imageData = UIImage(cgImage: large).jpegData(compressionQuality: 0.8),
           let thumbnailData = UIImage(cgImage: small).jpegData(compressionQuality: 0.6) {
            return Processed(imageData: imageData, thumbnailData: thumbnailData,
                             preview: UIImage(cgImage: large))
        }
        guard let image = UIImage(data: data) else { return nil }
        return redrawn(image)
    }

    /// From an already-decoded image (the camera).
    @concurrent
    static func process(image: UIImage) async -> Processed? {
        redrawn(image)
    }

    /// Decodes image data and forces the bitmap decode off main, so the first frame that
    /// shows it doesn't pay for it.
    @concurrent
    static func decodedForDisplay(_ data: Data?) async -> UIImage? {
        guard let data else { return nil }
        return UIImage(data: data)?.preparingForDisplay()
    }

    private static func downsample(_ source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,  // honor EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func redrawn(_ image: UIImage) -> Processed? {
        let large = resized(image, maxEdge: 1024)
        guard let imageData = large.jpegData(compressionQuality: 0.8),
              let thumbnailData = resized(image, maxEdge: 200).jpegData(compressionQuality: 0.6)
        else { return nil }
        return Processed(imageData: imageData, thumbnailData: thumbnailData, preview: large)
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
