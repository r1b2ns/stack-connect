import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol GooglePlayUserDetailViewModelProtocol: ObservableObject {
    var uiState: GooglePlayUserDetailUiState { get set }
    func load() async
    /// Turns Admin on or off (self-protection: the service account keeps it).
    func setAdmin(_ isOn: Bool)
    func setAccountPermission(_ permission: GooglePlayPermission, isOn: Bool)
    /// Saves the account-level permissions and the expiry.
    func save() async
    func requestRemove()
    /// Removes the user. Returns whether it was removed (the screen closes).
    func remove() async -> Bool
    /// Creates or replaces the user's access to one app.
    func saveGrant(packageName: String, permissions: [String]) async -> Bool
    func requestRemoveGrant(_ grant: GooglePlayGrantModel)
    func removeGrant(_ grant: GooglePlayGrantModel) async -> Bool
}

// MARK: - UiState

struct GooglePlayUserDetailUiState {
    var account: AccountModel
    /// The user as Google last returned it.
    var user: GooglePlayUserModel
    var serviceAccountEmail: String?
    /// The Google account's e-mail of a "Sign in with Google" account, named
    /// in its access copy; `nil` for a service account.
    var googleAccountEmail: String?
    /// The account's apps (cached list, in scope): names and icons of grants
    /// and the App Permissions picker.
    var apps: [GooglePlayAppItem] = []

    // Draft of the account-level permissions and expiry (saved with Save).
    var draftAccountPermissions: [String]
    var draftExpiration: Date?

    var isSaving = false
    var toastMessage: ToastMessage?
    var errorMessage: String?
    /// Technical lines of `errorMessage`'s Share Error report.
    var errorDetails: [String] = []
    /// A failure while the App Permissions sheet is open: shown in the sheet,
    /// since an alert can't show over it.
    var grantEditorError: GooglePlayUsersFailure?
    var refusalMessage: String?
    var confirmRemove = false
    var confirmRemoveGrant: GooglePlayGrantModel?
    var showExpiryEditor = false
    /// The App Permissions sheet: a grant to edit, or a new one.
    var grantEditor: GooglePlayGrantEditorRequest?

    init(account: AccountModel, user: GooglePlayUserModel, serviceAccountEmail: String?) {
        self.account = account
        self.user = user
        self.serviceAccountEmail = serviceAccountEmail
        self.draftAccountPermissions = user.developerAccountPermissions
        self.draftExpiration = user.expirationTime
    }

    var access: GooglePlayUsersAccess {
        GooglePlayUsersAccess(account: account, serviceAccountEmail: serviceAccountEmail)
    }

    var isSelf: Bool { access.isSelf(user) }

    /// Footer of a user Google returned only part of (`partial`).
    var partialAccessFooter: String {
        switch account.authMethod {
        case .keyFile:
            return String(localized: "Google returned only part of this user's access (they also have access this service account can't see). Edit them in Play Console.")
        case .googleSignIn:
            if let email = googleAccountEmail {
                return String(localized: "Google returned only part of this user's access (they also have access the Google account \(email) can't see). Edit them in Play Console.",
                              comment: "Footer of a Google Play user, account added with Sign in with Google. The placeholder is that Google account's e-mail.")
            }
            return String(localized: "Google returned only part of this user's access (they also have access the signed-in Google account can't see). Edit them in Play Console.")
        }
    }

    var draftIsAdmin: Bool {
        draftAccountPermissions.contains(GooglePlayPermissionCatalog.adminPermission)
    }

    var canEditAccountPermissions: Bool {
        access.accountPermissionsRefusal(for: user) == nil
    }

    /// Admin already covers every app, so per-app access adds nothing.
    var canAddGrant: Bool {
        access.editRefusal(for: user) == nil && !user.isAdmin && !availableAppsForNewGrant.isEmpty
    }

    var canRemove: Bool { access.canDelete }

    /// In-scope apps the user has no access to yet.
    var availableAppsForNewGrant: [GooglePlayAppItem] {
        apps.filter { app in access.allowsApp(app.packageName) && user.grant(for: app.packageName) == nil }
    }

