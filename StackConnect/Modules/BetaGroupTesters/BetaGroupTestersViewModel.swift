import Foundation

// MARK: - Protocol

@MainActor
protocol BetaGroupTestersViewModelProtocol: ObservableObject {
    var uiState: BetaGroupTestersUiState { get set }
    func load() async
    func addTester(email: String, firstName: String?, lastName: String?) async
    func addTeamMembersAsTesters(_ members: [TeamMemberModel]) async
    func removeTester(_ tester: BetaTesterModel) async
    func resendInvite(_ tester: BetaTesterModel) async
    func loadTeamMembers() async
}

// MARK: - UiState

struct BetaGroupTestersUiState {
    var group: BetaGroupModel
    var appId: String
    var account: AccountModel
    var testers: [BetaTesterModel] = []
    var teamMembers: [TeamMemberModel] = []
    var isLoading = false
    var isLoadingTeamMembers = false
    var toastMessage: ToastMessage?
    var error: String?
    var inviteError: String?
    var showAddTester = false
    var isInvitingTesters = false
    var isRemovingTester = false
    var isResendingInvite = false
    var confirmRemoveTester: BetaTesterModel?
    var searchQuery: String = ""

    var filteredTesters: [BetaTesterModel] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return testers }
        return testers.filter { tester in
            tester.displayName.lowercased().contains(query)
                || (tester.email?.lowercased().contains(query) ?? false)
                || (tester.firstName?.lowercased().contains(query) ?? false)
                || (tester.lastName?.lowercased().contains(query) ?? false)
        }
    }
}

// MARK: - Implementation

@MainActor
final class BetaGroupTestersViewModel: BetaGroupTestersViewModelProtocol {

    @Published var uiState: BetaGroupTestersUiState

    private let keychain: KeyStorable

    init(group: BetaGroupModel, appId: String, account: AccountModel, keychain: KeyStorable = KeychainStorable.shared) {
        self.uiState = BetaGroupTestersUiState(group: group, appId: appId, account: account)
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

            uiState.testers = try await connection.fetchBetaTestersForGroup(groupId: uiState.group.id)
            Log.print.info("[BetaGroupTesters] Loaded \(self.uiState.testers.count) testers")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[BetaGroupTesters] Load failed: \(error.localizedDescription)")
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
            Log.print.error("[BetaGroupTesters] Add tester failed: \(error.localizedDescription)")
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
                Log.print.error("[BetaGroupTesters] Add team member failed: \(error.localizedDescription)")
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
            Log.print.error("[BetaGroupTesters] Load team members failed: \(error.localizedDescription)")
        }
        uiState.isLoadingTeamMembers = false
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
            Log.print.error("[BetaGroupTesters] Remove tester failed: \(error.localizedDescription)")
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
            Log.print.error("[BetaGroupTesters] Resend invite failed: \(error.localizedDescription)")
        }
        uiState.isResendingInvite = false
    }

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return nil }
        return AppleAccountConnection(credentials: credentials)
    }
}
