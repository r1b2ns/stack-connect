import Foundation

/// Changes detected during a sync that should surface as local "fake push"
/// notifications (status transitions and newly received user reviews).
struct SyncChange: Sendable {

    struct StatusChange: Sendable {
        let accountId: String
        let appId: String
        let appName: String
        let newState: AppStoreState
    }

    struct NewReview: Sendable {
        let accountId: String
        let appId: String
        let appName: String
        let reviewId: String
    }

    var statusChanges: [StatusChange] = []
    var newReviews: [NewReview] = []

    var isEmpty: Bool { statusChanges.isEmpty && newReviews.isEmpty }

    static func + (lhs: SyncChange, rhs: SyncChange) -> SyncChange {
        SyncChange(
            statusChanges: lhs.statusChanges + rhs.statusChanges,
            newReviews: lhs.newReviews + rhs.newReviews
        )
    }
}
