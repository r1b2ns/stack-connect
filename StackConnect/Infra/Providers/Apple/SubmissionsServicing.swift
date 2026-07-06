import Foundation

/// Testable seam over the review-submission calls the Submissions module needs.
///
/// `AppleAccountConnection` already implements these three methods against the
/// Rust core; this protocol lets the `SubmissionsViewModel` depend on an
/// abstraction (Dependency Inversion) so tests can inject a mock instead of
/// hitting the network or the keychain.
///
/// The methods are declared as plain `async throws` (not `@MainActor`): the
/// concrete `AppleAccountConnection` is a `Sendable`, actor-agnostic type whose
/// methods are `nonisolated`. `@MainActor` ViewModels can still `await` them —
/// the call simply suspends off the main actor — matching how `AppReview*` and
/// `VersionDetail` already talk to the connection today.
protocol SubmissionsServicing {
    /// Returns ALL review submissions for the app, including unfinished drafts
    /// (`state == "READY_FOR_REVIEW"`), already sorted newest-first.
    func fetchReviewSubmissions(appId: String) async throws -> [ReviewSubmissionModel]

    /// Submits a `READY_FOR_REVIEW` draft for review.
    func submitReviewSubmission(id: String) async throws

    /// Discards/cancels a submission. For a `READY_FOR_REVIEW` draft this frees
    /// one of Apple's 5 concurrent-review slots (the fix for the 409
    /// `CONCURRENT_REVIEW_SUBMISSION_LIMIT_EXCEEDED`).
    func discardReviewSubmission(id: String) async throws
}

// MARK: - Conformance

/// `AppleAccountConnection` already exposes matching method signatures, so the
/// conformance is purely declarative — no new code, just the protocol adoption.
extension AppleAccountConnection: SubmissionsServicing {}
