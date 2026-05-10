import Foundation
import SwiftUI
import AppStoreConnect_Swift_SDK

// MARK: - Protocol

@MainActor
protocol VersionDetailViewModelProtocol: ObservableObject {
    var uiState: VersionDetailUiState { get set }
    func refresh() async
    func updatePromotionalText() async throws
    func updateDescription() async throws
    func updateWhatsNew() async throws
    func saveGroupedFields() async
    func saveReleaseType() async
    func savePhasedRelease(usePhased: Bool) async
    func setPhasedReleasePaused(_ paused: Bool) async
    func submitForReview() async
    func cancelReview() async
    func releaseVersion() async
    func rejectVersion() async
    func completePhasedRelease() async
}

// MARK: - UiState

struct VersionDetailUiState {
    var version: AppStoreVersionModel
    var account: AccountModel
    var isLoading = false
    var localization: AppStoreLocalizationModel?
    var currentBuild: BuildModel?

    // Text editing sheets
    var showPromotionalText = false
    var showDescription = false
    var showWhatsNew = false
    var editPromotionalText = ""
    var editDescription = ""
    var editWhatsNew = ""

    // Grouped fields
    var editKeywords = ""
    var editSupportUrl = ""
    var editMarketingUrl = ""
    var editVersion = ""
    var editCopyright = ""
    var isSavingGroupedFields = false
    var groupedFieldsError: String?

    // Release sheet
    var showReleaseSheet = false
    var selectedReleaseType: VersionReleaseType = .manual
    var scheduledDate = Date()
    var isSavingRelease = false
    var releaseError: String?

    // Version actions
    var isPerformingAction = false
    var actionError: String?
    var confirmAction: VersionDetailAction?
    var toastMessage: ToastMessage?

    // Phased release
    var phasedRelease: PhasedReleaseModel?
    var showPhasedReleaseSheet = false
    var isSavingPhasedRelease = false
    var phasedReleaseError: String?

    var releaseTypeSubtitle: String {
        switch selectedReleaseType {
        case .manual:        return String(localized: "Manually release this version")
        case .afterApproval: return String(localized: "Automatically release this version")
        case .scheduled:     return String(localized: "Scheduled release")
        }
    }

    var phasedReleaseSubtitle: String {
        guard let phased = phasedRelease else {
            return String(localized: "Release to all users immediately")
        }
        switch phased.state {
        case .active:
            if let day = phased.currentDayNumber {
                return String(localized: "Phased release — Day \(day) of 7")
            }
            return String(localized: "Phased release — Active")
        case .paused:
            return String(localized: "Phased release — Paused")
        case .complete:
            return String(localized: "Phased release — Complete")
        case .inactive:
            return String(localized: "Phased release over 7-day period")
        case .none:
            return String(localized: "Phased release over 7-day period")
        }
    }
}

enum VersionReleaseType: String, CaseIterable, Identifiable {
    case manual
    case afterApproval
    case scheduled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:        return String(localized: "Manually release this version")
        case .afterApproval: return String(localized: "Automatically release this version")
        case .scheduled:     return String(localized: "Automatically release after App Review, no earlier than")
        }
    }

    var icon: String {
        switch self {
        case .manual:        return "hand.tap"
        case .afterApproval: return "checkmark.circle"
        case .scheduled:     return "calendar.badge.clock"
        }
    }
}

enum VersionDetailAction: Identifiable {
    case submitForReview
    case cancelReview
    case release
    case reject
    case completePhasedRelease

    var id: String {
        switch self {
        case .submitForReview:       return "submit"
        case .cancelReview:          return "cancel"
        case .release:               return "release"
        case .reject:                return "reject"
        case .completePhasedRelease: return "completePhasedRelease"
        }
    }

    var title: String {
        switch self {
        case .submitForReview:       return String(localized: "Submit for Review")
        case .cancelReview:          return String(localized: "Cancel Review")
        case .release:               return String(localized: "Release Version")
        case .reject:                return String(localized: "Reject Version")
        case .completePhasedRelease: return String(localized: "Release to All Users")
        }
    }

