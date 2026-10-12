import MapKit
import UIKit
import CoreLocation

/// Renders a static map image with pins for a trip's sightings. Pins only — no routes.
enum RecapMapRenderer {

    static func snapshot(for coordinates: [CLLocationCoordinate2D], size: CGSize) async -> UIImage? {
        guard !coordinates.isEmpty else { return nil }

        let cacheKey = RecapMapCache.key(for: coordinates, size: size)
        if let cached = await RecapMapCache.image(for: cacheKey) {
            return cached
        }

        let options = MKMapSnapshotter.Options()
        options.region = region(for: coordinates)
        options.size = size
        options.mapType = .standard

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await snapshotter.start()
            // Map points are read here; the drawing and the cache write happen off main (#39).
            let points = coordinates.map { snapshot.point(for: $0) }
            let image = await drawPins(at: points, on: snapshot.image, size: size)
            await RecapMapCache.store(image, for: cacheKey)
            return image
        } catch {
            #if DEBUG
            print("[RecapMapRenderer] snapshot failed: \(error)")
            #endif
            return nil
        }
    }

    private static func region(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        // NOTE: min/max longitude math wraps incorrectly across the antimeridian (~±180°).
        // Acceptable for North America road trips.
        var minLat = coords[0].latitude, maxLat = coords[0].latitude
        var minLon = coords[0].longitude, maxLon = coords[0].longitude
        for c in coords {
            minLat = min(minLat, c.latitude);  maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        // 1.6x padding, with sane minimums so a single point isn't fully zoomed in.
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.6, 2.0),
                                    longitudeDelta: max((maxLon - minLon) * 1.6, 2.0))
        return MKCoordinateRegion(center: center, span: span)
    }

    @concurrent
    private nonisolated static func drawPins(at points: [CGPoint],
                                             on mapImage: UIImage,
                                             size: CGSize) async -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            mapImage.draw(at: .zero)
            let imageSize = mapImage.size
            let cg = ctx.cgContext
            let pinRadius: CGFloat = 5
            for point in points {
                guard point.x >= 0, point.y >= 0, point.x <= imageSize.width, point.y <= imageSize.height else { continue }
                let rect = CGRect(x: point.x - pinRadius, y: point.y - pinRadius,
                                  width: pinRadius * 2, height: pinRadius * 2)
                cg.setFillColor(UIColor.systemRed.cgColor)
                cg.fillEllipse(in: rect)
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(1.5)
                cg.strokeEllipse(in: rect)
            }
        }
    }
}
