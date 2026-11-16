import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol GooglePlayUsersViewModelProtocol: ObservableObject {
    var uiState: GooglePlayUsersUiState { get set }
    func load() async
    func refresh() async
    /// Reloads from the cache only (after a pop-back from a user's detail,
    /// which keeps the cache in step with its writes).
    func reloadFromCache() async
    func saveDeveloperId() async
}

// MARK: - UiState

struct GooglePlayUsersUiState {
    var account: AccountModel
    var users: [GooglePlayUserModel] = []
    var isLoading = false
    var isSyncing = false
    var showSyncToast = false
    /// Last load failure, user-facing.
    var error: String?
    /// The last load failed in a way a wrong developer ID explains (404 / 403):
    /// the error offers to change it (plan U3).
    var developerIdRejected = false
    /// The one-field setup form is on screen (no developer ID yet, or the user
    /// chose to change it).
    var isEditingDeveloperId = false
    var developerIdInput = ""
    var developerIdError: String?
    var isSavingDeveloperId = false
    var toastMessage: ToastMessage?
    /// The calling service account's `client_email` (self-protection, U7).
    var serviceAccountEmail: String?

    var developerId: String? { account.googlePlayDeveloperId }

    /// Setup state: no developer ID, or the user is correcting it.
    var showsSetup: Bool {
        developerId == nil || isEditingDeveloperId
    }

    var access: GooglePlayUsersAccess {
        GooglePlayUsersAccess(account: account, serviceAccountEmail: serviceAccountEmail)
    }
}

// MARK: - Implementation

/// The Users tab of a Google Play account (plan U4).
///
/// Offline-first: the cached users (`googleplay-users.{accountId}`) show right
/// away, then the list is fetched from `developers/{id}/users`. Nothing is
/// requested without a developer ID: the tab shows its setup field instead.
@MainActor
final class GooglePlayUsersViewModel: GooglePlayUsersViewModelProtocol {

    typealias ConnectionFactory = (GooglePlayCredentials) -> any GooglePlayUsersConnecting

    @Published var uiState: GooglePlayUsersUiState

