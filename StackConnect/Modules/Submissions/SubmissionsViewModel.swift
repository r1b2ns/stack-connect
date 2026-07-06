import Foundation

// MARK: - Protocol

@MainActor
protocol SubmissionsViewModelProtocol: ObservableObject {
    var uiState: SubmissionsUiState { get set }
    func load() async
    func discard(_ submission: ReviewSubmissionModel) async
    func submit(_ submission: ReviewSubmissionModel) async
}

// MARK: - Pending confirmation

/// A destructive/edit action awaiting user confirmation. Mirrors the
/// `confirmAction` pattern used by `AppReviewDetailViewModel`.
enum SubmissionsPendingAction: Identifiable {
    case discard(ReviewSubmissionModel)
    case submit(ReviewSubmissionModel)

    var id: String {
        switch self {
        case .discard(let s): return "discard-\(s.id)"
        case .submit(let s):  return "submit-\(s.id)"
        }
    }

    var submission: ReviewSubmissionModel {
        switch self {
        case .discard(let s): return s
        case .submit(let s):  return s
        }
    }

    var title: String {
        switch self {
        case .discard: return String(localized: "Discard Submission")
        case .submit:  return String(localized: "Submit for Review")
        }
    }

    var confirmLabel: String {
        switch self {
        case .discard: return String(localized: "Discard")
        case .submit:  return String(localized: "Submit")
        }
    }

    var isDestructive: Bool {
        switch self {
        case .discard: return true
        case .submit:  return false
        }
    }

    func message(version: String?) -> String {
        let v = version ?? "–"
        switch self {
        case .discard:
            return String(localized: "Are you sure you want to discard the submission for version \(v)? This frees one of Apple's \(AppStoreReviewLimits.concurrentSubmissions) concurrent review slots.")
        case .submit:
            return String(localized: "Are you sure you want to submit version \(v) for review?")
        }
    }
}

// MARK: - UiState

struct SubmissionsUiState {
    var appId: String
    var appName: String?
    var account: AccountModel
    var submissions: [ReviewSubmissionModel] = []
    var isLoading = false
    var error: String?
    /// IDs of submissions with an in-flight discard/submit, so the row can show
    /// a spinner and disable further taps.
    var busyIds: Set<String> = []
    var toastMessage: ToastMessage?
    var pendingAction: SubmissionsPendingAction?

    /// Apple's hard limit on concurrent (unfinished) review submissions per app.
    let concurrentLimit = AppStoreReviewLimits.concurrentSubmissions

    /// Unfinished drafts — the ones that can be submitted or discarded to free a slot.
    var drafts: [ReviewSubmissionModel] {
        submissions.filter { $0.state == "READY_FOR_REVIEW" }
    }

    /// How many submissions currently count against Apple's concurrency limit.
    ///
    /// Heuristic: everything that is not terminal counts. Apple only frees a slot
    /// once a submission reaches `COMPLETE`, so we treat any non-`COMPLETE` state
    /// (drafts, waiting, in-review, canceling, completing, unresolved issues) as
    /// occupying a slot. This intentionally over-counts rather than under-counts,
    /// so we warn the user before they hit the server-side 409.
    var concurrentCount: Int {
        submissions.filter { ($0.state ?? "") != "COMPLETE" }.count
    }

    var limitReached: Bool {
        concurrentCount >= concurrentLimit
    }
}

// MARK: - Implementation

@MainActor
final class SubmissionsViewModel: SubmissionsViewModelProtocol {

    @Published var uiState: SubmissionsUiState

    private let keychain: KeyStorable
    /// Injected service seam. When `nil`, a real `AppleAccountConnection` is
    /// resolved from keychain credentials on demand (see `resolveService`).
    private let injectedService: SubmissionsServicing?

    init(
        appId: String,
        appName: String?,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        service: SubmissionsServicing? = nil
    ) {
        self.uiState = SubmissionsUiState(
            appId: appId,
            appName: appName,
            account: account
        )
        self.keychain = keychain
        self.injectedService = service
    }

    // MARK: - Service resolution

    /// Returns the injected service (tests) or builds a real connection from the
    /// account's stored credentials. Sets `uiState.error` and returns `nil` when
    /// no credentials are available.
    private func resolveService() -> SubmissionsServicing? {
        if let injectedService {
            return injectedService
        }
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            uiState.error = String(localized: "No credentials found for this account.")
            Log.print.error("[Submissions] No credentials for account \(self.uiState.account.id)")
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }

    // MARK: - Load

    func load() async {
        uiState.isLoading = true
        uiState.error = nil

        guard let service = resolveService() else {
            uiState.isLoading = false
            return
        }

        do {
            let submissions = try await service.fetchReviewSubmissions(appId: uiState.appId)
            uiState.submissions = Self.sorted(submissions)
            Log.print.info("[Submissions] Loaded \(self.uiState.submissions.count) submissions for \(self.uiState.appId)")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[Submissions] Failed to load submissions: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    // MARK: - Actions

    func discard(_ submission: ReviewSubmissionModel) async {
        uiState.busyIds.insert(submission.id)
        defer { uiState.busyIds.remove(submission.id) }

        guard let service = resolveService() else { return }

        do {
            try await service.discardReviewSubmission(id: submission.id)
            uiState.toastMessage = ToastMessage(String(localized: "Submission discarded"), icon: "trash.fill")
            Log.print.info("[Submissions] Discarded submission \(submission.id)")
            await load()
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[Submissions] Discard failed: \(error.localizedDescription)")
        }
    }

    func submit(_ submission: ReviewSubmissionModel) async {
        uiState.busyIds.insert(submission.id)
        defer { uiState.busyIds.remove(submission.id) }

        guard let service = resolveService() else { return }

        do {
            try await service.submitReviewSubmission(id: submission.id)
            uiState.toastMessage = ToastMessage(String(localized: "Submission submitted"), icon: "paperplane.fill")
            Log.print.info("[Submissions] Submitted submission \(submission.id)")
            await load()
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[Submissions] Submit failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Sorting

    /// Drafts first (they are the actionable ones), then newest-submitted first,
    /// with never-submitted entries (nil date) sinking to the bottom of their group.
    private static func sorted(_ submissions: [ReviewSubmissionModel]) -> [ReviewSubmissionModel] {
        submissions.sorted { lhs, rhs in
            let lhsDraft = lhs.state == "READY_FOR_REVIEW"
            let rhsDraft = rhs.state == "READY_FOR_REVIEW"
            if lhsDraft != rhsDraft {
                return lhsDraft
            }
            return (lhs.submittedDate ?? .distantPast) > (rhs.submittedDate ?? .distantPast)
        }
    }
}
