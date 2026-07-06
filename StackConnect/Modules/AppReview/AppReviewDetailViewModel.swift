import Foundation
import SwiftUI

// MARK: - Protocol

@MainActor
protocol AppReviewDetailViewModelProtocol: ObservableObject {
    var uiState: AppReviewDetailUiState { get set }
    func loadDetail() async
    func resubmit() async
    func discard() async
}

// MARK: - Action

enum AppReviewDetailAction: Identifiable {
    case resubmit
    case discard

    var id: String {
        switch self {
        case .resubmit: return "resubmit"
        case .discard:  return "discard"
        }
    }

    var title: String {
        switch self {
        case .resubmit: return String(localized: "Resubmit Submission")
        case .discard:  return String(localized: "Discard Submission")
        }
    }

    func message(version: String?) -> String {
        let v = version ?? "–"
        switch self {
        case .resubmit:
            return String(localized: "Are you sure you want to resubmit version \(v) for review?")
        case .discard:
            return String(localized: "Are you sure you want to discard the submission for version \(v)? This will remove it from App Review.")
        }
    }

    var confirmLabel: String {
        switch self {
        case .resubmit: return String(localized: "Resubmit")
        case .discard:  return String(localized: "Discard")
        }
    }

    var isDestructive: Bool {
        switch self {
        case .resubmit: return false
        case .discard:  return true
        }
    }
}

// MARK: - UiState

struct AppReviewDetailUiState {
    var submission: ReviewSubmissionModel
    var account: AccountModel
    var reviewDetail: AppReviewDetailModel?
    var isLoading = false
    var error: String?

    // Submission actions
    var isPerformingAction = false
    var actionError: String?
    var confirmAction: AppReviewDetailAction?
    var toastMessage: ToastMessage?
    var didComplete = false
}

// MARK: - Implementation

@MainActor
final class AppReviewDetailViewModel: AppReviewDetailViewModelProtocol {

    @Published var uiState: AppReviewDetailUiState

    private let keychain: KeyStorable

    init(
        submission: ReviewSubmissionModel,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AppReviewDetailUiState(submission: submission, account: account)
        self.keychain = keychain
    }

    func loadDetail() async {
        guard let versionId = uiState.submission.versionId else { return }

        uiState.isLoading = true
        uiState.error = nil

        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
                uiState.isLoading = false
                return
            }

            let connection = AppleAccountConnection(credentials: credentials)
            uiState.reviewDetail = try await connection.fetchAppReviewDetail(versionId: versionId)
            Log.print.info("[AppReviewDetail] Loaded review detail for version \(versionId)")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[AppReviewDetail] Failed to load review detail: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    // MARK: - Submission Actions

    func resubmit() async {
        uiState.isPerformingAction = true
        uiState.actionError = nil
        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
                uiState.isPerformingAction = false
                return
            }
            let connection = AppleAccountConnection(credentials: credentials)
            try await connection.submitReviewSubmission(id: uiState.submission.id)
            uiState.toastMessage = ToastMessage(String(localized: "Submission resubmitted"), icon: "paperplane.fill")
            Log.print.info("[AppReviewDetail] Resubmitted submission \(self.uiState.submission.id)")
            uiState.didComplete = true
        } catch {
            // Prefer the core's clean, actionable copy over `StackError`'s reflected
            // `errorDescription` when a submission can't be removed via the API.
            uiState.actionError = AppleAPIErrorTranslator.submissionNotRemovableMessage(error)
                ?? error.localizedDescription
            Log.print.error("[AppReviewDetail] Resubmit failed: \(error.localizedDescription)")
        }
        uiState.isPerformingAction = false
    }

    func discard() async {
        uiState.isPerformingAction = true
        uiState.actionError = nil
        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
                uiState.isPerformingAction = false
                return
            }
            let connection = AppleAccountConnection(credentials: credentials)
            try await connection.discardReviewSubmission(id: uiState.submission.id)
            uiState.toastMessage = ToastMessage(String(localized: "Submission discarded"), icon: "trash.fill")
            Log.print.info("[AppReviewDetail] Discarded submission \(self.uiState.submission.id)")
            uiState.didComplete = true
        } catch {
            // An empty READY_FOR_REVIEW draft can't be removed via the API. Show
            // the core's clean, actionable copy instead of `StackError`'s reflected
            // `errorDescription`; the existing error alert renders it fine.
            uiState.actionError = AppleAPIErrorTranslator.submissionNotRemovableMessage(error)
                ?? error.localizedDescription
            Log.print.error("[AppReviewDetail] Discard failed: \(error.localizedDescription)")
        }
        uiState.isPerformingAction = false
    }
}
