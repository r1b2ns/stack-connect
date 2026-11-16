import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol UserAccessViewModelProtocol: ObservableObject {
    var uiState: UserAccessUiState { get set }
    func load() async
    func refresh() async
    func deleteUser(_ user: UserModel) async
    func inviteUser(
        email: String,
        firstName: String,
        lastName: String,
        roles: [String],
        allAppsVisible: Bool,
        provisioningAllowed: Bool
    ) async
}

// MARK: - Filter

enum UserRoleFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case accountHolder = "ACCOUNT_HOLDER"
    case admin = "ADMIN"
    case finance = "FINANCE"
    case accessToReports = "ACCESS_TO_REPORTS"
    case sales = "SALES"
    case developer = "DEVELOPER"
    case appManager = "APP_MANAGER"
    case customerSupport = "CUSTOMER_SUPPORT"
    case marketing = "MARKETING"
    case readOnly = "READ_ONLY"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:              return String(localized: "All")
        case .accountHolder:    return String(localized: "Account Holder")
        case .admin:            return String(localized: "Admin")
        case .finance:          return String(localized: "Finance")
        case .accessToReports:  return String(localized: "Access to Reports")
        case .sales:            return String(localized: "Sales")
        case .developer:        return String(localized: "Developer")
        case .appManager:       return String(localized: "App Manager")
        case .customerSupport:  return String(localized: "Customer Support")
        case .marketing:        return String(localized: "Marketing")
        case .readOnly:         return String(localized: "Read Only")
        }
    }
}

// MARK: - UiState

struct UserAccessUiState {
    var account: AccountModel
    var users: [UserModel] = []
    var isLoading = false
    var toastMessage: ToastMessage?
    var error: String?
    var selectedFilter: UserRoleFilter = .all
    var searchQuery = ""
    var showInviteUser = false
    var confirmDeleteUser: UserModel?
    var inviteError: String?
    var deleteError: String?

    var filteredUsers: [UserModel] {
        var result = users

        if selectedFilter != .all {
            result = result.filter { $0.roles.contains(selectedFilter.rawValue) }
        }

        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.displayName.lowercased().contains(query) ||
                ($0.email?.lowercased().contains(query) ?? false)
            }
        }

        return result.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

// MARK: - Implementation

@MainActor
final class UserAccessViewModel: UserAccessViewModelProtocol {

    @Published var uiState: UserAccessUiState

    private let keychain: KeyStorable
    private let analytics: AnalyticsTracking

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = UserAccessUiState(account: account)
        self.keychain = keychain
        self.analytics = analytics
    }

    func load() async {
        _ = await performLoad()
    }

    /// Pull-to-refresh: same load, tracked as a `refresh` action with its outcome.
    func refresh() async {
        let succeeded = await performLoad()
        analytics.track(.action(.refresh, on: .userAccess, result: succeeded ? .success : .failure))
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
            uiState.users = try await connection.fetchUsers()
            Log.print.info("[UserAccess] Loaded \(self.uiState.users.count) users")
        } catch {
            succeeded = false
            uiState.error = error.localizedDescription
            Log.print.error("[UserAccess] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
        return succeeded
    }

    func deleteUser(_ user: UserModel) async {
        analytics.track(.buttonTap(.confirmDelete, on: .userAccess))
        let parameters = Self.deleteParameters(for: user)
        do {
            guard let connection = createConnection() else {
                analytics.track(.action(.deleteUser, on: .userAccess, result: .failure, parameters: parameters))
                return
            }
            try await connection.deleteUser(id: user.id, isPending: user.isPending)
            uiState.users.removeAll { $0.id == user.id }
            let message = user.isPending
                ? String(localized: "Invitation cancelled")
                : String(localized: "User removed")
            uiState.toastMessage = ToastMessage(message, icon: "person.badge.minus")
            analytics.track(.action(.deleteUser, on: .userAccess, result: .success, parameters: parameters))
        } catch {
            analytics.track(.action(.deleteUser, on: .userAccess, result: .failure, parameters: parameters))
            if AppleAPIErrorTranslator.isForbidden(error) {
                uiState.deleteError = String(localized: "Your App Store Connect API key isn't allowed to remove users. Managing Users and Access requires a key with the Admin role. Update the key's permissions in App Store Connect (Users and Access → Integrations) and try again.")
            } else {
                uiState.toastMessage = ToastMessage(String(localized: "Failed to remove user"), icon: "exclamationmark.triangle.fill")
            }
            Log.print.error("[UserAccess] Delete failed: \(error.localizedDescription)")
        }
    }

    func inviteUser(
        email: String,
        firstName: String,
        lastName: String,
        roles: [String],
        allAppsVisible: Bool,
        provisioningAllowed: Bool
    ) async {
        analytics.track(.buttonTap(.invite, on: .inviteUser))
        // Shape of the invitation only — never the email or the name.
        let parameters: [String: AnalyticsValue] = [
            AnalyticsParameterKey.count: .int(roles.count),
            AnalyticsParameterKey.scoped: .bool(!allAppsVisible)
        ]
        do {
            guard let connection = createConnection() else {
                analytics.track(.action(.inviteUser, on: .inviteUser, result: .failure, parameters: parameters))
                return
            }
            try await connection.inviteUser(
                email: email,
                firstName: firstName,
                lastName: lastName,
                roles: roles,
                allAppsVisible: allAppsVisible,
                provisioningAllowed: provisioningAllowed
            )
            uiState.showInviteUser = false
            uiState.toastMessage = ToastMessage(String(localized: "Invitation sent"), icon: "envelope.fill")
            await load()
            analytics.track(.action(.inviteUser, on: .inviteUser, result: .success, parameters: parameters))
        } catch {
            analytics.track(.action(.inviteUser, on: .inviteUser, result: .failure, parameters: parameters))
            uiState.inviteError = error.localizedDescription
            Log.print.error("[UserAccess] Invite failed: \(error.localizedDescription)")
        }
    }

    /// Whether a pending invitation or an active member is being removed.
    static func deleteParameters(for user: UserModel) -> [String: AnalyticsValue] {
        [AnalyticsParameterKey.kind: .string(user.isPending ? "invitation" : "member")]
    }

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return nil }
        return AppleAccountConnection(credentials: credentials)
    }
}