    /// Unsaved changes to the account permissions or the expiry.
    var hasChanges: Bool {
        Set(GooglePlayPermissionCatalog.normalized(draftAccountPermissions, level: .account))
            != Set(GooglePlayPermissionCatalog.normalized(user.developerAccountPermissions, level: .account))
            || draftExpiration != user.expirationTime
    }

    func app(for packageName: String) -> GooglePlayAppItem? {
        apps.first { $0.packageName == packageName }
    }

    /// The grants, by app name.
    var sortedGrants: [GooglePlayGrantModel] {
        user.grants.sorted { lhs, rhs in
            let l = app(for: lhs.packageName)?.displayName ?? lhs.packageName
            let r = app(for: rhs.packageName)?.displayName ?? rhs.packageName
            return l.localizedCaseInsensitiveCompare(r) == .orderedAscending
        }
    }
}

/// What the App Permissions sheet opens on (plan U7).
struct GooglePlayGrantEditorRequest: Identifiable, Equatable {
    /// `nil` when adding: the sheet shows the app picker.
    let packageName: String?
    let permissions: [String]

    var id: String { packageName ?? "new" }
}

// MARK: - Implementation

/// One Google Play user (plan U5, prototype 17): access state, expiry, Admin,
/// account-level permissions, per-app access and removal. Every write goes to
/// Google first; the screen and the users cache change only on success.
@MainActor
final class GooglePlayUserDetailViewModel: GooglePlayUserDetailViewModelProtocol {

    typealias ConnectionFactory = (GooglePlayCredentials) -> any GooglePlayUsersConnecting

    @Published var uiState: GooglePlayUserDetailUiState

    private let keychain: KeyStorable
    private let storage: PersistentStorable
    private let connectionFactory: ConnectionFactory
    private let analytics: AnalyticsTracking
    private var connection: (any GooglePlayUsersConnecting)?

    init(
        user: GooglePlayUserModel,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        storage: PersistentStorable? = nil,
        connectionFactory: @escaping ConnectionFactory = { GooglePlayAccountConnection(credentials: $0) },
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        let credentials: GooglePlayCredentials? = keychain.object(forKey: "credentials.\(account.id)")
        let serviceAccountEmail = credentials.flatMap { try? GooglePlayServiceAccount(credentials: $0).clientEmail }
        self.uiState = GooglePlayUserDetailUiState(account: account, user: user, serviceAccountEmail: serviceAccountEmail)
        self.keychain = keychain
        self.storage = storage ?? SwiftDataStorable.shared
        self.connectionFactory = connectionFactory
        self.analytics = analytics
        self.uiState.googleAccountEmail = GoogleLoginReferences.email(of: account, keychain: keychain)
    }

    // MARK: - Load

