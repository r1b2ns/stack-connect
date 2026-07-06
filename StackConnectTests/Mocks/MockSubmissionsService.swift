import Foundation
import StackCoreRust
@testable import StackConnect

/// Test double for `SubmissionsServicing`. Returns canned submissions, can be
/// told to throw per-method, and records which IDs were discarded/submitted.
final class MockSubmissionsService: SubmissionsServicing {

    // MARK: - Canned results

    /// Returned by `fetchReviewSubmissions` (unless `fetchError` is set).
    var submissions: [ReviewSubmissionModel] = []

    // MARK: - Injected errors

    var fetchError: Error?
    var discardError: Error?
    var submitError: Error?

    // MARK: - Call recording

    private(set) var fetchedAppIds: [String] = []
    private(set) var discardedIds: [String] = []
    private(set) var submittedIds: [String] = []

    // MARK: - SubmissionsServicing

    func fetchReviewSubmissions(appId: String) async throws -> [ReviewSubmissionModel] {
        fetchedAppIds.append(appId)
        if let fetchError {
            throw fetchError
        }
        return submissions
    }

    func submitReviewSubmission(id: String) async throws {
        submittedIds.append(id)
        if let submitError {
            throw submitError
        }
    }

    func discardReviewSubmission(id: String) async throws {
        discardedIds.append(id)
        if let discardError {
            throw discardError
        }
    }
}
