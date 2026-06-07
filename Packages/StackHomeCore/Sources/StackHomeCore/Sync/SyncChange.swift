import Foundation

/// Changes detected during a sync that should surface as local "fake push"
/// notifications (status transitions and newly received user reviews).
///
/// Foundation-pure value type. It is produced by the core `SyncService`
/// pipeline and handed to the injected `SyncSideEffects` hook, whose iOS
/// implementation turns it into `UNUserNotificationCenter` local notifications
/// and whose default/Windows implementation ignores it.
public struct SyncChange: Sendable {

    public struct StatusChange: Sendable {
        public let accountId: String
        public let appId: String
        public let appName: String
        public let newState: AppStoreState

        public init(accountId: String, appId: String, appName: String, newState: AppStoreState) {
            self.accountId = accountId
            self.appId = appId
            self.appName = appName
            self.newState = newState
        }
    }

    public struct NewReview: Sendable {
        public let accountId: String
        public let appId: String
        public let appName: String
        public let reviewId: String

        public init(accountId: String, appId: String, appName: String, reviewId: String) {
            self.accountId = accountId
            self.appId = appId
            self.appName = appName
            self.reviewId = reviewId
        }
    }

    public var statusChanges: [StatusChange]
    public var newReviews: [NewReview]

    public init(statusChanges: [StatusChange] = [], newReviews: [NewReview] = []) {
        self.statusChanges = statusChanges
        self.newReviews = newReviews
    }

    public var isEmpty: Bool { statusChanges.isEmpty && newReviews.isEmpty }

    public static func + (lhs: SyncChange, rhs: SyncChange) -> SyncChange {
        SyncChange(
            statusChanges: lhs.statusChanges + rhs.statusChanges,
            newReviews: lhs.newReviews + rhs.newReviews
        )
    }
}
