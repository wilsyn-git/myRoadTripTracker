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
    private var locationContinuations: [CheckedContinuation<CLLocation?, Never>] = []
    private var authorizationContinuations: [CheckedContinuation<CLAuthorizationStatus, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorizationStatus = manager.authorizationStatus
    }

    /// One fix for a tapped plate. Asks for When In Use permission the first time, then
    /// requests one fresh fix and gives up after `timeout`. Returns nil when permission is
    /// denied or no fix arrives in time.
    func requestFix(timeout: Duration) async -> CLLocation? {
        guard await ensureAuthorized() else { return nil }
        return await requestOneFix(timeout: timeout)
    }

    /// Whether location is already allowed; never prompts.
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// The phone's last known location when it is at most `maxAge` seconds old and accurate
    /// to `maxAccuracy` metres; nil otherwise, or when not authorized. Never prompts and
    /// starts no location request.
    func recentLocation(maxAge: TimeInterval, maxAccuracy: CLLocationAccuracy) -> CLLocation? {
        guard isAuthorized, let cached = manager.location,
              -cached.timestamp.timeIntervalSinceNow <= maxAge,
              cached.horizontalAccuracy >= 0, cached.horizontalAccuracy <= maxAccuracy else { return nil }
        return cached
    }

    /// One fix for a Siri request: never prompts for permission, gives up after `timeout`.
    /// Uses the phone's last known location when it is at most `maxCachedAge` old and
    /// accurate to `maxCachedAccuracy` metres, which is often instant in a moving car;
    /// otherwise asks for one fresh fix. Returns nil when not already authorized, when iOS
    /// won't locate a background launch, or on timeout; the caller then records `0,0`
    /// (privacy invariants, CLAUDE.md).
    func requestFixIfAuthorized(timeout: Duration,
                                maxCachedAge: TimeInterval = 300,
                                maxCachedAccuracy: CLLocationAccuracy = 1000) async -> CLLocation? {
        guard isAuthorized else { return nil }
        if let cached = recentLocation(maxAge: maxCachedAge, maxAccuracy: maxCachedAccuracy) {
            return cached
        }
        return await requestOneFix(timeout: timeout)
    }

    /// Asks CoreLocation for one fresh fix, giving up after `timeout`.
    private func requestOneFix(timeout: Duration) async -> CLLocation? {
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self.resumeLocationContinuations(with: nil)
        }
        let location = await withCheckedContinuation { continuation in
            locationContinuations.append(continuation)
            manager.requestLocation()
        }
        timeoutTask.cancel()
        return location
    }

    /// Drain and resume all pending location continuations exactly once.
    private func resumeLocationContinuations(with location: CLLocation?) {
        let pending = locationContinuations
        locationContinuations = []
        for continuation in pending {
            continuation.resume(returning: location)
        }
    }

    /// Ensure we hold when-in-use authorization. When the status is undetermined, prompt and
    /// await the user's actual decision via the delegate callback rather than guessing after a
    /// fixed delay.
    private func ensureAuthorized() async -> Bool {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        case .notDetermined:
            let status = await awaitAuthorizationDecision()
            return status == .authorizedWhenInUse || status == .authorizedAlways
        default: // .denied, .restricted — no dialog will appear; do not wait.
            return false
        }
    }

    /// Prompt for authorization and suspend until `locationManagerDidChangeAuthorization` reports the
    /// user's decision. A safety timeout resumes with the current status so a stuck dialog cannot hang.
    private func awaitAuthorizationDecision() async -> CLAuthorizationStatus {
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            self.resumeAuthorizationContinuations(with: self.authorizationStatus)
        }
        let status = await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
        timeoutTask.cancel()
        return status
    }

    /// Drain and resume all pending authorization continuations exactly once.
    private func resumeAuthorizationContinuations(with status: CLAuthorizationStatus) {
        let pending = authorizationContinuations
        authorizationContinuations = []
        for continuation in pending {
            continuation.resume(returning: status)
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            let continuations = self.locationContinuations
            self.locationContinuations = []
            for continuation in continuations {
                continuation.resume(returning: location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            let continuations = self.locationContinuations
            self.locationContinuations = []
            for continuation in continuations {
                continuation.resume(returning: nil)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Read the status here: the manager isn't Sendable, so it can't go into the task.
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            self.resumeAuthorizationContinuations(with: status)
        }
    }
}
