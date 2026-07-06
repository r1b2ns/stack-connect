import Foundation
import StackProtocols

// MARK: - Role Catalog

/// Central definition of the ASC role taxonomy the UserDetail screen edits.
///
/// The ASC website models a member's access as **one primary (base) role** plus an
/// optional set of **additional resources** (add-on capabilities) and a
/// `provisioningAllowed` flag. Crucially, add-ons and provisioning are only valid
/// for the *app-management* base roles — assigning them to Admin/Finance/Sales/etc.
/// is rejected by the API with a 409 `ENTITY_ERROR.ATTRIBUTE.INVALID`. We mirror
/// that gating here so an invalid combination can never be submitted. All values
/// are the raw ASC strings passed verbatim to the core.
enum UserRoleCatalog {

    /// Mutually-exclusive primary roles the user can be assigned to (pick one).
    /// `ACCOUNT_HOLDER` is intentionally excluded — it is displayed but never
    /// assignable/selectable.
    static let assignablePrimaryRoles: [String] = [
        "ADMIN",
        "FINANCE",
        "SALES",
        "MARKETING",
        "APP_MANAGER",
        "DEVELOPER",
        "ACCESS_TO_REPORTS",
        "CUSTOMER_SUPPORT",
        "READ_ONLY",
    ]

    /// The non-assignable primary role. Shown for context but cannot be selected.
    static let accountHolder = "ACCOUNT_HOLDER"

    /// User-assignable add-on capabilities that can be layered on top of an
    /// app-management base role.
    ///
    /// The cloud-managed roles (`CLOUD_MANAGED_APP_DISTRIBUTION`,
    /// `CLOUD_MANAGED_DEVELOPER_ID`) are intentionally excluded: they are
    /// auto-assigned by Apple (Xcode Cloud / cloud-managed signing) and are not
    /// user-assignable, so we never offer them as editable toggles.
    static let additionalResources: [String] = [
        "CREATE_APPS",
        "GENERATE_INDIVIDUAL_KEYS",
    ]

    /// Cloud-managed roles that Apple auto-assigns. They may appear on a fetched
    /// user but must never be offered as editable add-ons nor emitted by the
    /// editor. We only preserve one across a save when the base role is unchanged
    /// (see `compose(primary:resources:preserving:)`).
    static let cloudManagedRoles: [String] = [
        "CLOUD_MANAGED_APP_DISTRIBUTION",
        "CLOUD_MANAGED_DEVELOPER_ID",
    ]

    /// All roles the app understands as a "primary" slot (assignable + account holder).
    static let allPrimaryRoles: [String] = [accountHolder] + assignablePrimaryRoles

    /// The base role → allowed add-on resources matrix. Any base role absent from
    /// this map supports **no** add-ons (and provisioning is forced off). This is
    /// the coarse gating we're confident about; the API validates finer details.
    private static let allowedResourcesByRole: [String: Set<String>] = [
        "DEVELOPER":   ["CREATE_APPS", "GENERATE_INDIVIDUAL_KEYS"],
        "APP_MANAGER": ["CREATE_APPS", "GENERATE_INDIVIDUAL_KEYS"],
        "MARKETING":   ["CREATE_APPS"],
    ]

    /// Base roles for which the `provisioningAllowed` flag is valid. Every other
    /// role must submit `provisioningAllowed = false`.
    private static let provisioningCapableRoles: Set<String> = [
        "DEVELOPER",
        "APP_MANAGER",
    ]

    private static let additionalResourceSet = Set(additionalResources)
    private static let cloudManagedSet = Set(cloudManagedRoles)
    private static let primaryRoleSet = Set(allPrimaryRoles)

    /// The add-on resources the given base role may carry, in catalog order.
    /// Empty for any non-app-management role (Admin, Finance, Sales, …).
    static func allowedResources(for primary: String?) -> [String] {
        guard let primary, let allowed = allowedResourcesByRole[primary] else { return [] }
        return additionalResources.filter { allowed.contains($0) }
    }

    /// Whether the base role supports any editable add-on resources at all.
    static func supportsAdditionalResources(_ primary: String?) -> Bool {
        !allowedResources(for: primary).isEmpty
    }