    func message(version: String?) -> String {
        let v = version ?? "–"
        switch self {
        case .submitForReview:
            return String(localized: "Are you sure you want to submit version \(v) for review?")
        case .cancelReview:
            return String(localized: "Are you sure you want to cancel the review for version \(v)?")
        case .release:
            return String(localized: "Are you sure you want to release version \(v) to the App Store?")
        case .reject:
            return String(localized: "Are you sure you want to reject version \(v)? This action cannot be undone.")
        case .completePhasedRelease:
            return String(localized: "Release version \(v) to all users now? This will end the phased release and make the update available to 100% of users.")
        }
    }

    var confirmLabel: String {
        switch self {
        case .submitForReview:       return String(localized: "Submit")
        case .cancelReview:          return String(localized: "Cancel Review")
        case .release:               return String(localized: "Release")
        case .reject:                return String(localized: "Reject")
        case .completePhasedRelease: return String(localized: "Release to All")
        }
    }

    var isDestructive: Bool {
        switch self {
        case .submitForReview, .release, .completePhasedRelease: return false
        case .cancelReview, .reject: return true
        }
    }
}

// MARK: - Implementation

@MainActor
final class VersionDetailViewModel: VersionDetailViewModelProtocol {

    @Published var uiState: VersionDetailUiState

    private let storage: PersistentStorable
    private let keychain: KeyStorable

    init(
        version: AppStoreVersionModel,
        account: AccountModel,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = VersionDetailUiState(version: version, account: account)
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
    }

    func refresh() async {
        uiState.isLoading = true

        guard let connection = createConnection() else {
            uiState.isLoading = false
            return
        }

        // Fetch version, localizations, build, and phased release in parallel
        async let versionsTask = connection.fetchAppStoreVersions(appId: uiState.version.appId, limit: 200)
        async let localizationsTask = connection.fetchLocalizations(versionId: uiState.version.id)
        async let buildTask = connection.fetchCurrentBuild(versionId: uiState.version.id)
        async let phasedTask = connection.fetchPhasedRelease(versionId: uiState.version.id)

        do {
            let allVersions = try await versionsTask
            if let updated = allVersions.first(where: { $0.id == self.uiState.version.id }) {
                uiState.version = updated
                try await storage.save(updated, id: "version.\(updated.id)")
            }
        } catch {
            Log.print.error("[VersionDetail] Version refresh failed: \(error.localizedDescription)")
        }

        do {
            let localizations = try await localizationsTask
            if let loc = localizations.first {
                uiState.localization = loc
                uiState.editPromotionalText = loc.promotionalText ?? ""
                uiState.editDescription = loc.description ?? ""
                uiState.editWhatsNew = loc.whatsNew ?? ""
                uiState.editKeywords = loc.keywords ?? ""
                uiState.editSupportUrl = loc.supportUrl ?? ""
                uiState.editMarketingUrl = loc.marketingUrl ?? ""
            }
        } catch {
            Log.print.error("[VersionDetail] Localizations fetch failed: \(error.localizedDescription)")
        }

        do {
            uiState.currentBuild = try await buildTask
        } catch {
            Log.print.error("[VersionDetail] Build fetch failed: \(error.localizedDescription)")
        }

        do {
            uiState.phasedRelease = try await phasedTask
        } catch {
            Log.print.error("[VersionDetail] Phased release fetch failed: \(error.localizedDescription)")
        }

        uiState.editVersion = uiState.version.versionString ?? ""
        uiState.editCopyright = uiState.version.copyright ?? ""

        // Map release type
        switch uiState.version.releaseType {
        case "AFTER_APPROVAL": uiState.selectedReleaseType = .afterApproval
        case "SCHEDULED":      uiState.selectedReleaseType = .scheduled
        default:               uiState.selectedReleaseType = .manual
        }

        uiState.isLoading = false
    }

    func updatePromotionalText() async throws {
        guard let locId = uiState.localization?.id else { return }
        let connection = createConnection()!
        try await connection.updateLocalization(id: locId, promotionalText: uiState.editPromotionalText)
        uiState.localization?.promotionalText = uiState.editPromotionalText
        Log.print.info("[VersionDetail] Updated promotional text")
    }

    func updateDescription() async throws {
        guard let locId = uiState.localization?.id else { return }
        let connection = createConnection()!
        try await connection.updateLocalization(id: locId, description: uiState.editDescription)
        uiState.localization?.description = uiState.editDescription
        Log.print.info("[VersionDetail] Updated description")
    }

