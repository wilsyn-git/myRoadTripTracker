import UIKit

enum ImageProcessor {

    static func processImage(_ image: UIImage) -> (imageData: Data, thumbnailData: Data)? {
        guard let imageData = resized(image, maxEdge: 1024)?.jpegData(compressionQuality: 0.8),
              let thumbnailData = resized(image, maxEdge: 200)?.jpegData(compressionQuality: 0.6)
        else { return nil }

        return (imageData, thumbnailData)
    }

    private static func resized(_ image: UIImage, maxEdge: CGFloat) -> UIImage? {
        let size = image.size
        let longestEdge = max(size.width, size.height)
        guard longestEdge > maxEdge else { return image }

        let scale = maxEdge / longestEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