    /// Whether the base role may have `provisioningAllowed == true`.
    static func supportsProvisioning(_ primary: String?) -> Bool {
        guard let primary else { return false }
        return provisioningCapableRoles.contains(primary)
    }

    /// Splits a raw ASC `roles` array into (primary role, additional resources).
    /// The first recognised primary role wins; only *user-assignable* add-ons are
    /// surfaced as editable resources — cloud-managed and unknown values are
    /// ignored here (cloud-managed ones are preserved separately on save).
    static func split(_ roles: [String]) -> (primary: String?, resources: Set<String>) {
        let primary = roles.first { primaryRoleSet.contains($0) }
        let resources = Set(roles.filter { additionalResourceSet.contains($0) })
        return (primary, resources)
    }

    /// Composes the raw `roles` array to send to the API from an editable selection.
    ///
    /// Only add-ons that are valid for the chosen base role are emitted; anything
    /// else (invalid-for-role add-ons, cloud-managed roles) is dropped so an
    /// invalid combination can never reach the API.
    ///
    /// - Parameter preserving: raw roles from the user's *current* server state to
    ///   carry through. Used to keep an auto-assigned cloud-managed role when the
    ///   base role is unchanged; ignored entirely when the base role changes.
    static func compose(
        primary: String?,
        resources: Set<String>,
        preserving existingRoles: [String] = []
    ) -> [String] {
        var result: [String] = []
        if let primary { result.append(primary) }

        // Only add-ons valid for this base role, in stable catalog order.
        let valid = Set(allowedResources(for: primary))
        result.append(contentsOf: additionalResources.filter { resources.contains($0) && valid.contains($0) })

        // Preserve any cloud-managed role Apple auto-assigned, but only when the
        // base role is unchanged — a cloud-managed capability is meaningless once
        // the primary role changes, so we drop it and let the API re-derive it.
        let (existingPrimary, _) = split(existingRoles)
        if let primary, existingPrimary == primary {
            let cloud = existingRoles.filter { cloudManagedSet.contains($0) }
            result.append(contentsOf: cloudManagedRoles.filter { cloud.contains($0) })
        }

        return result
    }

    /// Concise, localized explanation of what a role grants. Used by the
    /// permissions bottom sheet (pure presentation).
    static func permissionDescription(for role: String) -> String {
        switch role {
        case "ACCOUNT_HOLDER":
            return String(localized: "Full access to everything, including legal agreements and banking. There is exactly one Account Holder per team.")
        case "ADMIN":
            return String(localized: "Manage most areas, including users, apps and agreements. Cannot change the Account Holder.")
        case "FINANCE":
            return String(localized: "Access financial reports, sales and payments. Manage banking and tax details.")
        case "SALES":
            return String(localized: "View sales and download reports. Read-only access to app data.")
        case "MARKETING":
            return String(localized: "Manage marketing metadata, promotional artwork and App Store presence.")
        case "APP_MANAGER":
            return String(localized: "Manage apps, builds, TestFlight and submissions for the apps they can access.")
        case "DEVELOPER":
            return String(localized: "Manage builds, certificates and provisioning. Cannot submit apps for review.")
        case "ACCESS_TO_REPORTS":
            return String(localized: "Download sales, finance and payment reports only. No other access.")
        case "CUSTOMER_SUPPORT":
            return String(localized: "Respond to customer reviews and view app analytics.")
        case "READ_ONLY":
            return String(localized: "View-only access to App Store Connect. Cannot make any changes.")
        case "CREATE_APPS":
            return String(localized: "Create new apps and bundle identifiers.")
        case "CLOUD_MANAGED_APP_DISTRIBUTION":
            return String(localized: "Use Xcode Cloud to sign and distribute apps automatically.")
        case "CLOUD_MANAGED_DEVELOPER_ID":
            return String(localized: "Use cloud-managed Developer ID signing for macOS apps.")
        case "GENERATE_INDIVIDUAL_KEYS":
            return String(localized: "Create individual App Store Connect API keys for automation.")
        default:
            return String(localized: "Grants additional access in App Store Connect.")
        }
    }
}

