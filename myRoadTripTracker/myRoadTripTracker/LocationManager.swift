//
//  LocationManager.swift
//  myRoadTripTracker
//
//  Created by Sam Grover on 3/5/26.
//

import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
class LocationManager: NSObject {
    private let manager = CLLocationManager()
    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Request a location fix, retrying over the given duration before giving up.
    func requestCurrentLocation(timeout: TimeInterval = 30) async -> CLLocation? {
        if authorizationStatus != .authorizedWhenInUse && authorizationStatus != .authorizedAlways {
            requestPermission()
            try? await Task.sleep(for: .milliseconds(500))
            guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
                return nil
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        var delay: Duration = .seconds(2)

        while Date() < deadline {
            let location = await withCheckedContinuation { continuation in
                locationContinuation = continuation
                manager.requestLocation()
            }
            if let location {
                return location
            }
            try? await Task.sleep(for: delay)
            delay = min(delay * 2, .seconds(8))
        }
        return nil
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}
