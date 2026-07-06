import Foundation

/// Apple-imposed limits around the App Store review process.
///
/// Single source of truth so the same numbers don't drift across the
/// translator copy, the Submissions UI state, and the various confirmation
/// dialogs that reference them.
enum AppStoreReviewLimits {

    /// The maximum number of concurrent (unfinished) review submissions Apple
    /// allows per app. Once reached, "Submit for review" fails with a 409
    /// `CONCURRENT_REVIEW_SUBMISSION_LIMIT_EXCEEDED`.
    static let concurrentSubmissions = 5
}
