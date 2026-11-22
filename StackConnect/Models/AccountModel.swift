import Foundation

// MARK: - Permission

enum AccountPermission: String, Codable, CaseIterable, Hashable {
    case view
    case edit
    case delete
    case add
}

// MARK: - Rule Resource

enum AccountRuleResource: String, Codable, CaseIterable, Hashable {
    case apps
    case version
    case users
    case review
    case testFlight
    case analytics
    case provisioning

    /// Rule resources that gate something for accounts of `provider`, in display
    /// order. Drives the permission pickers (export) and the permissions summary
    /// (Account Settings), so only meaningful resources are offered.
    ///
    /// Google Play gates its app list and the read-only app sections (`apps`:
    /// manual add / remove, store listings, app details), its releases
    /// (`version`: release status, tracks and release detail; later edit /
    /// add for rollout changes and new releases, plan R5) and its ratings &
    /// reviews (`review`: view, reply) and its users (`users`: view the Users
    /// tab, invite, change permissions and app access, remove; plan U6).
    /// Older Play exports carry no `version` / `users` permission, so their
    /// releases and users stay hidden (fail closed). Firebase accounts have no
    /// rules.
    static func resources(for provider: ProviderType) -> [AccountRuleResource] {
        switch provider {
        case .apple:      return [.apps, .version, .review, .testFlight, .analytics, .users, .provisioning]
        case .googlePlay: return [.apps, .version, .review, .users]
        case .firebase:   return []
        }
    }
}

// MARK: - Rules

struct AccountRules: Codable, Hashable {
    var apps: [AccountPermission]
    var version: [AccountPermission]
    var users: [AccountPermission]
    var review: [AccountPermission]
    var testFlight: [AccountPermission]
    var analytics: [AccountPermission]
    var provisioning: [AccountPermission]

    init(
        apps: [AccountPermission] = [],
        version: [AccountPermission] = [],
        users: [AccountPermission] = [],
        review: [AccountPermission] = [],
        testFlight: [AccountPermission] = [],
        analytics: [AccountPermission] = [],
        provisioning: [AccountPermission] = []
    ) {
        self.apps = apps
        self.version = version
        self.users = users
        self.review = review
        self.testFlight = testFlight
        self.analytics = analytics
        self.provisioning = provisioning
    }

    // Tolerates rules persisted before a resource existed (e.g. `provisioning`)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps = try container.decodeIfPresent([AccountPermission].self, forKey: .apps) ?? []
        version = try container.decodeIfPresent([AccountPermission].self, forKey: .version) ?? []
        users = try container.decodeIfPresent([AccountPermission].self, forKey: .users) ?? []
        review = try container.decodeIfPresent([AccountPermission].self, forKey: .review) ?? []
        testFlight = try container.decodeIfPresent([AccountPermission].self, forKey: .testFlight) ?? []
        analytics = try container.decodeIfPresent([AccountPermission].self, forKey: .analytics) ?? []
        provisioning = try container.decodeIfPresent([AccountPermission].self, forKey: .provisioning) ?? []
    }

    static var allPermissions: AccountRules {
        let all = AccountPermission.allCases
        return AccountRules(
            apps: all,
            version: all,
            users: all,
            review: all,
            testFlight: all,
            analytics: all,
            provisioning: all
        )
    }

    subscript(resource: AccountRuleResource) -> [AccountPermission] {
        get {
            switch resource {
            case .apps:         return apps
            case .version:      return version
            case .users:        return users
            case .review:       return review
            case .testFlight:   return testFlight
            case .analytics:    return analytics
            case .provisioning: return provisioning
            }
        }
        set {
            switch resource {
            case .apps:         apps = newValue
            case .version:      version = newValue
            case .users:        users = newValue
            case .review:       review = newValue
            case .testFlight:   testFlight = newValue
            case .analytics:    analytics = newValue
            case .provisioning: provisioning = newValue
            }
        }
    }
}

// MARK: - Account Origin

enum AccountOrigin: String, Codable, Hashable {
    case created
    case imported
}

// MARK: - Auth Method

