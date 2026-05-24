import Foundation

// MARK: - Protocol

@MainActor
protocol BetaGroupDetailViewModelProtocol: ObservableObject {
    var uiState: BetaGroupDetailUiState { get set }
    func load() async
    func loadTestInformation() async
    func requestAddBuild()
    func updateGroup(name: String?, isPublicLinkEnabled: Bool?, publicLinkLimit: Int?, isFeedbackEnabled: Bool?) async
    func addBuildToGroup(buildId: String) async
    func removeBuildFromGroup(_ build: BuildModel) async
    func expireBuild(_ build: BuildModel) async
    func startSubmitForReview(_ build: BuildModel) async
    func confirmSubmitForReview(whatsNew: String) async
    func loadAvailableBuilds() async
}

// MARK: - UiState

struct BetaGroupDetailUiState {
    var group: BetaGroupModel
    var appId: String
    var account: AccountModel
    var builds: [BuildModel] = []
    var allBuilds: [BuildModel] = []
    var isLoading = false
    var isLoadingBuilds = false
    var toastMessage: ToastMessage?
    var error: String?
    var showAddBuild = false
    var isAddingBuild = false
    var isRemovingBuild = false
    var confirmRemoveBuild: BuildModel?
    var confirmExpireBuild: BuildModel?
    var isExpiringBuild = false
    var expireError: String?
    var showEditGroup = false
    var showSubmitSheet = false
    var submitSheetBuild: BuildModel?
    var submitSheetWhatsNew = ""
    var submitSheetLocale = "en-US"
    var submitSheetLocalizationId: String?
    var isLoadingSubmitSheet = false
    var isSubmittingForReview = false
    var submitError: String?

    // Test Information (Beta App Review Detail + Beta App Localization)
    var betaReviewDetail: BetaAppReviewDetailModel?
    var betaAppLocalization: BetaAppLocalizationModel?
    var showTestInformationRequiredAlert = false

    var isTestInformationComplete: Bool {
        BetaAppReviewInfoCompleteness.isComplete(
            detail: betaReviewDetail,
            localization: betaAppLocalization
        )
    }

    /// Builds assigned to this group, grouped by platform in canonical order.
    var buildsByPlatform: [PlatformBuildGroup] {
        let sorted = builds.sorted { ($0.uploadedDate ?? .distantPast) > ($1.uploadedDate ?? .distantPast) }
        let dict = Dictionary(grouping: sorted) { $0.platform ?? "" }
        return dict
            .map { PlatformBuildGroup(platform: $0.key, builds: $0.value) }
            .sorted { BuildPlatform.sortOrder($0.platform) < BuildPlatform.sortOrder($1.platform) }
    }
}

// MARK: - Implementation

@MainActor
final class BetaGroupDetailViewModel: BetaGroupDetailViewModelProtocol {

    @Published var uiState: BetaGroupDetailUiState

    private let keychain: KeyStorable

    init(group: BetaGroupModel, appId: String, account: AccountModel, keychain: KeyStorable = KeychainStorable.shared) {
        self.uiState = BetaGroupDetailUiState(group: group, appId: appId, account: account)
        self.keychain = keychain
    }

    func load() async {
        uiState.isLoading = true
        uiState.error = nil

        do {
            guard let connection = createConnection() else {
                uiState.isLoading = false
                return
            }

            uiState.builds = try await connection.fetchBuildsForGroup(groupId: uiState.group.id)

            Log.print.info("[BetaGroupDetail] Loaded \(self.uiState.builds.count) builds")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[BetaGroupDetail] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false

        if !uiState.group.isInternalGroup {
            await loadTestInformation()
        }
    }

    func loadTestInformation() async {
        guard !uiState.group.isInternalGroup else { return }
        guard let connection = createConnection() else { return }

        do {
            async let detail = connection.fetchBetaAppReviewDetail(appId: uiState.appId)
            async let localizations = connection.fetchBetaAppLocalizations(appId: uiState.appId)
            uiState.betaReviewDetail = try await detail
            let locs = try await localizations
            uiState.betaAppLocalization = locs.first(where: { $0.locale == "en-US" }) ?? locs.first
        } catch {
            Log.print.error("[BetaGroupDetail] Load test info failed: \(error.localizedDescription)")
        }
    }

    func requestAddBuild() {
        if !uiState.group.isInternalGroup && !uiState.isTestInformationComplete {
            uiState.showTestInformationRequiredAlert = true
        } else {
            uiState.showAddBuild = true
        }
    }

    func loadAvailableBuilds() async {
        uiState.isLoadingBuilds = true
        do {
            guard let connection = createConnection() else {
                uiState.isLoadingBuilds = false
                return
            }
            let all = try await connection.fetchBuilds(appId: uiState.appId, limit: 50)
            let assignedIds = Set(uiState.builds.map(\.id))
            uiState.allBuilds = all.filter { build in
                build.processingState == "VALID" && !assignedIds.contains(build.id)
            }
        } catch {
            Log.print.error("[BetaGroupDetail] Load builds failed: \(error.localizedDescription)")
        }
        uiState.isLoadingBuilds = false
    }

    func updateGroup(name: String?, isPublicLinkEnabled: Bool?, publicLinkLimit: Int?, isFeedbackEnabled: Bool?) async {
        do {
            guard let connection = createConnection() else { return }
            try await connection.updateBetaGroup(
                id: uiState.group.id,
                name: name,
                isPublicLinkEnabled: isPublicLinkEnabled,
                publicLinkLimit: publicLinkLimit,
                isFeedbackEnabled: isFeedbackEnabled
            )
            if let name { uiState.group.name = name }
            if let enabled = isPublicLinkEnabled { uiState.group.isPublicLinkEnabled = enabled }
            if let limit = publicLinkLimit { uiState.group.publicLinkLimit = limit }
            if let feedback = isFeedbackEnabled { uiState.group.isFeedbackEnabled = feedback }
            uiState.showEditGroup = false
            uiState.toastMessage = ToastMessage(String(localized: "Group updated"), icon: "checkmark.circle.fill")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to update group"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[BetaGroupDetail] Update failed: \(error.localizedDescription)")
        }
    }

