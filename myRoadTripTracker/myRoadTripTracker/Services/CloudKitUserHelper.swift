import CloudKit
import Foundation

/// Who this phone's user is, as a stable ID for matching `TripParticipant`s.
enum CloudKitUserHelper {
    private static let recordNameKey = "cloudKitUserRecordName"
    private static let fallbackKey = "localCloudKitFallbackID"

    private static var container: CKContainer {
        CKContainer(identifier: PersistenceController.cloudKitContainerID)
    }

    /// The current user's ID, or nil when it can't be known right now.
    ///
    /// This is the CloudKit user record name. It's cached after the first successful fetch,
    /// so later calls are instant and work offline. Without an iCloud account, a UUID kept
    /// on this phone stands in; with no account there's no sharing, so nothing else needs
    /// to match it. Returns nil when iCloud is signed in but the name has never been fetched
    /// and CloudKit can't be reached. Callers must then not create or match participants:
    /// a guessed ID never matches the real one later (#36).
    static func currentUserID() async -> String? {
        if let cached = UserDefaults.standard.string(forKey: recordNameKey) {
            return cached
        }
        if let fetched = await refresh() {
            return fetched
        }
        guard (try? await container.accountStatus()) == .noAccount else { return nil }
        return localFallbackID()
    }

    /// Fetches the user record name from CloudKit and caches it; nil if the fetch fails.
    /// Run once per launch and on account changes, so a trip open never waits on it and a
    /// different iCloud account replaces the cached name.
    @discardableResult
    static func refresh() async -> String? {
        guard let recordName = try? await container.userRecordID().recordName else { return nil }
        UserDefaults.standard.set(recordName, forKey: recordNameKey)
        return recordName
    }

    /// Forgets the cached name, e.g. when the iCloud account changes.
    static func clearCache() {
        UserDefaults.standard.removeObject(forKey: recordNameKey)
    }

    private static func localFallbackID() -> String {
        if let existing = UserDefaults.standard.string(forKey: fallbackKey) {
            return existing
        }
        let fallback = UUID().uuidString
        UserDefaults.standard.set(fallback, forKey: fallbackKey)
        return fallback
    }
}
