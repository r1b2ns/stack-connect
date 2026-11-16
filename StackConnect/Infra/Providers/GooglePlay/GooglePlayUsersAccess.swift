import Foundation

/// What this account may do on the Google Play Users screens (plan U6, U7),
/// in one testable place. The Views hide entry points with it; the ViewModels
/// re-check it before every write (source of truth).
///
/// - Rules, as for App Store Connect: `canView(.users)` shows the tab,
///   `canAdd` invites, `canEdit` changes permissions and app access,
///   `canDelete` removes. Resend (delete + invite again) needs both.
/// - Per-app scope of an imported account (`appsBundles`): it may only grant
///   apps inside the scope, can't change account-wide permissions (they reach
///   every app) and can't remove a user whose access reaches outside it.
/// - Self-protection (U7): the calling service account (by `client_email`) can't
///   be removed nor lose its own Admin permission — it would lock this account
///   out of the tab, and of everything else when it removes itself.
struct GooglePlayUsersAccess: Equatable {

    let account: AccountModel
    /// The service account's `client_email`; `nil` when the key can't be read.
    let serviceAccountEmail: String?

    var canView: Bool { account.canView(.users) }
    var canInvite: Bool { account.canAdd(.users) }
    var canEdit: Bool { account.canEdit(.users) }
    var canDelete: Bool { account.canDelete(.users) }

    /// The account is limited to some apps.
    var isScoped: Bool { !(account.appsBundles ?? []).isEmpty }

    /// Account-wide permissions apply to every app, so a scoped account can't set them.
    var canEditAccountPermissions: Bool { canEdit && !isScoped }

    /// Account-wide permissions on an invitation.
    var canInviteWithAccountPermissions: Bool { canInvite && !isScoped }

    func allowsApp(_ packageName: String) -> Bool {
        account.allowsApp(bundleId: packageName)
    }

    func isSelf(_ user: GooglePlayUserModel) -> Bool {
        guard let serviceAccountEmail else { return false }
        return user.matches(email: serviceAccountEmail)
    }

    /// Why a change to `user` is refused, `nil` when it is allowed.
    enum Refusal: Equatable {
        /// The account's `users` rules don't allow it.
        case notPermitted
        /// The calling service account itself (U7).
        case selfProtected
        /// The user's access reaches apps outside this account's scope, or
        /// Google didn't return all of it (`partial`).
        case outsideScope
    }

    func editRefusal(for user: GooglePlayUserModel) -> Refusal? {
        guard canEdit else { return .notPermitted }
        if user.partial { return .outsideScope }
        return nil
    }

    /// Account-wide permissions of `user` (Admin included).
    func accountPermissionsRefusal(for user: GooglePlayUserModel) -> Refusal? {
        if let refusal = editRefusal(for: user) { return refusal }
        return isScoped ? .outsideScope : nil
    }

    /// Turning off `user`'s Admin permission.
    func removeAdminRefusal(for user: GooglePlayUserModel) -> Refusal? {
        if let refusal = accountPermissionsRefusal(for: user) { return refusal }
        return isSelf(user) ? .selfProtected : nil
    }

    /// Adding, changing or removing `user`'s access to `packageName`.
    func grantRefusal(for user: GooglePlayUserModel, packageName: String) -> Refusal? {
        if let refusal = editRefusal(for: user) { return refusal }
        return allowsApp(packageName) ? nil : .outsideScope
    }

    func removeRefusal(for user: GooglePlayUserModel) -> Refusal? {
        guard canDelete else { return .notPermitted }
        if isSelf(user) { return .selfProtected }
        if isScoped, user.partial || user.hasAllAppsAccess || user.grants.contains(where: { !allowsApp($0.packageName) }) {
            return .outsideScope
        }
        return nil
    }

    /// Resend (plan U8): only an expired invitation, and only with the rights
    /// to both remove it and invite again.
    func resendRefusal(for user: GooglePlayUserModel) -> Refusal? {
        guard user.accessState == .invitationExpired, canInvite else { return .notPermitted }
        if let refusal = removeRefusal(for: user) { return refusal }
        if user.hasAllAppsAccess, !canInviteWithAccountPermissions { return .outsideScope }
        return nil
    }

    /// The explanation shown when a change is refused.
    static func message(for refusal: Refusal) -> String {
        switch refusal {
        case .notPermitted:
            return String(localized: "This account doesn't have permission to make this change.")
        case .selfProtected:
            return String(localized: "This is the service account StackConnect uses for this account. Removing it, or its Admin permission, would lock StackConnect out of this developer account. Make the change in Play Console if you really need to.")
        case .outsideScope:
            return String(localized: "This user has access to apps outside the ones shared with this account, so the change has to be made in Play Console.")
        }
    }
}
