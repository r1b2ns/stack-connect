import Foundation

// MARK: - Group

/// How permissions are grouped on screen (prototype 22).
enum GooglePlayPermissionGroup: String, CaseIterable, Hashable, Sendable {
    case appAccess
    case releases
    case storePresence
    case usersAndFeedback
    case monetization

    var title: String {
        switch self {
        case .appAccess:        return String(localized: "App access", comment: "Google Play permission group.")
        case .releases:         return String(localized: "Releases", comment: "Google Play permission group.")
        case .storePresence:    return String(localized: "Store presence", comment: "Google Play permission group.")
        case .usersAndFeedback: return String(localized: "Users & feedback", comment: "Google Play permission group.")
        case .monetization:     return String(localized: "Monetization", comment: "Google Play permission group.")
        }
    }
}

// MARK: - Permission

/// One Google Play permission, with its account-level (`CAN_…_GLOBAL`) and
/// app-level (`CAN_…`) wire values when Google has both.
struct GooglePlayPermission: Hashable, Identifiable, Sendable {
    /// Stable app-side key.
    let id: String
    let group: GooglePlayPermissionGroup
    /// `developerAccountPermissions` value, `nil` when only granted per app.
    let accountLevel: String?
    /// `appLevelPermissions` value, `nil` when account-wide only.
    let appLevel: String?
    /// Name on the account-level lists.
    let accountName: String
    /// Name on the per-app lists, when it differs ("Edit draft app").
    let appName: String
    /// Deprecated values Google still returns for the same permission
    /// (`CAN_SEE_ALL_APPS`, `CAN_ACCESS_APP`): read as this permission, kept on save.
    var legacyValues: Set<String> = []

    func value(for level: GooglePlayPermissionLevel) -> String? {
        level == .account ? accountLevel : appLevel
    }

    func name(for level: GooglePlayPermissionLevel) -> String {
        level == .account ? accountName : appName
    }
}

enum GooglePlayPermissionLevel: Sendable {
    /// `developerAccountPermissions`: every app of the account.
    case account
    /// `grants[].appLevelPermissions`: one app.
    case app
}

// MARK: - Catalog

/// The one list of Google Play permissions (plan U4), mirroring `UserRoleCatalog`:
/// names, groups, account ↔ app pairing and implications, for the users list,
/// user detail, invite and app-permission screens.
///
/// Rules:
/// - Admin (`CAN_MANAGE_PERMISSIONS_GLOBAL`) implies every permission for every
///   app; the app-level `CAN_MANAGE_PERMISSIONS` implies every permission of that app.
/// - Any permission implies "View app information" (it is added on save).
/// - Values the catalog doesn't know are preserved on save and listed as "Other".
enum GooglePlayPermissionCatalog {

    static let adminPermission = "CAN_MANAGE_PERMISSIONS_GLOBAL"
    static let appAdminPermission = "CAN_MANAGE_PERMISSIONS"

    static let viewAppInformation = GooglePlayPermission(
        id: "viewAppInformation", group: .appAccess,
        accountLevel: "CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL", appLevel: "CAN_VIEW_NON_FINANCIAL_DATA",
        accountName: String(localized: "View app information", comment: "Google Play permission."),
        appName: String(localized: "View app information", comment: "Google Play permission."),
        legacyValues: ["CAN_SEE_ALL_APPS", "CAN_ACCESS_APP"]
    )

    static let manageUsers = GooglePlayPermission(
        id: "manageUsers", group: .usersAndFeedback,
        accountLevel: nil, appLevel: appAdminPermission,
        accountName: String(localized: "Manage users for this app", comment: "Google Play app-level permission (admin of one app)."),
        appName: String(localized: "Manage users for this app", comment: "Google Play app-level permission (admin of one app).")
    )