    func updateWhatsNew() async throws {
        guard let locId = uiState.localization?.id else { return }
        let connection = createConnection()!
        try await connection.updateLocalization(id: locId, whatsNew: uiState.editWhatsNew)
        uiState.localization?.whatsNew = uiState.editWhatsNew
        Log.print.info("[VersionDetail] Updated what's new")
    }

    func saveGroupedFields() async {
        uiState.isSavingGroupedFields = true
        uiState.groupedFieldsError = nil

        guard let connection = createConnection() else {
            uiState.isSavingGroupedFields = false
            return
        }

        do {
            // Update localization fields (keywords, URLs) and version fields in parallel
            if let locId = uiState.localization?.id {
                async let locTask: () = connection.updateLocalization(
                    id: locId,
                    keywords: uiState.editKeywords,
                    supportUrl: uiState.editSupportUrl,
                    marketingUrl: uiState.editMarketingUrl
                )

                async let versionTask: () = connection.updateAppStoreVersion(
                    id: uiState.version.id,
                    versionString: uiState.editVersion,
                    copyright: uiState.editCopyright
                )

                _ = try await (locTask, versionTask)
            } else {
                try await connection.updateAppStoreVersion(
                    id: uiState.version.id,
                    versionString: uiState.editVersion,
                    copyright: uiState.editCopyright
                )
            }

            uiState.version.versionString = uiState.editVersion
            uiState.version.copyright = uiState.editCopyright
            uiState.localization?.keywords = uiState.editKeywords
            uiState.localization?.supportUrl = uiState.editSupportUrl
            uiState.localization?.marketingUrl = uiState.editMarketingUrl

            try await storage.save(uiState.version, id: "version.\(self.uiState.version.id)")
            Log.print.info("[VersionDetail] Saved grouped fields")

        } catch {
            uiState.groupedFieldsError = error.localizedDescription
            Log.print.error("[VersionDetail] Save grouped fields failed: \(error.localizedDescription)")
        }

        uiState.isSavingGroupedFields = false
    }

    func saveReleaseType() async {
        uiState.isSavingRelease = true
        uiState.releaseError = nil

        guard let connection = createConnection() else {
            uiState.isSavingRelease = false
            return
        }

        do {
            let releaseType: AppStoreVersionUpdateRequest.Data.Attributes.ReleaseType
            var earliestDate: Date?

            switch uiState.selectedReleaseType {
            case .manual:
                releaseType = .manual
            case .afterApproval:
                releaseType = .afterApproval
            case .scheduled:
                releaseType = .scheduled
                earliestDate = uiState.scheduledDate
            }

            try await connection.updateAppStoreVersion(
                id: uiState.version.id,
                releaseType: releaseType,
                earliestReleaseDate: earliestDate
            )

            uiState.version.releaseType = uiState.selectedReleaseType.rawValue.uppercased()
            uiState.showReleaseSheet = false
            try await storage.save(uiState.version, id: "version.\(self.uiState.version.id)")
            Log.print.info("[VersionDetail] Saved release type: \(self.uiState.selectedReleaseType.rawValue)")

        } catch {
            uiState.releaseError = error.localizedDescription
            Log.print.error("[VersionDetail] Save release type failed: \(error.localizedDescription)")
        }

        uiState.isSavingRelease = false
    }

    func savePhasedRelease(usePhased: Bool) async {
        uiState.isSavingPhasedRelease = true
        uiState.phasedReleaseError = nil

        guard let connection = createConnection() else {
            uiState.isSavingPhasedRelease = false
            return
        }

        do {
            if usePhased {
                // Create or keep phased release
                if uiState.phasedRelease == nil {
                    let created = try await connection.createPhasedRelease(versionId: uiState.version.id, state: .active)
                    uiState.phasedRelease = created
                }
            } else {
                // Delete phased release (release to all immediately)
                if let phasedId = uiState.phasedRelease?.id {
                    try await connection.deletePhasedRelease(id: phasedId)
                    uiState.phasedRelease = nil
                }
            }
            uiState.showPhasedReleaseSheet = false
            Log.print.info("[VersionDetail] Saved phased release: usePhased=\(usePhased)")
        } catch {
            uiState.phasedReleaseError = error.localizedDescription
            Log.print.error("[VersionDetail] Phased release save failed: \(error.localizedDescription)")
        }

        uiState.isSavingPhasedRelease = false
    }

