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
    var appsBundles: [String]?

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
        appsBundles: [String]? = nil
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
    }

    var isExportable: Bool {
        origin == .created
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, providerType, createdAt, rules, origin, role, expirationDate
        case hasPendingAgreements, pendingAgreementsDetectedAt, appsBundles
    }
}