    /// Every known permission except account Admin (a toggle of its own), in display order.
    static let all: [GooglePlayPermission] = [
        viewAppInformation,
        permission("viewFinancialData", .appAccess, "CAN_VIEW_FINANCIAL_DATA_GLOBAL", "CAN_VIEW_FINANCIAL_DATA",
                   String(localized: "View financial data", comment: "Google Play permission.")),
        permission("viewAppQuality", .appAccess, "CAN_VIEW_APP_QUALITY_GLOBAL", "CAN_VIEW_APP_QUALITY",
                   String(localized: "View app quality (Vitals)", comment: "Google Play permission.")),
        permission("viewConnectedApps", .appAccess, "CAN_VIEW_CONNECTED_APPS_GLOBAL", nil,
                   String(localized: "View connected apps", comment: "Google Play permission.")),
        permission("editConnectedApps", .appAccess, "CAN_EDIT_CONNECTED_APPS_GLOBAL", nil,
                   String(localized: "Edit connected apps", comment: "Google Play permission.")),
        permission("releaseToProduction", .releases, "CAN_MANAGE_PUBLIC_APKS_GLOBAL", "CAN_MANAGE_PUBLIC_APKS",
                   String(localized: "Release to production", comment: "Google Play permission.")),
        permission("releaseToTesting", .releases, "CAN_MANAGE_TRACK_APKS_GLOBAL", "CAN_MANAGE_TRACK_APKS",
                   String(localized: "Release to testing tracks", comment: "Google Play permission.")),
        permission("manageTesters", .releases, "CAN_MANAGE_TRACK_USERS_GLOBAL", "CAN_MANAGE_TRACK_USERS",
                   String(localized: "Manage testing tracks and testers", comment: "Google Play permission.")),
        permission("draftApps", .releases, "CAN_MANAGE_DRAFT_APPS_GLOBAL", "CAN_MANAGE_DRAFT_APPS",
                   String(localized: "Create and edit draft apps", comment: "Google Play account-level permission."),
                   appName: String(localized: "Edit draft app", comment: "Google Play app-level permission.")),
        permission("privateApps", .releases, "CAN_CREATE_MANAGED_PLAY_APPS_GLOBAL", nil,
                   String(localized: "Create and publish private apps", comment: "Google Play permission.")),
        permission("editGames", .releases, "CAN_EDIT_GAMES_GLOBAL", nil,
                   String(localized: "Edit Play Games projects", comment: "Google Play permission.")),
        permission("publishGames", .releases, "CAN_PUBLISH_GAMES_GLOBAL", nil,
                   String(localized: "Publish Play Games projects", comment: "Google Play permission.")),
        permission("storePresence", .storePresence, "CAN_MANAGE_PUBLIC_LISTING_GLOBAL", "CAN_MANAGE_PUBLIC_LISTING",
                   String(localized: "Manage store presence", comment: "Google Play permission.")),
        permission("policyDeclarations", .storePresence, "CAN_MANAGE_APP_CONTENT_GLOBAL", "CAN_MANAGE_APP_CONTENT",
                   String(localized: "Manage policy declarations", comment: "Google Play permission.")),
        permission("deepLinks", .storePresence, "CAN_MANAGE_DEEPLINKS_GLOBAL", "CAN_MANAGE_DEEPLINKS",
                   String(localized: "Manage deep links", comment: "Google Play permission.")),
        permission("replyToReviews", .usersAndFeedback, "CAN_REPLY_TO_REVIEWS_GLOBAL", "CAN_REPLY_TO_REVIEWS",
                   String(localized: "Reply to reviews", comment: "Google Play permission.")),
        manageUsers,
        permission("orders", .monetization, "CAN_MANAGE_ORDERS_GLOBAL", "CAN_MANAGE_ORDERS",
                   String(localized: "Manage orders and subscriptions", comment: "Google Play permission."))
    ]

    /// Account-level permissions always listed on the user detail and invite
    /// sheet (prototypes 17 / 21); the others sit behind "More Permissions"
    /// unless they are on.
    static let commonAccountPermissionIds: Set<String> = [
        "viewAppInformation", "viewFinancialData", "viewAppQuality", "replyToReviews", "orders", "draftApps"
    ]

    /// Permissions that can be granted account-wide (Admin excluded), in display order.
    static var accountPermissions: [GooglePlayPermission] {
        all.filter { $0.accountLevel != nil }
    }

    /// Permissions that can be granted for one app, in display order.
    static var appPermissions: [GooglePlayPermission] {
        all.filter { $0.appLevel != nil }
    }

    /// `permissions(for:)` split by group, empty groups left out.
    static func grouped(_ level: GooglePlayPermissionLevel) -> [(group: GooglePlayPermissionGroup, permissions: [GooglePlayPermission])] {
        let list = level == .account ? accountPermissions : appPermissions
        return GooglePlayPermissionGroup.allCases.compactMap { group in
            let items = list.filter { $0.group == group }
            return items.isEmpty ? nil : (group, items)
        }
    }

    static func permission(forValue value: String) -> GooglePlayPermission? {
        all.first { $0.accountLevel == value || $0.appLevel == value || $0.legacyValues.contains(value) }
    }

    // MARK: - Reading a permission set

    /// `permission` is explicitly in `values` (its own value or a legacy alias).
    static func contains(_ permission: GooglePlayPermission, in values: [String], level: GooglePlayPermissionLevel) -> Bool {
        guard let value = permission.value(for: level) else { return false }
        return values.contains(value) || !permission.legacyValues.isDisjoint(with: values)
    }

