import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol AppHistoryViewModelProtocol: ObservableObject {
    var uiState: AppHistoryUiState { get set }
    func load() async
    func refresh() async
}

// MARK: - UiState

struct AppHistoryUiState {
    var appId: String
    var account: AccountModel
    var groups: [AppHistoryGroup] = []
    var isLoading = false
    var error: String?
}

struct AppHistoryGroup: Identifiable {
    let id: String
    var versionString: String
    var platform: AppPlatform?
    var entries: [AppHistoryEntry]
}

struct AppHistoryEntry: Identifiable {
    let id: String
    var activity: String
    var actorName: String?
    var date: Date?
    var status: String
    var statusColor: AppStoreStateColor
}

// MARK: - Implementation

@MainActor
final class AppHistoryViewModel: AppHistoryViewModelProtocol {

    @Published var uiState: AppHistoryUiState

    private let keychain: KeyStorable
    private let analytics: AnalyticsTracking

    init(
        appId: String,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = AppHistoryUiState(appId: appId, account: account)
        self.keychain = keychain
        self.analytics = analytics
    }

    func load() async {
        _ = await performLoad()
    }

    /// Pull-to-refresh: same load, tracked as a `refresh` action with its outcome.
    func refresh() async {
        let succeeded = await performLoad()
        analytics.track(.action(.refresh, on: .appHistory, result: succeeded ? .success : .failure))
    }

    private func performLoad() async -> Bool {
        var succeeded = true
        uiState.isLoading = true
        uiState.error = nil

        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
                uiState.isLoading = false
                return false
            }

            let connection = AppleAccountConnection(credentials: credentials)

            async let versionsResult = connection.fetchAppStoreVersions(appId: uiState.appId, limit: 200)
            async let submissionsResult = connection.fetchReviewSubmissions(appId: uiState.appId)

            let versions = try await versionsResult
            let submissions = (try? await submissionsResult) ?? []

            uiState.groups = buildGroups(versions: versions, submissions: submissions)

            Log.print.info("[AppHistory] Loaded \(versions.count) versions, \(submissions.count) submissions")
        } catch {
            succeeded = false
            uiState.error = error.userFacingMessage
            Log.print.error("[AppHistory] Failed to load: \(error.localizedDescription)")
        }

        uiState.isLoading = false
        return succeeded
    }

    // MARK: - Private

    private func buildGroups(
        versions: [AppStoreVersionModel],
        submissions: [ReviewSubmissionModel]
    ) -> [AppHistoryGroup] {
        AppHistoryTimelineBuilder.buildGroups(
            versions: versions,
            submissions: submissions,
            activityName: activityName(for:),
            submissionActivity: submissionActivity(for:)
        )
    }

    private func activityName(for state: AppStoreState) -> String {
        switch state {
        case .readyForSale:                return String(localized: "Released to App Store")
        case .prepareForSubmission:        return String(localized: "Preparing for Submission")
        case .waitingForReview:            return String(localized: "Waiting for Review")
        case .inReview:                    return String(localized: "In Review")
        case .pendingDeveloperRelease:     return String(localized: "Pending Developer Release")
        case .pendingAppleRelease:         return String(localized: "Pending Apple Release")
        case .rejected:                    return String(localized: "Rejected by App Review")
        case .metadataRejected:            return String(localized: "Metadata Rejected")
        case .developerRejected:           return String(localized: "Developer Rejected")
        case .removedFromSale:             return String(localized: "Removed from Sale")
        case .developerRemovedFromSale:    return String(localized: "Removed from Sale")
        case .replacedWithNewVersion:      return String(localized: "Replaced with New Version")
        case .processingForAppStore:       return String(localized: "Processing for App Store")
        case .readyForReview:              return String(localized: "Ready for Review")
        case .accepted:                    return String(localized: "Accepted")
        case .invalidBinary:               return String(localized: "Invalid Binary")
        case .pendingContract:             return String(localized: "Pending Contract")
        case .preorderReadyForSale:        return String(localized: "Pre-Order Ready")
        case .waitingForExportCompliance:  return String(localized: "Waiting for Export Compliance")
        case .notApplicable:               return String(localized: "Not Applicable")
        }
    }

    private func submissionActivity(for state: String?) -> String {
        switch state {
        case "WAITING_FOR_REVIEW": return String(localized: "Submitted for Review")
        case "IN_REVIEW":          return String(localized: "Review Started")
        case "COMPLETE":           return String(localized: "Review Completed")
        case "UNRESOLVED_ISSUES":  return String(localized: "Issues Found")
        case "CANCELING":          return String(localized: "Canceling Review")
        case "READY_FOR_REVIEW":   return String(localized: "Ready for Review")
        default:                   return String(localized: "Submitted for Review")
        }
    }
}

// MARK: - Timeline builder

/// Builds the per-version history timeline (newest first).
///
/// ASC exposes no timestamp for when a version *reached* its current
/// `appStoreState` — only its `createdDate`. The current-state entry used to be
/// stamped with `createdDate`, so "Released to App Store" showed the creation day
/// and sat above a later "Review Completed". It now carries no date and is pinned
/// on top as the current status, while every dated event (review submissions,
/// version creation) is ordered newest-first by its own timestamp.
enum AppHistoryTimelineBuilder {

    static func buildGroups(
        versions: [AppStoreVersionModel],
        submissions: [ReviewSubmissionModel],
        activityName: (AppStoreState) -> String,
        submissionActivity: (String?) -> String
    ) -> [AppHistoryGroup] {
        let sortedVersions = versions.sorted {
            ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast)
        }

        return sortedVersions.map { version in
            var events: [AppHistoryEntry] = submissions
                .filter { $0.versionId == version.id }
                .map { submission in
                    AppHistoryEntry(
                        id: "sub-\(submission.id)",
                        activity: submissionActivity(submission.state),
                        actorName: submission.submittedByName,
                        date: submission.submittedDate,
                        status: submission.stateDisplayName,
                        statusColor: submission.stateColor
                    )
                }

            events.append(AppHistoryEntry(
                id: "\(version.id)-created",
                activity: String(localized: "Version Created"),
                actorName: nil,
                date: version.createdDate,
                status: String(localized: "Created"),
                statusColor: .gray
            ))

            // Newest first; "Version Created" is appended last so it stays at the
            // bottom when a submission shares its exact timestamp (stable sort).
            let orderedEvents = events.enumerated()
                .sorted { lhs, rhs in
                    let lDate = lhs.element.date ?? .distantPast
                    let rDate = rhs.element.date ?? .distantPast
                    return lDate == rDate ? lhs.offset < rhs.offset : lDate > rDate
                }
                .map(\.element)

            var entries: [AppHistoryEntry] = []
            if let state = version.appStoreState {
                entries.append(AppHistoryEntry(
                    id: "\(version.id)-state",
                    activity: activityName(state),
                    actorName: nil,
                    date: nil,
                    status: state.displayName,
                    statusColor: state.color
                ))
            }
            entries.append(contentsOf: orderedEvents)

            return AppHistoryGroup(
                id: version.id,
                versionString: version.versionString ?? "–",
                platform: version.platform,
                entries: entries
            )
        }
    }
}