// MARK: - Protocol

@MainActor
protocol UserDetailViewModelProtocol: ObservableObject {
    var uiState: UserDetailUiState { get set }

    /// Selects a new primary (base) role and immediately reconciles the dependent
    /// selection: any add-on resource not valid for the new role is dropped, and
    /// `provisioningAllowed` is forced to `false` when the new role can't have it.
    /// This guarantees an invalid combination can never be submitted.
    func selectPrimaryRole(_ role: String)

    /// Loads the user's current visible-apps selection and the account's apps.
    /// Only meaningful when `allAppsVisible == false`; safe to call otherwise.
    func loadVisibleApps() async

    /// Persists the edited primary role. Returns `true` on success.
    @discardableResult
    func saveRole() async -> Bool

    /// Persists the edited additional resources + access flags. Returns `true` on success.
    @discardableResult
    func saveResources() async -> Bool

    /// Persists the edited visible-apps selection (full replace). Returns `true` on success.
    @discardableResult
    func saveVisibleApps() async -> Bool

    /// Deletes the user (removes member or cancels invitation). Returns `true` on
    /// success so the View can pop back.
    @discardableResult
    func deleteUser() async -> Bool
}

// MARK: - UiState

struct UserDetailUiState {
    var user: UserModel

    // Editing — role & resources
    var selectedPrimaryRole: String?
    var selectedResources: Set<String> = []
    var allAppsVisible: Bool
    var provisioningAllowed: Bool

    // Visible apps
    var availableApps: [StackProtocols.AppInfo] = []
    var selectedAppIds: Set<String> = []
    var isLoadingVisibleApps = false
    var visibleAppsLoaded = false

    // Presentation flags (sheets / alerts)
    var showRoleEditor = false
    var showResourcesEditor = false
    var showPermissions = false
    var showVisibleAppsEditor = false
    var confirmDelete = false

    // Feedback
    var isSaving = false
    var toastMessage: ToastMessage?
    var errorMessage: String?

    // MARK: Guards

    /// Pending invitations cannot be edited via the ASC API — only cancelled (deleted).
    var isPending: Bool { user.isPending }

    /// The Account Holder cannot be deleted and its primary role cannot be changed.
    var isAccountHolder: Bool { user.roles.contains(UserRoleCatalog.accountHolder) }

    /// True when any edit action is allowed at all (active, non-pending user).
    var canEdit: Bool { !isPending }

    /// True when the primary role can be changed.
    var canEditRole: Bool { canEdit && !isAccountHolder }

    /// True when the delete/cancel action is allowed.
    var canDelete: Bool { !isAccountHolder }

    /// Visible-apps editing only makes sense when the user is NOT scoped to all apps.
    var canEditVisibleApps: Bool { canEdit && !allAppsVisible }
}

// MARK: - Implementation

@MainActor
final class UserDetailViewModel: UserDetailViewModelProtocol {

    @Published var uiState: UserDetailUiState

    private let account: AccountModel
    private let keychain: KeyStorable
    /// Injected service seam. When `nil`, a real `AppleAccountConnection` is
    /// resolved from keychain credentials on demand (see `resolveService`).
    private let injectedService: UserManaging?

    init(
        user: UserModel,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        service: UserManaging? = nil
    ) {
        let (primary, resources) = UserRoleCatalog.split(user.roles)
        self.uiState = UserDetailUiState(
            user: user,
            selectedPrimaryRole: primary,
            selectedResources: resources,
            allAppsVisible: user.allAppsVisible,
            provisioningAllowed: user.provisioningAllowed
        )
        self.account = account
        self.keychain = keychain
        self.injectedService = service
    }

    // MARK: - Service resolution

    /// Returns the injected service (tests) or builds a real connection from the
    /// account's stored credentials. Sets `uiState.errorMessage` and returns `nil`
    /// when no credentials are available.
    private func resolveService() -> UserManaging? {
        if let injectedService {
            return injectedService
        }
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(account.id)") else {
            uiState.errorMessage = String(localized: "No credentials found for this account.")
            Log.print.error("[UserDetail] No credentials for account \(self.account.id)")
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }

