import Foundation

/// The Invite User sheet's draft (plan U6, prototype 21), kept apart from the
/// view so its rules are testable: e-mail, expiry, preset, account-level
/// permissions and per-app access.
struct GooglePlayInviteForm: Equatable {

    var email = ""
    var expiration: Date?
    /// The chip shown as selected. Presets only pre-fill the toggles (U5); a
    /// manual change selects whichever preset matches, or Custom.
    private(set) var preset: GooglePlayPermissionPreset = .custom
    private(set) var accountPermissions: [String] = []
    private(set) var grants: [GooglePlayGrantModel] = []

    var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isAdmin: Bool {
        accountPermissions.contains(GooglePlayPermissionCatalog.adminPermission)
    }

    mutating func apply(_ preset: GooglePlayPermissionPreset) {
        self.preset = preset
        if let values = preset.accountPermissions {
            accountPermissions = values
        }
    }

    mutating func setAdmin(_ isOn: Bool) {
        let admin = GooglePlayPermissionCatalog.adminPermission
        accountPermissions.removeAll { $0 == admin }
        if isOn { accountPermissions.append(admin) }
        preset = .matching(accountPermissions)
    }

    mutating func set(_ permission: GooglePlayPermission, isOn: Bool) {
        guard accountState(of: permission) != .implied else { return }
        accountPermissions = GooglePlayPermissionCatalog.setting(permission, on: isOn, in: accountPermissions, level: .account)
        preset = .matching(accountPermissions)
    }

    func accountState(of permission: GooglePlayPermission) -> GooglePlayPermissionCatalog.Effective {
        GooglePlayPermissionCatalog.accountState(of: permission, in: accountPermissions)
    }

    /// Adds or replaces the access to one app.
    mutating func setGrant(packageName: String, values: [String]) {
        grants.removeAll { $0.packageName == packageName }
        grants.append(GooglePlayGrantModel(packageName: packageName,
                                           appLevelPermissions: GooglePlayPermissionCatalog.normalized(values, level: .app)))
    }

    mutating func removeGrant(packageName: String) {
        grants.removeAll { $0.packageName == packageName }
    }

    /// What is sent to Google.
    var normalizedAccountPermissions: [String] {
        GooglePlayPermissionCatalog.normalized(accountPermissions, level: .account)
    }

    // MARK: - Validation

    var isEmailValid: Bool {
        trimmedEmail.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    /// Something to grant: a user with no account permission and no app sees nothing.
    var hasAccess: Bool {
        !accountPermissions.isEmpty || !grants.isEmpty
    }

    var canSend: Bool {
        isEmailValid && hasAccess
    }

    /// Why Send is off, for the footer; `nil` when it can be sent.
    var blockingReason: String? {
        if trimmedEmail.isEmpty { return nil }
        if !isEmailValid { return String(localized: "Enter a valid e-mail address.") }
        if !hasAccess { return String(localized: "Turn on an account permission or add an app.") }
        return nil
    }
}