    /// Values the catalog doesn't know (kept on save, listed as "Other").
    static func unknownValues(in values: [String]) -> [String] {
        values.filter { value in
            value != adminPermission && permission(forValue: value) == nil
        }
    }

    /// "CAN_CHANGE_MANAGED_PLAY_SETTING_GLOBAL" → "Change managed play setting".
    static func displayName(forUnknown value: String) -> String {
        var words = value.lowercased().split(separator: "_").map(String.init)
        if words.first == "can" { words.removeFirst() }
        if words.last == "global" { words.removeLast() }
        let sentence = words.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    /// Short name of any value, known or not.
    static func displayName(forValue value: String, level: GooglePlayPermissionLevel) -> String {
        if value == adminPermission { return adminName }
        return permission(forValue: value)?.name(for: level) ?? displayName(forUnknown: value)
    }

    static var adminName: String {
        String(localized: "Admin (all permissions)", comment: "Google Play account-level Admin permission.")
    }

    // MARK: - Editing a permission set

    /// `values` with `permission` turned on or off. Turning a permission off also
    /// drops its legacy aliases; every other value (unknown ones included) stays.
    static func setting(
        _ permission: GooglePlayPermission,
        on isOn: Bool,
        in values: [String],
        level: GooglePlayPermissionLevel
    ) -> [String] {
        guard let value = permission.value(for: level) else { return values }
        var result = values.filter { $0 != value && !permission.legacyValues.contains($0) }
        if isOn { result.append(value) }
        return result
    }

    /// What is sent to Google: duplicates removed, "View app information"
    /// added when any other permission is on (plan U4).
    static func normalized(_ values: [String], level: GooglePlayPermissionLevel) -> [String] {
        var seen = Set<String>()
        var result = values.filter { seen.insert($0).inserted }
        guard let view = viewAppInformation.value(for: level) else { return result }
        let hasView = contains(viewAppInformation, in: result, level: level)
        if !hasView && !result.isEmpty {
            result.insert(view, at: 0)
        }
        return result
    }

    // MARK: - Implications

    /// Whether `permission` is effectively on for one app, and why it can't be
    /// turned off there.
    enum Effective: Equatable {
        case off
        case on
        /// On because of something else; the toggle is locked.
        case implied
    }

    /// The state of an account-level toggle in `values`.
    static func accountState(of permission: GooglePlayPermission, in values: [String]) -> Effective {
        if values.contains(adminPermission) { return .implied }
        let explicit = contains(permission, in: values, level: .account)
        if permission == viewAppInformation, hasOtherThanView(values, level: .account) { return .implied }
        return explicit ? .on : .off
    }

    /// The state of an app-level toggle for one app: `appValues` are the
    /// grant's permissions, `accountValues` the user's account-wide ones (which
    /// apply to every app and can't be turned off per app).
    static func appState(of permission: GooglePlayPermission, appValues: [String], accountValues: [String]) -> Effective {
        if accountValues.contains(adminPermission) { return .implied }
        if permission != manageUsers, appValues.contains(appAdminPermission) { return .implied }
        if contains(permission, in: accountValues, level: .account) { return .implied }
        if permission == viewAppInformation,
           hasOtherThanView(appValues, level: .app) || hasOtherThanView(accountValues, level: .account) {
            return .implied
        }
        return contains(permission, in: appValues, level: .app) ? .on : .off
    }

    /// Any value other than "View app information" (known or not).
    private static func hasOtherThanView(_ values: [String], level: GooglePlayPermissionLevel) -> Bool {
        values.contains { value in
            value != viewAppInformation.value(for: level) && !viewAppInformation.legacyValues.contains(value)
        }
    }

    // MARK: - Summary

    /// One line about what a user can do, for the users list (prototype 16):
    /// "Admin (all permissions)", "Reply to reviews · 1 app", "Releases, Store
    /// presence · 2 apps", "Service account · Releases", "… · expires Dec 31, 2026".
    static func summary(for user: GooglePlayUserModel, now: Date = Date()) -> String {
        var parts: [String] = []
        if user.isServiceAccount {
            parts.append(String(localized: "Service account", comment: "Google Play users list: the user is a Google Cloud service account."))
        }
        if user.isAdmin {
            parts.append(adminName)
        } else {
            parts.append(permissionsSummary(for: user))
            if !user.hasAllAppsAccess, !user.grants.isEmpty {
                parts.append(appCount(user.grants.count))
            }
        }
        if let expiration = user.expirationTime {
            let date = expiration.formatted(date: .abbreviated, time: .omitted)
            parts.append(expiration > now
                         ? String(localized: "expires \(date)", comment: "Google Play users list: access expiry date.")
                         : String(localized: "expired \(date)", comment: "Google Play users list: access expired on this date."))
        }
        return parts.joined(separator: " · ")
    }

    /// "1 app" / "3 apps".
    static func appCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 app", comment: "Google Play: number of apps a user has access to (one).")
            : String(localized: "\(count) apps", comment: "Google Play: number of apps a user has access to.")
    }