/// How the account authenticates. Not secret (the credentials themselves stay
/// in the Keychain): it lets the lists and the export know an account signed
/// in with Google without reading the Keychain.
enum AccountAuthMethod: String, Codable, Hashable {
    /// A key file: the App Store Connect `.p8` key or a Google service account JSON.
    case keyFile
    /// "Sign in with Google" (Firebase and Google Play, plan G5).
    case googleSignIn
    /// "Sign in with Apple ID" (App Store Connect, plan `apple-id-sign-in.md`):
    /// the Apple ID web session, shared by every team account of that Apple ID.
    case appleIdSignIn
}

// MARK: - Connection Kind

/// How an account is connected, independent of its provider. The accounts
/// lists show one section per kind, in `allCases` order (key-based first).
enum AccountConnectionKind: String, CaseIterable, Hashable {
    /// A key file: the App Store Connect API key (`.p8` "AuthKey") or a Google
    /// service account JSON key.
    case keyFile
    /// A personal sign-in: "Sign in with Apple ID" (password + two-factor web
    /// session) or "Sign in with Google" (OAuth).
    case signIn
}

/// A connection kind of a given provider: what an accounts list section
/// header shows ("API Key" / "Apple ID", "Service Account Key" / "Google Account").
struct AccountConnection: Hashable {
    let provider: ProviderType
    let kind: AccountConnectionKind

    /// Section header title.
    var title: String {
        switch (provider, kind) {
        case (.apple, .keyFile): return String(localized: "API Key")
        case (.apple, .signIn):  return String(localized: "Apple ID")
        case (.firebase, .keyFile), (.googlePlay, .keyFile):
            return String(localized: "Service Account Key")
        case (.firebase, .signIn), (.googlePlay, .signIn):
            return String(localized: "Google Account")
        }
    }

    var iconName: String {
        switch kind {
        case .keyFile: return "key.fill"
        case .signIn:  return "person.crop.circle"
        }
    }
}

// MARK: - Account Role

/// App Store Connect role associated with the API key backing this account.
/// `.unspecified` is the default/none case for accounts created before roles
/// existed or when the user chooses not to set one.
enum AccountRole: String, Codable, CaseIterable, Hashable {
    case unspecified
    case admin
    case appManager
    case developer
    case marketing
    case sales
    case finance
    case customerSupport

    var displayName: String {
        switch self {
        case .unspecified:     return String(localized: "Unspecified")
        case .admin:           return String(localized: "Admin")
        case .appManager:      return String(localized: "App Manager")
        case .developer:       return String(localized: "Developer")
        case .marketing:       return String(localized: "Marketing")
        case .sales:           return String(localized: "Sales")
        case .finance:         return String(localized: "Finance")
        case .customerSupport: return String(localized: "Customer Support")
        }
    }
}

// MARK: - Account Model

