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

// MARK: - Account Model

struct AccountModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let providerType: ProviderType
    let createdAt: Date
    var rules: AccountRules
    var origin: AccountOrigin

    init(
        id: String = UUID().uuidString,
        name: String,
        providerType: ProviderType,
        createdAt: Date = .now,
        rules: AccountRules = .allPermissions,
        origin: AccountOrigin = .created
    ) {
        self.id = id
        self.name = name
        self.providerType = providerType
        self.createdAt = createdAt
        self.rules = rules
        self.origin = origin
    }

    var isExportable: Bool {
        origin == .created
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, providerType, createdAt, rules, origin
    }
}
