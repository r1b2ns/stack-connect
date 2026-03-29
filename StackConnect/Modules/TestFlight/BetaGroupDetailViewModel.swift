import Foundation

// MARK: - Protocol

@MainActor
protocol BetaGroupDetailViewModelProtocol: ObservableObject {
    var uiState: BetaGroupDetailUiState { get set }
    func load() async
    func addTester(email: String, firstName: String?, lastName: String?) async
    func addTeamMembersAsTesters(_ members: [TeamMemberModel]) async
    func removeTester(_ tester: BetaTesterModel) async
    func updateGroup(name: String?, isPublicLinkEnabled: Bool?, publicLinkLimit: Int?, isFeedbackEnabled: Bool?) async
    func addBuildToGroup(buildId: String) async
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
    var showAddBuild = false
    var showEditGroup = false
    var confirmRemoveTester: BetaTesterModel?
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
        do {
            guard let connection = createConnection() else { return }
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
    }

    func addTeamMembersAsTesters(_ members: [TeamMemberModel]) async {
        guard let connection = createConnection() else { return }
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
        guard uiState.allBuilds.isEmpty else { return }
        uiState.isLoadingBuilds = true
        do {
            guard let connection = createConnection() else {
                uiState.isLoadingBuilds = false
                return
            }
            uiState.allBuilds = try await connection.fetchBuilds(appId: uiState.appId, limit: 50)
        } catch {
            Log.print.error("[BetaGroupDetail] Load builds failed: \(error.localizedDescription)")
        }
        uiState.isLoadingBuilds = false
    }

    func removeTester(_ tester: BetaTesterModel) async {
        do {
            guard let connection = createConnection() else { return }
            try await connection.removeTesterFromGroup(testerId: tester.id, groupId: uiState.group.id)
            uiState.testers.removeAll { $0.id == tester.id }
            uiState.toastMessage = ToastMessage(String(localized: "Tester removed"), icon: "person.badge.minus")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to remove tester"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[BetaGroupDetail] Remove tester failed: \(error.localizedDescription)")
        }
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
        do {
            guard let connection = createConnection() else { return }
            try await connection.addBuildToGroups(buildId: buildId, groupIds: [uiState.group.id])
            uiState.showAddBuild = false
            uiState.toastMessage = ToastMessage(String(localized: "Build added"), icon: "hammer.fill")
            await load()
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to add build"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[BetaGroupDetail] Add build failed: \(error.localizedDescription)")
        }
    }

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return nil }
        return AppleAccountConnection(credentials: credentials)
    }
}