struct AccountModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let providerType: ProviderType
    let createdAt: Date
    var rules: AccountRules
    var origin: AccountOrigin
    /// Optional App Store Connect role/label for this account. Lets the same team
    /// (same issuerID) be registered multiple times with different API key roles.
    var role: AccountRole
    /// Optional expiration set on the export. When reached, the account must be removed.
    var expirationDate: Date?
    /// True when ASC calls for this account started failing with a 403 "pending
    /// agreements" error (Paid Apps / Program License Agreement). Detected
    /// indirectly — Apple exposes no agreements API. Self-heals on a clean sync.
    var hasPendingAgreements: Bool
    /// Timestamp of the first time pending agreements were detected. Kept stable
    /// across re-detections so the banner can show a consistent "since" date.
    var pendingAgreementsDetectedAt: Date?
    /// Per-app export scope. nil/empty ⇒ no restriction (all apps visible —
    /// legacy/created accounts). Non-empty ⇒ only apps whose bundleId ∈
    /// appsBundles are visible for this imported account. See `allowsApp`.
    /// Google sign-in accounts (`authMethod == .googleSignIn`) use the same
    /// scope for what was picked in Add Account: Play package names, or the
    /// Firebase project ID of a Firebase account.
    var appsBundles: [String]?
    /// Google Play only: the numeric Play Console developer account ID the Users
    /// tab needs (`developers/{id}/users`, plan U3). Optional — set in Add
    /// Account or later in Account Settings / the Users tab. Not secret (it is
    /// in every Play Console URL), so it lives here, not in the Keychain, and
    /// travels in `.scexport` files.
    var googlePlayDeveloperId: String?
    /// `.googleSignIn` for accounts added with "Sign in with Google"; every
    /// account stored before that existed decodes as `.keyFile`.
    var authMethod: AccountAuthMethod

    init(
        id: String = UUID().uuidString,
        name: String,
        providerType: ProviderType,
        createdAt: Date = .now,
        rules: AccountRules = .allPermissions,
        origin: AccountOrigin = .created,
        role: AccountRole = .unspecified,
        expirationDate: Date? = nil,
        hasPendingAgreements: Bool = false,
        pendingAgreementsDetectedAt: Date? = nil,
        appsBundles: [String]? = nil,
        googlePlayDeveloperId: String? = nil,
        authMethod: AccountAuthMethod = .keyFile
    ) {
        self.id = id
        self.name = name
        self.providerType = providerType
        self.createdAt = createdAt
        self.rules = rules
        self.origin = origin
        self.role = role
        self.expirationDate = expirationDate
        self.hasPendingAgreements = hasPendingAgreements
        self.pendingAgreementsDetectedAt = pendingAgreementsDetectedAt
        self.appsBundles = appsBundles
        self.googlePlayDeveloperId = googlePlayDeveloperId
        self.authMethod = authMethod
    }

    /// Only accounts created on this device, of a provider that supports export,
    /// can be exported (an imported account can't be re-shared). Accounts
    /// signed in with Google are never exported (plan G7): their refresh token
    /// must not leave the device, and the receiving user signs in with their
    /// own Google account instead. Accounts signed in with an Apple ID are
    /// never exported either (Apple ID plan D7): the session is a personal
    /// login (see `exportUnavailableReason`).
    var isExportable: Bool {
        origin == .created && providerType.supportsExport
            && authMethod != .googleSignIn && authMethod != .appleIdSignIn
    }

    /// Why the export entry points are shown disabled, or `nil` when the
    /// account has none to explain (exportable, or simply not exportable by
    /// provider / origin, which hides them as before).
    var exportUnavailableReason: String? {
        guard authMethod == .appleIdSignIn else { return nil }
        return String(localized: "Accounts added with Sign in with Apple ID can't be exported: the session is your personal Apple ID login. Share an App Store Connect API key instead.")
    }

    // MARK: - Apple ID session limits (plan `apple-id-sign-in.md` G3)

    /// An App Store Connect account added with "Sign in with Apple ID".
    var isAppleIdSession: Bool {
        providerType == .apple && authMethod == .appleIdSignIn
    }

    /// Analytics Reports (and their detail and files screens) need the App
    /// Store Connect API: the Apple ID web session has no route to them.
    var supportsAnalyticsReports: Bool {
        !isAppleIdSession
    }

    /// Renaming or deleting a bundle ID has no Apple ID session form.
    var supportsBundleIdRenameAndDelete: Bool {
        !isAppleIdSession
    }

    /// How this account is connected (key file vs sign-in), used to section the
    /// accounts lists. Read from `authMethod`, so no Keychain access is needed.
    var connectionKind: AccountConnectionKind {
        switch authMethod {
        case .keyFile:                       return .keyFile
        case .googleSignIn, .appleIdSignIn:  return .signIn
        }
    }

    /// `connectionKind` of this account's provider (section header title / icon).
    var connection: AccountConnection {
        AccountConnection(provider: providerType, kind: connectionKind)
    }

    /// Rule resources that apply to this account's provider.
    var ruleResources: [AccountRuleResource] {
        AccountRuleResource.resources(for: providerType)
    }

    /// Role to show next to the account name, or `nil` when there is none to show
    /// (unspecified, or a provider without roles such as Google Play).
    var displayedRole: AccountRole? {
        guard providerType.supportsAccountRole, role != .unspecified else { return nil }
        return role
    }

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return Date() >= expirationDate
    }

    /// True when the account has not expired yet but will within the next 24 hours.
    var isExpiringSoon: Bool {
        guard let expirationDate else { return false }
        let now = Date()
        return expirationDate > now && expirationDate <= now.addingTimeInterval(24 * 60 * 60)
    }

    /// Per-app export scope check. nil/empty ⇒ no restriction (all apps visible).
    /// Non-empty ⇒ only apps whose bundleId ∈ appsBundles are visible for this
    /// imported account. Single source of truth for backward-compat semantics:
    /// absent / null / [] all mean "every app is available".
    func allowsApp(bundleId: String) -> Bool {
        guard let appsBundles, !appsBundles.isEmpty else { return true }
        return appsBundles.contains(bundleId)
    }

    // MARK: - Permission Checks (respects hierarchy: add→edit→view, delete→edit→view)

    func canView(_ resource: AccountRuleResource) -> Bool {
        let perms = rules[resource]
        return perms.contains(.view) || perms.contains(.edit) || perms.contains(.delete) || perms.contains(.add)
    }

    func canEdit(_ resource: AccountRuleResource) -> Bool {
        let perms = rules[resource]
        return perms.contains(.edit) || perms.contains(.delete) || perms.contains(.add)
    }

    func canDelete(_ resource: AccountRuleResource) -> Bool {
        rules[resource].contains(.delete)
    }

    func canAdd(_ resource: AccountRuleResource) -> Bool {
        rules[resource].contains(.add)
    }

    /// A copy with a new name and/or role that keeps every other field —
    /// including the per-app scope (`appsBundles`), which must survive a rename.
    func updating(name: String? = nil, role: AccountRole? = nil) -> AccountModel {
        updating(name: name, role: role, googlePlayDeveloperId: .some(googlePlayDeveloperId))
    }

    /// Same as `updating(name:role:)`, also replacing the Google Play developer
    /// ID (`.some(nil)` clears it).
    func updating(name: String? = nil, role: AccountRole? = nil, googlePlayDeveloperId: String??) -> AccountModel {
        AccountModel(
            id: id,
            name: name ?? self.name,
            providerType: providerType,
            createdAt: createdAt,
            rules: rules,
            origin: origin,
            role: role ?? self.role,
            expirationDate: expirationDate,
            hasPendingAgreements: hasPendingAgreements,
            pendingAgreementsDetectedAt: pendingAgreementsDetectedAt,
            appsBundles: appsBundles,
            googlePlayDeveloperId: googlePlayDeveloperId ?? self.googlePlayDeveloperId,
            authMethod: authMethod
        )
    }

    /// Ensures all rule resources have values for created accounts.
    /// Imported accounts keep their original permissions (even if empty).
    mutating func fillMissingRules() {
        guard origin == .created else { return }
        let all = AccountPermission.allCases
        for resource in AccountRuleResource.allCases {
            if self.rules[resource].isEmpty {
                self.rules[resource] = all
            }
        }
    }

    // Custom decoder to handle existing accounts without rules/origin
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        providerType = try container.decode(ProviderType.self, forKey: .providerType)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        rules = try container.decodeIfPresent(AccountRules.self, forKey: .rules) ?? .allPermissions
        origin = try container.decodeIfPresent(AccountOrigin.self, forKey: .origin) ?? .created
        role = try container.decodeIfPresent(AccountRole.self, forKey: .role) ?? .unspecified
        expirationDate = try container.decodeIfPresent(Date.self, forKey: .expirationDate)
        hasPendingAgreements = try container.decodeIfPresent(Bool.self, forKey: .hasPendingAgreements) ?? false
        pendingAgreementsDetectedAt = try container.decodeIfPresent(Date.self, forKey: .pendingAgreementsDetectedAt)
        // decodeIfPresent ⇒ absent/null decodes to nil ⇒ no restriction (free backward compat).
        appsBundles = try container.decodeIfPresent([String].self, forKey: .appsBundles)
        googlePlayDeveloperId = try container.decodeIfPresent(String.self, forKey: .googlePlayDeveloperId)
        authMethod = try container.decodeIfPresent(AccountAuthMethod.self, forKey: .authMethod) ?? .keyFile
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, providerType, createdAt, rules, origin, role, expirationDate
        case hasPendingAgreements, pendingAgreementsDetectedAt, appsBundles, googlePlayDeveloperId
        case authMethod
    }
}