    private let keychain: KeyStorable
    private let storage: PersistentStorable
    private let connectionFactory: ConnectionFactory
    private let analytics: AnalyticsTracking
    private var connection: (any GooglePlayUsersConnecting)?

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        storage: PersistentStorable? = nil,
        connectionFactory: @escaping ConnectionFactory = { GooglePlayAccountConnection(credentials: $0) },
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = GooglePlayUsersUiState(account: account)
        self.keychain = keychain
        self.storage = storage ?? SwiftDataStorable.shared
        self.connectionFactory = connectionFactory
        self.analytics = analytics
        self.uiState.serviceAccountEmail = Self.serviceAccountEmail(keychain: keychain, accountId: account.id)
    }

    // MARK: - Load

    func load() async {
        await performLoad()
    }

    func refresh() async {
        await performLoad()
        analytics.track(.action(.refresh, on: .googlePlayUsers, result: uiState.error == nil ? .success : .failure))
    }

    func reloadFromCache() async {
        guard uiState.developerId != nil, let cached = await loadCache() else { return }
        uiState.users = Self.sorted(cached.users)
    }

    private func performLoad() async {
        await refreshAccount()
        guard uiState.access.canView else { return }
        guard let developerId = uiState.developerId else {
            // Setup state: nothing to request until the ID is known.
            uiState.users = []
            uiState.isLoading = false
            return
        }

        uiState.error = nil
        if let cached = await loadCache() {
            uiState.users = Self.sorted(cached.users)
        }
        uiState.isLoading = uiState.users.isEmpty

        guard let connection = makeConnection() else {
            uiState.error = String(localized: "No credentials found for this account.")
            uiState.isLoading = false
            return
        }

        uiState.isSyncing = true
        if !uiState.users.isEmpty { uiState.showSyncToast = true }

        do {
            let users = try await connection.fetchUsers(developerId: developerId)
            uiState.users = Self.sorted(users)
            uiState.developerIdRejected = false
            await saveCache()
            Log.print.info("[GooglePlayUsers] Synced \(users.count) users for account: \(self.uiState.account.name)")
        } catch {
            Log.print.error("[GooglePlayUsers] Sync failed: \(error.localizedDescription)")
            let offline = GooglePlayErrorTranslator.isOffline(error)
            if !(offline && !uiState.users.isEmpty) {
                uiState.error = GooglePlayErrorTranslator.friendlyMessage(for: error, operation: .users)
            }
            uiState.developerIdRejected = GooglePlayErrorTranslator.isWrongDeveloperId(error)
        }

        uiState.isLoading = false
        uiState.isSyncing = false
    }

    // MARK: - Developer ID (plan U3)

    func saveDeveloperId() async {
        analytics.track(.buttonTap(.saveDeveloperId, on: .googlePlayUsers))
        guard let developerId = GooglePlayDeveloperId.normalized(uiState.developerIdInput) else {
            uiState.developerIdError = String(localized: "Enter the number from Play Console › Settings › Developer account.")
            return
        }
        uiState.isSavingDeveloperId = true
        defer { uiState.isSavingDeveloperId = false }

        let changed = developerId != uiState.developerId
        let updated = uiState.account.updating(googlePlayDeveloperId: .some(developerId))
        do {
            try await storage.save(updated, id: updated.id)
        } catch {
            Log.print.error("[GooglePlayUsers] Saving the developer ID failed: \(error.localizedDescription)")
            uiState.developerIdError = String(localized: "The Developer ID couldn't be saved. Try again.")
            analytics.track(.action(.saveDeveloperId, on: .googlePlayUsers, result: .failure))
            return
        }
        uiState.account = updated
        uiState.developerIdError = nil
        uiState.isEditingDeveloperId = false
        analytics.track(.action(.saveDeveloperId, on: .googlePlayUsers, result: .success))

        // Another developer account's users must not show under the new ID.
        if changed {
            uiState.users = []
            try? await storage.delete(GooglePlayUsersCache.self, id: cacheKey)
        }
        await performLoad()
    }

    // MARK: - Private

    /// The account as stored now: the developer ID may have been set in
    /// Account Settings since this screen was pushed.
    private func refreshAccount() async {
        if let stored = try? await storage.fetch(AccountModel.self, id: uiState.account.id) {
            uiState.account = stored
        }
    }

    private func makeConnection() -> (any GooglePlayUsersConnecting)? {
        if let connection { return connection }
        guard let credentials: GooglePlayCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            Log.print.error("[GooglePlayUsers] No credentials found for account: \(self.uiState.account.name)")
            return nil
        }
        let made = connectionFactory(credentials)
        connection = made
        return made
    }

    private static func serviceAccountEmail(keychain: KeyStorable, accountId: String) -> String? {
        guard let credentials: GooglePlayCredentials = keychain.object(forKey: "credentials.\(accountId)") else { return nil }
        return (try? GooglePlayServiceAccount(credentials: credentials))?.clientEmail
    }

    private var cacheKey: String {
        GooglePlayUsersCache.cacheKey(accountId: uiState.account.id)
    }

    private func loadCache() async -> GooglePlayUsersCache? {
        do {
            return try await storage.fetch(GooglePlayUsersCache.self, id: cacheKey)
        } catch {
            Log.print.error("[GooglePlayUsers] Cache load failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func saveCache() async {
        let cache = GooglePlayUsersCache(accountId: uiState.account.id, users: uiState.users, fetchedAt: Date())
        do {
            try await storage.save(cache, id: cacheKey)
        } catch {
            Log.print.error("[GooglePlayUsers] Cache save failed: \(error.localizedDescription)")
        }
    }

    /// People with access first (by name), then invitations, expired ones, and
    /// service accounts last.
    static func sorted(_ users: [GooglePlayUserModel]) -> [GooglePlayUserModel] {
        func rank(_ user: GooglePlayUserModel) -> Int {
            if user.isServiceAccount { return 3 }
            switch user.accessState {
            case .invited: return 1
            case .invitationExpired, .accessExpired: return 2
            default: return 0
            }
        }
        return users.sorted { lhs, rhs in
            let (l, r) = (rank(lhs), rank(rhs))
            if l != r { return l < r }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