    // MARK: - Role selection

    func selectPrimaryRole(_ role: String) {
        uiState.selectedPrimaryRole = role
        reconcileSelectionForCurrentRole()
    }

    /// Drops any selected add-on not valid for the current base role and forces
    /// `provisioningAllowed = false` when the role can't support it. Called on
    /// every role change so the editor never holds an invalid combination.
    private func reconcileSelectionForCurrentRole() {
        let primary = uiState.selectedPrimaryRole
        let allowed = Set(UserRoleCatalog.allowedResources(for: primary))
        uiState.selectedResources.formIntersection(allowed)
        if !UserRoleCatalog.supportsProvisioning(primary) {
            uiState.provisioningAllowed = false
        }
    }

    // MARK: - Visible Apps

    func loadVisibleApps() async {
        // Nothing to scope when the user already sees all apps, or when the user
        // is a pending invite (cannot be edited anyway).
        guard uiState.canEditVisibleApps else { return }
        guard !uiState.isLoadingVisibleApps else { return }
        guard let service = resolveService() else { return }

        uiState.isLoadingVisibleApps = true
        do {
            async let appsCall = service.fetchApps()
            async let selectedCall = service.fetchUserVisibleApps(id: uiState.user.id)
            let (apps, selected) = try await (appsCall, selectedCall)
            uiState.availableApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            uiState.selectedAppIds = Set(selected)
            uiState.visibleAppsLoaded = true
            Log.print.info("[UserDetail] Loaded \(apps.count) apps, \(selected.count) selected")
        } catch {
            handle(error, fallback: String(localized: "Failed to load apps"))
            Log.print.error("[UserDetail] Load visible apps failed: \(error.localizedDescription)")
        }
        uiState.isLoadingVisibleApps = false
    }

    // MARK: - Save Role

    @discardableResult
    func saveRole() async -> Bool {
        guard uiState.canEditRole else { return false }
        guard let primary = uiState.selectedPrimaryRole else {
            uiState.errorMessage = String(localized: "Select a role before saving.")
            return false
        }
        // Belt-and-braces: never emit provisioning for a role that can't have it,
        // even if the flag lingered from a previous selection.
        let provisioning = uiState.provisioningAllowed && UserRoleCatalog.supportsProvisioning(primary)
        return await performUpdate(
            roles: UserRoleCatalog.compose(
                primary: primary,
                resources: uiState.selectedResources,
                preserving: uiState.user.roles
            ),
            allAppsVisible: uiState.allAppsVisible,
            provisioningAllowed: provisioning,
            successMessage: String(localized: "Role updated"),
            successIcon: "person.badge.shield.checkmark",
            onSuccess: { self.uiState.showRoleEditor = false }
        )
    }

    // MARK: - Save Resources & Flags

    @discardableResult
    func saveResources() async -> Bool {
        guard uiState.canEdit else { return false }
        // Account Holder role stays whatever it was; for everyone else we compose
        // from the selected primary role. This keeps the primary role intact when
        // only additional resources / access flags change. `preserving:` carries
        // through any auto-assigned cloud-managed role since the base role is
        // unchanged on this path.
        let primary = uiState.selectedPrimaryRole
        let roles = UserRoleCatalog.compose(
            primary: primary,
            resources: uiState.selectedResources,
            preserving: uiState.user.roles
        )
        // Never emit provisioning for a role that can't have it.
        let provisioning = uiState.provisioningAllowed && UserRoleCatalog.supportsProvisioning(primary)
        return await performUpdate(
            roles: roles,
            allAppsVisible: uiState.allAppsVisible,
            provisioningAllowed: provisioning,
            successMessage: String(localized: "Access updated"),
            successIcon: "checkmark.circle.fill",
            onSuccess: { self.uiState.showResourcesEditor = false }
        )
    }

