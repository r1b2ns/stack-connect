import Foundation

// MARK: - Protocol

@MainActor
protocol UserAccessViewModelProtocol: ObservableObject {
    var uiState: UserAccessUiState { get set }
    func load() async
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

    init(account: AccountModel, keychain: KeyStorable = KeychainStorable.shared) {
        self.uiState = UserAccessUiState(account: account)
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
            uiState.users = try await connection.fetchUsers()
            Log.print.info("[UserAccess] Loaded \(self.uiState.users.count) users")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[UserAccess] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func deleteUser(_ user: UserModel) async {
        do {
            guard let connection = createConnection() else { return }
            try await connection.deleteUser(id: user.id, isPending: user.isPending)
            uiState.users.removeAll { $0.id == user.id }
            let message = user.isPending
                ? String(localized: "Invitation cancelled")
                : String(localized: "User removed")
            uiState.toastMessage = ToastMessage(message, icon: "person.badge.minus")
        } catch {
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
        do {
            guard let connection = createConnection() else { return }
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
        } catch {
            uiState.inviteError = error.localizedDescription
            Log.print.error("[UserAccess] Invite failed: \(error.localizedDescription)")
        }
    }

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return nil }
        return AppleAccountConnection(credentials: credentials)
    }
}
