import Foundation

// MARK: - Protocol

@MainActor
protocol TestFlightViewModelProtocol: ObservableObject {
    var uiState: TestFlightUiState { get set }
    func load() async
    func createGroup(name: String, isInternal: Bool) async
    func deleteGroup(_ group: BetaGroupModel) async
}

// MARK: - UiState

struct PlatformBuildGroup: Identifiable {
    let platform: String
    let builds: [BuildModel]

    var id: String { platform }
}

struct TestFlightUiState {
    var appId: String
    var account: AccountModel
    var groups: [BetaGroupModel] = []
    var builds: [BuildModel] = []
    var isLoading = false
    var error: String?
    var toastMessage: ToastMessage?
    var showCreateGroup = false
    var isCreatingGroup = false
    var confirmDelete: BetaGroupModel?

    var internalGroups: [BetaGroupModel] {
        groups.filter { $0.isInternalGroup }
            .sorted { $0.name < $1.name }
    }

    var externalGroups: [BetaGroupModel] {
        groups.filter { !$0.isInternalGroup }
            .sorted { $0.name < $1.name }
    }

    var recentBuilds: [BuildModel] {
        builds.sorted { ($0.uploadedDate ?? .distantPast) > ($1.uploadedDate ?? .distantPast) }
    }

    /// Builds grouped by platform (most recent first within each group), sorted in
    /// canonical platform order. Builds with an unknown platform are bucketed under "Other".
    var buildsByPlatform: [PlatformBuildGroup] {
        let dict = Dictionary(grouping: recentBuilds) { $0.platform ?? "" }
        return dict
            .map { PlatformBuildGroup(platform: $0.key, builds: $0.value) }
            .sorted { BuildPlatform.sortOrder($0.platform) < BuildPlatform.sortOrder($1.platform) }
    }
}

// MARK: - Implementation

@MainActor
final class TestFlightViewModel: TestFlightViewModelProtocol {

    @Published var uiState: TestFlightUiState

    private let keychain: KeyStorable

    init(appId: String, account: AccountModel, keychain: KeyStorable = KeychainStorable.shared) {
        self.uiState = TestFlightUiState(appId: appId, account: account)
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

            async let groupsResult = connection.fetchBetaGroups(appId: uiState.appId)
            async let buildsResult = connection.fetchBuilds(appId: uiState.appId, limit: 20)

            uiState.groups = try await groupsResult
            uiState.builds = try await buildsResult
            uiState.isLoading = false

            Log.print.info("[TestFlight] Loaded \(self.uiState.groups.count) groups, \(self.uiState.builds.count) builds")
            loadTesterCounts()
        } catch {
            uiState.error = error.localizedDescription
            uiState.isLoading = false
            Log.print.error("[TestFlight] Load failed: \(error.localizedDescription)")
        }
    }

    private func loadTesterCounts() {
        guard let connection = createConnection() else { return }
        for group in uiState.groups {
            Task {
                do {
                    let count = try await connection.fetchTesterCount(groupId: group.id)
                    if let index = uiState.groups.firstIndex(where: { $0.id == group.id }) {
                        uiState.groups[index].testerCount = count
                    }
                } catch {
                    Log.print.error("[TestFlight] Tester count failed for \(group.id): \(error.localizedDescription)")
                }
            }
        }
    }

    func createGroup(name: String, isInternal: Bool) async {
        uiState.isCreatingGroup = true
        do {
            guard let connection = createConnection() else {
                uiState.isCreatingGroup = false
                return
            }
            let group = try await connection.createBetaGroup(
                appId: uiState.appId,
                name: name,
                isInternal: isInternal
            )
            uiState.groups.append(group)
            uiState.showCreateGroup = false
            uiState.toastMessage = ToastMessage(String(localized: "Group created"), icon: "person.3.fill")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to create group"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[TestFlight] Create group failed: \(error.localizedDescription)")
        }
        uiState.isCreatingGroup = false
    }

    func deleteGroup(_ group: BetaGroupModel) async {
        do {
            guard let connection = createConnection() else { return }
            try await connection.deleteBetaGroup(id: group.id)
            uiState.groups.removeAll { $0.id == group.id }
            uiState.toastMessage = ToastMessage(String(localized: "Group deleted"), icon: "trash")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to delete group"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[TestFlight] Delete group failed: \(error.localizedDescription)")
        }
    }

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return nil }
        return AppleAccountConnection(credentials: credentials)
    }
}