    /// Shared update path for role / resources / flags. Optimistically updates
    /// `uiState.user` on success so the screen reflects changes without a reload.
    @discardableResult
    private func performUpdate(
        roles: [String],
        allAppsVisible: Bool,
        provisioningAllowed: Bool,
        successMessage: String,
        successIcon: String,
        onSuccess: @escaping () -> Void
    ) async -> Bool {
        guard let service = resolveService() else { return false }

        uiState.isSaving = true
        defer { uiState.isSaving = false }
        do {
            try await service.updateUser(
                id: uiState.user.id,
                roles: roles,
                allAppsVisible: allAppsVisible,
                provisioningAllowed: provisioningAllowed
            )
            // Optimistic local update — no full reload needed.
            uiState.user.roles = roles
            uiState.user.allAppsVisible = allAppsVisible
            uiState.user.provisioningAllowed = provisioningAllowed
            let (primary, resources) = UserRoleCatalog.split(roles)
            uiState.selectedPrimaryRole = primary
            uiState.selectedResources = resources
            uiState.toastMessage = ToastMessage(successMessage, icon: successIcon)
            onSuccess()
            Log.print.info("[UserDetail] Updated user \(self.uiState.user.id)")
            return true
        } catch {
            handle(error, fallback: String(localized: "Failed to update user"))
            Log.print.error("[UserDetail] Update failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Save Visible Apps

    @discardableResult
    func saveVisibleApps() async -> Bool {
        guard uiState.canEditVisibleApps else { return false }
        guard let service = resolveService() else { return false }

        uiState.isSaving = true
        defer { uiState.isSaving = false }
        do {
            // Full replace — always send the complete desired set.
            try await service.updateUserVisibleApps(
                id: uiState.user.id,
                appIds: Array(uiState.selectedAppIds)
            )
            uiState.toastMessage = ToastMessage(String(localized: "Visible apps updated"), icon: "square.grid.2x2.fill")
            uiState.showVisibleAppsEditor = false
            Log.print.info("[UserDetail] Updated visible apps for user \(self.uiState.user.id) (\(self.uiState.selectedAppIds.count))")
            return true
        } catch {
            handle(error, fallback: String(localized: "Failed to update visible apps"))
            Log.print.error("[UserDetail] Update visible apps failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Delete

    @discardableResult
    func deleteUser() async -> Bool {
        guard uiState.canDelete else { return false }
        guard let service = resolveService() else { return false }

        uiState.isSaving = true
        defer { uiState.isSaving = false }
        do {
            try await service.deleteUser(id: uiState.user.id, isPending: uiState.user.isPending)
            Log.print.info("[UserDetail] Deleted user \(self.uiState.user.id) (isPending: \(self.uiState.user.isPending))")
            return true
        } catch {
            if AppleAPIErrorTranslator.isForbidden(error) {
                uiState.errorMessage = String(localized: "Your App Store Connect API key isn't allowed to remove users. Managing Users and Access requires a key with the Admin role. Update the key's permissions in App Store Connect (Users and Access → Integrations) and try again.")
            } else {
                // Surface Apple's specific message (e.g. NOT_FOUND / state conflicts)
                // rather than a flat "Failed to remove user".
                let message = AppleAPIErrorTranslator.friendlyMessage(for: error)
                uiState.errorMessage = message.isEmpty ? String(localized: "Failed to remove user") : message
            }
            Log.print.error("[UserDetail] Delete failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Error handling

    /// Maps a thrown error to a user-facing message, using the shared 403 copy for
    /// forbidden (missing Admin key) cases across every edit path. For every other
    /// error we defer to `AppleAPIErrorTranslator.friendlyMessage`, which surfaces
    /// Apple's specific `detail` for role/attribute 409s (e.g. "The user can't have
    /// provisioning privilege.") instead of a generic fallback. The `fallback` is
    /// used only when the translator yields an empty string.
    private func handle(_ error: Error, fallback: String) {
        if AppleAPIErrorTranslator.isForbidden(error) {
            uiState.errorMessage = String(localized: "Your App Store Connect API key isn't allowed to manage users. Managing Users and Access requires a key with the Admin role. Update the key's permissions in App Store Connect (Users and Access → Integrations) and try again.")
        } else {
            let message = AppleAPIErrorTranslator.friendlyMessage(for: error)
            uiState.errorMessage = message.isEmpty ? fallback : message
        }
    }
}
