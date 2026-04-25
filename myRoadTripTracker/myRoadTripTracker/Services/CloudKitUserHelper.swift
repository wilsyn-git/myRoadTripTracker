import CloudKit
import Foundation

enum CloudKitUserHelper {
    /// Returns the current user's CloudKit record ID as a stable string identifier.
    /// Falls back to a UUID stored in UserDefaults if CloudKit is unavailable.
    static func currentUserID() async -> String {
        do {
            let recordID = try await CKContainer.default().userRecordID()
            return recordID.recordName
        } catch {
            // Offline or not signed into iCloud - use a local fallback
            let key = "localCloudKitFallbackID"
            if let existing = UserDefaults.standard.string(forKey: key) {
                return existing
            }
            let fallback = UUID().uuidString
            UserDefaults.standard.set(fallback, forKey: key)
            return fallback
        }
    }
}