    /// The account's cached app list (names and icons). No request: the user
    /// came from the list that was just loaded.
    func load() async {
        if let stored = try? await storage.fetch(AccountModel.self, id: uiState.account.id) {
            uiState.account = stored
        }
        let apps = (try? await storage.fetch([GooglePlayAppItem].self, id: GooglePlayAppItem.cacheKey(accountId: uiState.account.id))) ?? []
        uiState.apps = apps
            .filter { uiState.account.allowsApp(bundleId: $0.packageName) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Account permissions

    func setAdmin(_ isOn: Bool) {
        if let refusal = uiState.access.accountPermissionsRefusal(for: uiState.user) {
            uiState.refusalMessage = GooglePlayUsersAccess.message(for: refusal)
            return
        }
        // Self-protection (U7): the service account keeps its own Admin.
        if !isOn, uiState.isSelf, uiState.user.isAdmin {
            uiState.refusalMessage = GooglePlayUsersAccess.message(for: .selfProtected)
            return
        }
        let admin = GooglePlayPermissionCatalog.adminPermission
        uiState.draftAccountPermissions.removeAll { $0 == admin }
        if isOn { uiState.draftAccountPermissions.append(admin) }
    }

    func setAccountPermission(_ permission: GooglePlayPermission, isOn: Bool) {
        guard uiState.canEditAccountPermissions else { return }
        uiState.draftAccountPermissions = GooglePlayPermissionCatalog.setting(
            permission, on: isOn, in: uiState.draftAccountPermissions, level: .account
        )
    }

    func save() async {
        analytics.track(.buttonTap(.save, on: .googlePlayUserDetail))
        let user = uiState.user
        guard uiState.hasChanges else { return }
        if let refusal = uiState.access.editRefusal(for: user) {
            uiState.refusalMessage = GooglePlayUsersAccess.message(for: refusal)
            return
        }
        let permissions = GooglePlayPermissionCatalog.normalized(uiState.draftAccountPermissions, level: .account)
        let permissionsChanged = Set(permissions) != Set(GooglePlayPermissionCatalog.normalized(user.developerAccountPermissions, level: .account))
        if permissionsChanged, let refusal = uiState.access.accountPermissionsRefusal(for: user) {
            uiState.refusalMessage = GooglePlayUsersAccess.message(for: refusal)
            return
        }
        // Self-protection holds on save too (U7).
        if user.isAdmin, !permissions.contains(GooglePlayPermissionCatalog.adminPermission), uiState.isSelf {
            uiState.refusalMessage = GooglePlayUsersAccess.message(for: .selfProtected)
            return
        }
        guard let (connection, developerId) = connectionAndDeveloperId() else { return }

        uiState.isSaving = true
        defer { uiState.isSaving = false }
        do {
            let updated = try await connection.updateUser(
                developerId: developerId,
                email: user.email,
                accountPermissions: permissions,
                expiration: uiState.draftExpiration
            )
            // Google's answer may leave out the grants: keep the ones we know.
            var merged = updated
            if merged.grants.isEmpty { merged.grants = user.grants }
            await apply(merged)
            uiState.toastMessage = ToastMessage(String(localized: "Permissions saved"))
            analytics.track(.action(.updateUserPermissions, on: .googlePlayUserDetail, result: .success))
        } catch {
            show(GooglePlayErrorTranslator.usersFailure(
                error, call: usersCall(.update, developerId: developerId, email: user.email), logTag: "GooglePlayUserDetail",
                authMethod: uiState.account.authMethod,
                accountEmail: uiState.googleAccountEmail
            ))
            analytics.track(.action(.updateUserPermissions, on: .googlePlayUserDetail, result: .failure))
        }
    }

    // MARK: - Remove

    func requestRemove() {
        analytics.track(.buttonTap(.remove, on: .googlePlayUserDetail))
        if let refusal = uiState.access.removeRefusal(for: uiState.user) {
            uiState.refusalMessage = GooglePlayUsersAccess.message(for: refusal)
        } else {
            uiState.confirmRemove = true
        }
    }

    func remove() async -> Bool {
        let user = uiState.user
        guard uiState.access.removeRefusal(for: user) == nil,
              let (connection, developerId) = connectionAndDeveloperId() else { return false }
        uiState.isSaving = true
        defer { uiState.isSaving = false }
        do {
            try await connection.deleteUser(developerId: developerId, email: user.email)
            await cacheStore.remove(email: user.email)
            analytics.track(.action(.deleteUser, on: .googlePlayUserDetail, result: .success))
            return true
        } catch {
            show(GooglePlayErrorTranslator.usersFailure(
                error, call: usersCall(.delete, developerId: developerId, email: user.email), logTag: "GooglePlayUserDetail",
                authMethod: uiState.account.authMethod,
                accountEmail: uiState.googleAccountEmail
            ))
            analytics.track(.action(.deleteUser, on: .googlePlayUserDetail, result: .failure))
            return false
        }
    }

    // MARK: - App access

    func saveGrant(packageName: String, permissions: [String]) async -> Bool {
        uiState.grantEditorError = nil
        let user = uiState.user
        if let refusal = uiState.access.grantRefusal(for: user, packageName: packageName) {
            uiState.refusalMessage = GooglePlayUsersAccess.message(for: refusal)
            return false
        }
        let normalized = GooglePlayPermissionCatalog.normalized(permissions, level: .app)
        guard !normalized.isEmpty else {
            show(GooglePlayUsersFailure(message: String(localized: "Turn on at least one permission for this app.")))
            return false
        }
        guard let (connection, developerId) = connectionAndDeveloperId() else { return false }
        uiState.isSaving = true
        defer { uiState.isSaving = false }
        do {
            let grant = try await connection.setGrant(developerId: developerId, email: user.email,
                                                      packageName: packageName, permissions: normalized)
            var updated = uiState.user
            updated.grants.removeAll { $0.packageName == packageName }
            updated.grants.append(grant)
            await apply(updated)
            uiState.toastMessage = ToastMessage(String(localized: "App access saved"))
            analytics.track(.action(.updateAppAccess, on: .googlePlayAppPermissions, result: .success))
            return true
        } catch {
            show(GooglePlayErrorTranslator.usersFailure(
                error,
                call: usersCall(.setGrant, developerId: developerId, email: user.email, packageName: packageName),
                logTag: "GooglePlayUserDetail",
                authMethod: uiState.account.authMethod,
                accountEmail: uiState.googleAccountEmail
            ))
            analytics.track(.action(.updateAppAccess, on: .googlePlayAppPermissions, result: .failure))
            return false
        }
    }

    func requestRemoveGrant(_ grant: GooglePlayGrantModel) {
        if let refusal = uiState.access.grantRefusal(for: uiState.user, packageName: grant.packageName) {
            uiState.refusalMessage = GooglePlayUsersAccess.message(for: refusal)
        } else {
            uiState.confirmRemoveGrant = grant
        }
    }

    func removeGrant(_ grant: GooglePlayGrantModel) async -> Bool {
        uiState.confirmRemoveGrant = nil
        uiState.grantEditorError = nil
        let user = uiState.user
        guard uiState.access.grantRefusal(for: user, packageName: grant.packageName) == nil,
              let (connection, developerId) = connectionAndDeveloperId() else { return false }
        uiState.isSaving = true
        defer { uiState.isSaving = false }
        do {
            try await connection.deleteGrant(developerId: developerId, email: user.email, packageName: grant.packageName)
            var updated = uiState.user
            updated.grants.removeAll { $0.packageName == grant.packageName }
            await apply(updated)
            uiState.toastMessage = ToastMessage(String(localized: "App access removed"))
            analytics.track(.action(.removeAppAccess, on: .googlePlayUserDetail, result: .success))
            return true
        } catch {
            show(GooglePlayErrorTranslator.usersFailure(
                error,
                call: usersCall(.deleteGrant, developerId: developerId, email: user.email, packageName: grant.packageName),
                logTag: "GooglePlayUserDetail",
                authMethod: uiState.account.authMethod,
                accountEmail: uiState.googleAccountEmail
            ))
            analytics.track(.action(.removeAppAccess, on: .googlePlayUserDetail, result: .failure))
            return false
        }
    }

    // MARK: - Private

    private func usersCall(
        _ method: GooglePlayUsersCall.Method,
        developerId: String,
        email: String,
        packageName: String? = nil
    ) -> GooglePlayUsersCall {
        GooglePlayUsersCall(method, developerId: developerId, email: email, packageName: packageName,
                            serviceAccountEmail: uiState.serviceAccountEmail)
    }

    /// In the App Permissions sheet while it's open, else in the error alert.
    private func show(_ failure: GooglePlayUsersFailure) {
        if uiState.grantEditor != nil {
            uiState.grantEditorError = failure
        } else {
            uiState.errorMessage = failure.message
            uiState.errorDetails = failure.technicalDetails
        }
    }

    private var cacheStore: GooglePlayUsersCacheStore {
        GooglePlayUsersCacheStore(storage: storage, accountId: uiState.account.id)
    }

    /// The saved user becomes the new baseline; the cache follows.
    private func apply(_ user: GooglePlayUserModel) async {
        uiState.user = user
        uiState.draftAccountPermissions = user.developerAccountPermissions
        uiState.draftExpiration = user.expirationTime
        await cacheStore.upsert(user)
    }

    private func connectionAndDeveloperId() -> (any GooglePlayUsersConnecting, String)? {
        guard let developerId = uiState.account.googlePlayDeveloperId else {
            show(GooglePlayUsersFailure(message: String(localized: "Add the Developer ID in Account Settings first.")))
            return nil
        }
        if let connection { return (connection, developerId) }
        guard let credentials: GooglePlayCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            Log.print.error("[GooglePlayUserDetail] No credentials found for account: \(self.uiState.account.name)")
            show(GooglePlayUsersFailure(message: String(localized: "No credentials found for this account.")))
            return nil
        }
        let made = connectionFactory(credentials)
        connection = made
        return (made, developerId)
    }
}