    func setPhasedReleasePaused(_ paused: Bool) async {
        guard let phasedId = uiState.phasedRelease?.id else { return }

        uiState.isSavingPhasedRelease = true
        uiState.phasedReleaseError = nil

        guard let connection = createConnection() else {
            uiState.isSavingPhasedRelease = false
            return
        }

        do {
            let newState: PhasedReleaseState = paused ? .paused : .active
            let updated = try await connection.updatePhasedReleaseState(id: phasedId, state: newState)
            uiState.phasedRelease = updated
            Log.print.info("[VersionDetail] Phased release paused=\(paused)")
        } catch {
            uiState.phasedReleaseError = error.localizedDescription
            Log.print.error("[VersionDetail] Pause phased release failed: \(error.localizedDescription)")
        }

        uiState.isSavingPhasedRelease = false
    }

    // MARK: - Version Actions

    func submitForReview() async {
        uiState.isPerformingAction = true
        uiState.actionError = nil

        do {
            guard let connection = createConnection() else { return }
            try await connection.submitForReview(
                appId: uiState.version.appId,
                versionId: uiState.version.id,
                platform: uiState.version.platform
            )
            uiState.toastMessage = ToastMessage(String(localized: "Submitted for review"), icon: "paperplane.fill")
            Log.print.info("[VersionDetail] Submitted for review")
            await refresh()
        } catch {
            uiState.actionError = error.localizedDescription
            Log.print.error("[VersionDetail] Submit for review failed: \(error.localizedDescription)")
        }

        uiState.isPerformingAction = false
    }

    func cancelReview() async {
        uiState.isPerformingAction = true
        uiState.actionError = nil

        do {
            guard let connection = createConnection() else { return }
            try await connection.cancelReview(appId: uiState.version.appId)
            uiState.toastMessage = ToastMessage(String(localized: "Review cancelled"), icon: "xmark.circle.fill")
            Log.print.info("[VersionDetail] Cancelled review")
            await refresh()
        } catch {
            uiState.actionError = error.localizedDescription
            Log.print.error("[VersionDetail] Cancel review failed: \(error.localizedDescription)")
        }

        uiState.isPerformingAction = false
    }

    func releaseVersion() async {
        uiState.isPerformingAction = true
        uiState.actionError = nil

        do {
            guard let connection = createConnection() else { return }
            try await connection.releaseVersion(versionId: uiState.version.id)
            uiState.toastMessage = ToastMessage(String(localized: "Version released"), icon: "checkmark.circle.fill")
            Log.print.info("[VersionDetail] Released version")
            await refresh()
        } catch {
            uiState.actionError = error.localizedDescription
            Log.print.error("[VersionDetail] Release failed: \(error.localizedDescription)")
        }

        uiState.isPerformingAction = false
    }

    func rejectVersion() async {
        uiState.isPerformingAction = true
        uiState.actionError = nil

        do {
            guard let connection = createConnection() else { return }
            try await connection.rejectVersion(appId: uiState.version.appId)
            uiState.toastMessage = ToastMessage(String(localized: "Version rejected"), icon: "xmark.circle.fill")
            Log.print.info("[VersionDetail] Rejected version")
            await refresh()
        } catch {
            uiState.actionError = error.localizedDescription
            Log.print.error("[VersionDetail] Reject failed: \(error.localizedDescription)")
        }

        uiState.isPerformingAction = false
    }

    func completePhasedRelease() async {
        guard let phasedId = uiState.phasedRelease?.id else { return }

        uiState.isPerformingAction = true
        uiState.actionError = nil

        do {
            guard let connection = createConnection() else { return }
            let updated = try await connection.updatePhasedReleaseState(id: phasedId, state: .complete)
            uiState.phasedRelease = updated
            uiState.toastMessage = ToastMessage(String(localized: "Released to all users"), icon: "checkmark.circle.fill")
            Log.print.info("[VersionDetail] Completed phased release")
            await refresh()
        } catch {
            uiState.actionError = error.localizedDescription
            Log.print.error("[VersionDetail] Complete phased release failed: \(error.localizedDescription)")
        }

        uiState.isPerformingAction = false
    }

    // MARK: - Private

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}