    func addBuildToGroup(buildId: String) async {
        uiState.isAddingBuild = true
        do {
            guard let connection = createConnection() else {
                uiState.isAddingBuild = false
                return
            }
            try await connection.addBuildToGroups(buildId: buildId, groupIds: [uiState.group.id])
            uiState.showAddBuild = false
            uiState.toastMessage = ToastMessage(String(localized: "Build added"), icon: "hammer.fill")
            await load()
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to add build"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[BetaGroupDetail] Add build failed: \(error.localizedDescription)")
        }
        uiState.isAddingBuild = false
    }

    func startSubmitForReview(_ build: BuildModel) async {
        uiState.submitSheetBuild = build
        uiState.submitSheetWhatsNew = ""
        uiState.submitSheetLocalizationId = nil
        uiState.submitSheetLocale = "en-US"
        uiState.isLoadingSubmitSheet = true
        uiState.showSubmitSheet = true

        guard let connection = createConnection() else {
            uiState.isLoadingSubmitSheet = false
            return
        }

        do {
            let localizations = try await connection.fetchBetaBuildLocalizations(buildId: build.id)
            let preferred = localizations.first(where: { $0.locale == "en-US" }) ?? localizations.first
            if let preferred {
                uiState.submitSheetLocalizationId = preferred.id
                uiState.submitSheetLocale = preferred.locale
                uiState.submitSheetWhatsNew = preferred.whatsNew ?? ""
            }
        } catch {
            Log.print.error("[BetaGroupDetail] Load beta localizations failed: \(error.localizedDescription)")
        }
        uiState.isLoadingSubmitSheet = false
    }

    func confirmSubmitForReview(whatsNew: String) async {
        guard let build = uiState.submitSheetBuild else { return }
        uiState.isSubmittingForReview = true
        uiState.submitError = nil
        do {
            guard let connection = createConnection() else {
                uiState.isSubmittingForReview = false
                return
            }

            if let id = uiState.submitSheetLocalizationId {
                try await connection.updateBetaBuildLocalization(id: id, whatsNew: whatsNew)
            } else {
                try await connection.createBetaBuildLocalization(
                    buildId: build.id,
                    locale: uiState.submitSheetLocale,
                    whatsNew: whatsNew
                )
            }
            try await connection.submitBuildForBetaReview(buildId: build.id)

            uiState.showSubmitSheet = false
            uiState.submitSheetBuild = nil
            uiState.toastMessage = ToastMessage(String(localized: "Submitted for review"), icon: "paperplane.fill")
            await load()
        } catch {
            uiState.submitError = error.localizedDescription
            Log.print.error("[BetaGroupDetail] Submit for review failed: \(error.localizedDescription)")
        }
        uiState.isSubmittingForReview = false
    }

    func expireBuild(_ build: BuildModel) async {
        uiState.isExpiringBuild = true
        uiState.expireError = nil
        do {
            guard let connection = createConnection() else {
                uiState.isExpiringBuild = false
                return
            }
            try await connection.expireBuild(buildId: build.id)
            if let idx = uiState.builds.firstIndex(where: { $0.id == build.id }) {
                uiState.builds[idx].isExpired = true
            }
            uiState.toastMessage = ToastMessage(String(localized: "Build expired"), icon: "clock.badge.xmark")
        } catch {
            uiState.expireError = error.localizedDescription
            Log.print.error("[BetaGroupDetail] Expire failed: \(error.localizedDescription)")
        }
        uiState.isExpiringBuild = false
    }

    func removeBuildFromGroup(_ build: BuildModel) async {
        uiState.isRemovingBuild = true
        do {
            guard let connection = createConnection() else {
                uiState.isRemovingBuild = false
                return
            }
            try await connection.removeBuildFromGroup(buildId: build.id, groupId: uiState.group.id)
            uiState.builds.removeAll { $0.id == build.id }
            uiState.toastMessage = ToastMessage(String(localized: "Build removed"), icon: "trash")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to remove build"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[BetaGroupDetail] Remove build failed: \(error.localizedDescription)")
        }
        uiState.isRemovingBuild = false
    }

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return nil }
        return AppleAccountConnection(credentials: credentials)
    }
}
