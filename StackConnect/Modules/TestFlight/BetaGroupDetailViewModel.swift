import Foundation

// MARK: - Protocol

@MainActor
protocol BetaGroupDetailViewModelProtocol: ObservableObject {
    var uiState: BetaGroupDetailUiState { get set }
    func load() async
    func addTester(email: String, firstName: String?, lastName: String?) async
    func addTeamMembersAsTesters(_ members: [TeamMemberModel]) async
    func removeTester(_ tester: BetaTesterModel) async
    func resendInvite(_ tester: BetaTesterModel) async
    func updateGroup(name: String?, isPublicLinkEnabled: Bool?, publicLinkLimit: Int?, isFeedbackEnabled: Bool?) async
    func addBuildToGroup(buildId: String) async
    func removeBuildFromGroup(_ build: BuildModel) async
    func expireBuild(_ build: BuildModel) async
    func startSubmitForReview(_ build: BuildModel) async
    func confirmSubmitForReview(whatsNew: String) async
    func loadTeamMembers() async
    func loadAvailableBuilds() async
}

// MARK: - UiState

struct BetaGroupDetailUiState {
    var group: BetaGroupModel
    var appId: String
    var account: AccountModel
    var testers: [BetaTesterModel] = []
    var builds: [BuildModel] = []
    var allBuilds: [BuildModel] = []
    var teamMembers: [TeamMemberModel] = []
    var isLoading = false
    var isLoadingTeamMembers = false
    var isLoadingBuilds = false
    var toastMessage: ToastMessage?
    var error: String?
    var inviteError: String?
    var showAddTester = false
    var isInvitingTesters = false
    var isRemovingTester = false
    var isResendingInvite = false
    var showAddBuild = false
    var isAddingBuild = false
    var isRemovingBuild = false
    var confirmRemoveBuild: BuildModel?
    var confirmExpireBuild: BuildModel?
    var isExpiringBuild = false
    var expireError: String?
    var showEditGroup = false
    var confirmRemoveTester: BetaTesterModel?
    var showSubmitSheet = false
    var submitSheetBuild: BuildModel?
    var submitSheetWhatsNew = ""
    var submitSheetLocale = "en-US"
    var submitSheetLocalizationId: String?
    var isLoadingSubmitSheet = false
    var isSubmittingForReview = false
    var submitError: String?

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

            async let testersResult = connection.fetchBetaTestersForGroup(groupId: uiState.group.id)
            async let buildsResult = connection.fetchBuildsForGroup(groupId: uiState.group.id)

            uiState.testers = try await testersResult
            uiState.builds = try await buildsResult

            Log.print.info("[BetaGroupDetail] Loaded \(self.uiState.testers.count) testers, \(self.uiState.builds.count) builds")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[BetaGroupDetail] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func addTester(email: String, firstName: String?, lastName: String?) async {
        uiState.isInvitingTesters = true
        do {
            guard let connection = createConnection() else {
                uiState.isInvitingTesters = false
                return
            }
            try await connection.addTesterToGroup(
                email: email,
                firstName: firstName,
                lastName: lastName,
                groupId: uiState.group.id
            )
            uiState.showAddTester = false
            uiState.toastMessage = ToastMessage(String(localized: "Tester invited"), icon: "envelope.fill")
            await load()
        } catch {
            uiState.inviteError = error.localizedDescription
            Log.print.error("[BetaGroupDetail] Add tester failed: \(error.localizedDescription)")
        }
        uiState.isInvitingTesters = false
    }

    func addTeamMembersAsTesters(_ members: [TeamMemberModel]) async {
        uiState.isInvitingTesters = true
        guard let connection = createConnection() else {
            uiState.isInvitingTesters = false
            return
        }
        var failed = 0
        for member in members {
            do {
                try await connection.addTesterToGroup(
                    email: member.username ?? "",
                    firstName: member.firstName,
                    lastName: member.lastName,
                    groupId: uiState.group.id
                )
            } catch {
                failed += 1
                Log.print.error("[BetaGroupDetail] Add team member failed: \(error.localizedDescription)")
            }
        }
        uiState.showAddTester = false
        if failed == 0 {
            uiState.toastMessage = ToastMessage(String(localized: "Testers invited"), icon: "envelope.fill")
        } else if failed < members.count {
            uiState.toastMessage = ToastMessage(String(localized: "Some invites failed"), icon: "exclamationmark.triangle.fill")
        } else {
            uiState.inviteError = String(localized: "Failed to invite testers")
        }
        await load()
        uiState.isInvitingTesters = false
    }

    func loadTeamMembers() async {
        guard uiState.teamMembers.isEmpty else { return }
        uiState.isLoadingTeamMembers = true
        do {
            guard let connection = createConnection() else {
                uiState.isLoadingTeamMembers = false
                return
            }
            uiState.teamMembers = try await connection.fetchTeamMembers()
        } catch {
            Log.print.error("[BetaGroupDetail] Load team members failed: \(error.localizedDescription)")
        }
        uiState.isLoadingTeamMembers = false
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

    func removeTester(_ tester: BetaTesterModel) async {
        uiState.isRemovingTester = true
        do {
            guard let connection = createConnection() else {
                uiState.isRemovingTester = false
                return
            }
            try await connection.removeTesterFromGroup(testerId: tester.id, groupId: uiState.group.id)
            uiState.testers.removeAll { $0.id == tester.id }
            uiState.toastMessage = ToastMessage(String(localized: "Tester removed"), icon: "person.badge.minus")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to remove tester"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[BetaGroupDetail] Remove tester failed: \(error.localizedDescription)")
        }
        uiState.isRemovingTester = false
    }

    func resendInvite(_ tester: BetaTesterModel) async {
        uiState.isResendingInvite = true
        do {
            guard let connection = createConnection() else {
                uiState.isResendingInvite = false
                return
            }
            try await connection.resendInvite(testerId: tester.id, appId: uiState.appId)
            uiState.toastMessage = ToastMessage(String(localized: "Invite resent"), icon: "envelope.fill")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to resend invite"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[BetaGroupDetail] Resend invite failed: \(error.localizedDescription)")
        }
        uiState.isResendingInvite = false
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
