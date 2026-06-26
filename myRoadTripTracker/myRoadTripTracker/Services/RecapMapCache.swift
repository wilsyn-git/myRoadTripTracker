import CoreLocation
import CryptoKit
import UIKit

/// On-disk cache for rendered recap map images, keyed by a stable content hash of the
/// coordinates + render size. Lives in the Caches directory (OS-purgeable). Pins only.
enum RecapMapCache {

    private static let folderName = "RecapMaps"

    /// Stable, order-independent content key: SHA256 hex of the size + the coordinate list
    /// (fixed precision, sorted). Swift's built-in Hasher is per-process seeded and must NOT
    /// be used for a persistent filename.
    static func key(for coordinates: [CLLocationCoordinate2D], size: CGSize) -> String {
        let coordStrings = coordinates
            .map { String(format: "%.5f,%.5f", $0.latitude, $0.longitude) }
            .sorted()
        let content = "\(Int(size.width))x\(Int(size.height))|" + coordStrings.joined(separator: ";")
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func image(for key: String) -> UIImage? {
        guard let url = fileURL(for: key),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func store(_ image: UIImage, for key: String) {
        guard let url = fileURL(for: key),
              let data = image.pngData() else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    private static func fileURL(for key: String) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches
            .appendingPathComponent(folderName)
            .appendingPathComponent("recapMap-\(key).png")
    }
}
