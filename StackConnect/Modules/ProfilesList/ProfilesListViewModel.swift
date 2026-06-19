import Foundation

// MARK: - Protocol

@MainActor
protocol ProfilesListViewModelProtocol: ObservableObject {
    var uiState: ProfilesListUiState { get set }
    func load() async
    func insertProfile(_ profile: ProvisioningProfileModel)
    func removeProfile(id: String)
}

// MARK: - UiState

struct ProfilesListUiState {
    var account: AccountModel
    var profiles: [ProvisioningProfileModel] = []
    var isLoading = false
    var errorMessage: String?
    var pendingAgreement: Bool = false
    var searchQuery = ""

    var filteredProfiles: [ProvisioningProfileModel] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return profiles }
        return profiles.filter {
            $0.name.lowercased().contains(query) ||
            $0.typeDisplayName.lowercased().contains(query) ||
            ($0.bundleId?.lowercased().contains(query) ?? false)
        }
    }

    var groupedByType: [(type: String, items: [ProvisioningProfileModel])] {
        let grouped = Dictionary(grouping: filteredProfiles, by: { $0.typeDisplayName })
        return grouped
            .map { (type: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.type < $1.type }
    }
}

// MARK: - Implementation

@MainActor
final class ProfilesListViewModel: ProfilesListViewModelProtocol {

    @Published var uiState: ProfilesListUiState

    private let keychain: KeyStorable

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = ProfilesListUiState(account: account)
        self.keychain = keychain
    }

    func removeProfile(id: String) {
        uiState.profiles.removeAll { $0.id == id }
    }

    func insertProfile(_ profile: ProvisioningProfileModel) {
        if let idx = uiState.profiles.firstIndex(where: { $0.id == profile.id }) {
            uiState.profiles[idx] = profile
        } else {
            uiState.profiles.insert(profile, at: 0)
        }
    }

    /// Maps a `load()` failure onto UI state: a pending Program License Agreement
    /// surfaces as the friendly tip flag, anything else as the generic error message.
    /// Extracted as the injectable test seam because `load()` builds its
    /// `AppleAccountConnection` inline and is otherwise not unit-testable.
    func handleLoadError(_ error: Error) {
        if AppleAPIErrorTranslator.isPendingAgreement(error) {
            uiState.pendingAgreement = true
        } else {
            uiState.errorMessage = error.localizedDescription
        }
    }

    func load() async {
        uiState.isLoading = true
        uiState.errorMessage = nil
        uiState.pendingAgreement = false

        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            uiState.errorMessage = String(localized: "No credentials found for this account")
            uiState.isLoading = false
            Log.print.error("[Profiles] No credentials for account: \(self.uiState.account.name)")
            return
        }

        let connection = AppleAccountConnection(credentials: credentials)

        do {
            let profiles = try await connection.fetchProfiles()
            uiState.profiles = profiles
            Log.print.info("[Profiles] Loaded \(profiles.count) for account: \(self.uiState.account.name)")
        } catch {
            handleLoadError(error)
            Log.print.error("[Profiles] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }
}