    /// One permission → its name; several → their group names (at most two, then "+N").
    private static func permissionsSummary(for user: GooglePlayUserModel) -> String {
        var meaningful: [GooglePlayPermission] = []
        var unknownCount = 0
        let account = user.developerAccountPermissions.map { ($0, GooglePlayPermissionLevel.account) }
        let app = user.grants.flatMap { $0.appLevelPermissions.map { ($0, GooglePlayPermissionLevel.app) } }
        for (value, _) in account + app {
            if let permission = permission(forValue: value) {
                if permission != viewAppInformation, !meaningful.contains(permission) { meaningful.append(permission) }
            } else if value != adminPermission {
                unknownCount += 1
            }
        }
        if meaningful.isEmpty {
            let hasView = !user.developerAccountPermissions.isEmpty || user.grants.contains { !$0.appLevelPermissions.isEmpty }
            return hasView || unknownCount > 0
                ? viewAppInformation.accountName
                : String(localized: "No permissions", comment: "Google Play users list: the user has no permission.")
        }
        if meaningful.count == 1, let only = meaningful.first {
            return only.accountName
        }
        let groups = GooglePlayPermissionGroup.allCases.filter { group in meaningful.contains { $0.group == group } }
        if groups.count <= 2 {
            return groups.map(\.title).formatted(.list(type: .and, width: .narrow))
        }
        let shown = groups.prefix(2).map(\.title).joined(separator: ", ")
        return "\(shown) +\(groups.count - 2)"
    }

    // MARK: - Private

    private static func permission(
        _ id: String,
        _ group: GooglePlayPermissionGroup,
        _ accountLevel: String?,
        _ appLevel: String?,
        _ name: String,
        appName: String? = nil
    ) -> GooglePlayPermission {
        GooglePlayPermission(
            id: id, group: group, accountLevel: accountLevel, appLevel: appLevel,
            accountName: name, appName: appName ?? name
        )
    }
}

// MARK: - Presets

/// App-side shortcuts that only pre-fill the account-level toggles (plan U5).
/// Google Play has no roles, so nothing about the preset is stored.
enum GooglePlayPermissionPreset: String, CaseIterable, Identifiable, Hashable, Sendable {
    case admin
    case releaseManager
    case support
    case finance
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .admin:          return String(localized: "Admin", comment: "Google Play invite preset.")
        case .releaseManager: return String(localized: "Release manager", comment: "Google Play invite preset.")
        case .support:        return String(localized: "Support", comment: "Google Play invite preset.")
        case .finance:        return String(localized: "Finance", comment: "Google Play invite preset.")
        case .custom:         return String(localized: "Custom", comment: "Google Play invite preset: the toggles as set by hand.")
        }
    }

    /// The account-level values the preset turns on (normalized), `nil` for
    /// Custom (the toggles stay as they are).
    var accountPermissions: [String]? {
        let values: [String]
        switch self {
        case .admin:
            values = [GooglePlayPermissionCatalog.adminPermission]
        case .releaseManager:
            values = ["CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL", "CAN_VIEW_APP_QUALITY_GLOBAL", "CAN_MANAGE_PUBLIC_APKS_GLOBAL",
                      "CAN_MANAGE_TRACK_APKS_GLOBAL", "CAN_MANAGE_TRACK_USERS_GLOBAL"]
        case .support:
            values = ["CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL", "CAN_REPLY_TO_REVIEWS_GLOBAL"]
        case .finance:
            values = ["CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL", "CAN_VIEW_FINANCIAL_DATA_GLOBAL", "CAN_MANAGE_ORDERS_GLOBAL"]
        case .custom:
            return nil
        }
        return values
    }

    /// The preset whose permissions are exactly `values`, Custom otherwise.
    static func matching(_ values: [String]) -> GooglePlayPermissionPreset {
        let set = Set(GooglePlayPermissionCatalog.normalized(values, level: .account))
        return allCases.first { preset in
            preset.accountPermissions.map { Set($0) == set } ?? false
        } ?? .custom
    }
}
