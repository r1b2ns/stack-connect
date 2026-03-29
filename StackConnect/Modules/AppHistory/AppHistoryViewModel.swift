import Foundation

// MARK: - Protocol

@MainActor
protocol AppHistoryViewModelProtocol: ObservableObject {
    var uiState: AppHistoryUiState { get set }
    func load() async
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

    init(
        appId: String,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AppHistoryUiState(appId: appId, account: account)
        self.keychain = keychain
    }

    func load() async {
        uiState.isLoading = true
        uiState.error = nil

        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
                uiState.isLoading = false
                return
            }

            let connection = AppleAccountConnection(credentials: credentials)

            async let versionsResult = connection.fetchAppStoreVersions(appId: uiState.appId, limit: 200)
            async let submissionsResult = connection.fetchReviewSubmissions(appId: uiState.appId)

            let versions = try await versionsResult
            let submissions = (try? await submissionsResult) ?? []

            uiState.groups = buildGroups(versions: versions, submissions: submissions)

            Log.print.info("[AppHistory] Loaded \(versions.count) versions, \(submissions.count) submissions")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[AppHistory] Failed to load: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    // MARK: - Private

    private func buildGroups(
        versions: [AppStoreVersionModel],
        submissions: [ReviewSubmissionModel]
    ) -> [AppHistoryGroup] {
        let sortedVersions = versions.sorted {
            ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast)
        }

        return sortedVersions.map { version in
            var entries: [AppHistoryEntry] = []

            // Current state entry
            if let state = version.appStoreState {
                entries.append(AppHistoryEntry(
                    id: "\(version.id)-state",
                    activity: activityName(for: state),
                    actorName: nil,
                    date: version.createdDate,
                    status: state.displayName,
                    statusColor: state.color
                ))
            }

            // Review submission entries
            let versionSubmissions = submissions
                .filter { $0.versionId == version.id }
                .sorted { ($0.submittedDate ?? .distantPast) > ($1.submittedDate ?? .distantPast) }

            for submission in versionSubmissions {
                entries.append(AppHistoryEntry(
                    id: "sub-\(submission.id)",
                    activity: submissionActivity(for: submission.state),
                    actorName: submission.submittedByName,
                    date: submission.submittedDate,
                    status: submission.stateDisplayName,
                    statusColor: submission.stateColor
                ))
            }

            // Version created entry
            entries.append(AppHistoryEntry(
                id: "\(version.id)-created",
                activity: String(localized: "Version Created"),
                actorName: nil,
                date: version.createdDate,
                status: String(localized: "Created"),
                statusColor: .gray
            ))

            return AppHistoryGroup(
                id: version.id,
                versionString: version.versionString ?? "–",
                platform: version.platform,
                entries: entries
            )
        }
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
