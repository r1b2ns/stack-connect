import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol BetaGroupTestersViewModelProtocol: ObservableObject {
    var uiState: BetaGroupTestersUiState { get set }
    func load() async
    func refresh() async
    func addTester(email: String, firstName: String?, lastName: String?) async
    func addTeamMembersAsTesters(_ members: [TeamMemberModel]) async
    func importCSVTesters(_ rows: [CSVTesterRow]) async
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
    private let analytics: AnalyticsTracking

    init(
        group: BetaGroupModel,
        appId: String,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = BetaGroupTestersUiState(group: group, appId: appId, account: account)
        self.keychain = keychain
        self.analytics = analytics
    }

    func load() async {
        _ = await performLoad()
    }

    /// Pull-to-refresh: same load, tracked as a `refresh` action with its outcome.
    func refresh() async {
        let succeeded = await performLoad()
        analytics.track(.action(.refresh, on: .betaGroupTesters, result: succeeded ? .success : .failure))
    }

    private func performLoad() async -> Bool {
        var succeeded = true
        uiState.isLoading = true
        uiState.error = nil

        do {
            guard let connection = createConnection() else {
                uiState.isLoading = false
                return false
            }

            uiState.testers = try await connection.fetchBetaTestersForGroup(groupId: uiState.group.id)
            Log.print.info("[BetaGroupTesters] Loaded \(self.uiState.testers.count) testers")
        } catch {
            succeeded = false
            uiState.error = error.localizedDescription
            Log.print.error("[BetaGroupTesters] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
        return succeeded
    }

    func addTester(email: String, firstName: String?, lastName: String?) async {
        analytics.track(.buttonTap(.invite, on: .addTester))
        uiState.isInvitingTesters = true
        do {
            guard let connection = createConnection() else {
                uiState.isInvitingTesters = false
                analytics.track(.action(.inviteTester, on: .addTester, result: .failure))
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
            analytics.track(.action(.inviteTester, on: .addTester, result: .success))
        } catch {
            analytics.track(.action(.inviteTester, on: .addTester, result: .failure))
            uiState.inviteError = error.localizedDescription
            Log.print.error("[BetaGroupTesters] Add tester failed: \(error.localizedDescription)")
        }
        uiState.isInvitingTesters = false
    }

    /// Sequentially invite testers parsed from a CSV, throttling each call by 1 second.
    /// The list is expected to already exclude testers that are part of this group.
    func importCSVTesters(_ rows: [CSVTesterRow]) async {
        analytics.track(.buttonTap(.continue, on: .csvTesterImport))
        guard !rows.isEmpty else {
            uiState.showAddTester = false
            return
        }

        uiState.isInvitingTesters = true
        guard let connection = createConnection() else {
            uiState.isInvitingTesters = false
            analytics.track(.action(.importTesters, on: .csvTesterImport, result: .failure, parameters: [
                AnalyticsParameterKey.count: .int(rows.count)
            ]))
            return
        }

        var failed = 0
        for (index, row) in rows.enumerated() {
            do {
                try await connection.addTesterToGroup(
                    email: row.email,
                    firstName: row.firstName.isEmpty ? nil : row.firstName,
                    lastName: row.lastName.isEmpty ? nil : row.lastName,
                    groupId: uiState.group.id
                )
            } catch {
                failed += 1
                Log.print.error("[BetaGroupTesters] Import CSV failed for \(row.email): \(error.localizedDescription)")
            }

            // Throttle subsequent requests; no need to wait after the last one.
            if index < rows.count - 1 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        uiState.showAddTester = false
        let succeeded = rows.count - failed
        analytics.track(.action(.importTesters, on: .csvTesterImport, result: succeeded > 0 ? .success : .failure, parameters: [
            AnalyticsParameterKey.count: .int(rows.count),
            AnalyticsParameterKey.failedCount: .int(failed)
        ]))
        if failed == 0 {
            uiState.toastMessage = ToastMessage(String(localized: "Imported \(succeeded) tester(s)"), icon: "envelope.fill")
        } else if succeeded > 0 {
            uiState.toastMessage = ToastMessage(String(localized: "Imported \(succeeded), \(failed) failed"), icon: "exclamationmark.triangle.fill")
        } else {
            uiState.inviteError = String(localized: "Failed to import testers")
        }
        await load()
        uiState.isInvitingTesters = false
    }

    func addTeamMembersAsTesters(_ members: [TeamMemberModel]) async {
        analytics.track(.buttonTap(.invite, on: .internalTesterPicker))
        uiState.isInvitingTesters = true
        guard let connection = createConnection() else {
            uiState.isInvitingTesters = false
            analytics.track(.action(.inviteTesters, on: .internalTesterPicker, result: .failure, parameters: [
                AnalyticsParameterKey.count: .int(members.count)
            ]))
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
        analytics.track(.action(.inviteTesters, on: .internalTesterPicker, result: failed < members.count ? .success : .failure, parameters: [
            AnalyticsParameterKey.count: .int(members.count),
            AnalyticsParameterKey.failedCount: .int(failed)
        ]))
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
        analytics.track(.buttonTap(.confirmRemove, on: .betaGroupTesters))
        uiState.isRemovingTester = true
        do {
            guard let connection = createConnection() else {
                uiState.isRemovingTester = false
                analytics.track(.action(.removeTester, on: .betaGroupTesters, result: .failure))
                return
            }
            try await connection.removeTesterFromGroup(testerId: tester.id, groupId: uiState.group.id)
            uiState.testers.removeAll { $0.id == tester.id }
            uiState.toastMessage = ToastMessage(String(localized: "Tester removed"), icon: "person.badge.minus")
            analytics.track(.action(.removeTester, on: .betaGroupTesters, result: .success))
        } catch {
            analytics.track(.action(.removeTester, on: .betaGroupTesters, result: .failure))
            uiState.toastMessage = ToastMessage(String(localized: "Failed to remove tester"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[BetaGroupTesters] Remove tester failed: \(error.localizedDescription)")
        }
        uiState.isRemovingTester = false
    }

    func resendInvite(_ tester: BetaTesterModel) async {
        analytics.track(.buttonTap(.resendInvite, on: .betaGroupTesters))
        uiState.isResendingInvite = true
        do {
            guard let connection = createConnection() else {
                uiState.isResendingInvite = false
                analytics.track(.action(.resendInvite, on: .betaGroupTesters, result: .failure))
                return
            }
            try await connection.resendInvite(testerId: tester.id, appId: uiState.appId)
            uiState.toastMessage = ToastMessage(String(localized: "Invite resent"), icon: "envelope.fill")
            analytics.track(.action(.resendInvite, on: .betaGroupTesters, result: .success))
        } catch {
            analytics.track(.action(.resendInvite, on: .betaGroupTesters, result: .failure))
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
