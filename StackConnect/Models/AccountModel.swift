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
}

// MARK: - Rules

struct AccountRules: Codable, Hashable {
    var apps: [AccountPermission]
    var version: [AccountPermission]
    var users: [AccountPermission]
    var review: [AccountPermission]
    var testFlight: [AccountPermission]
    var analytics: [AccountPermission]

    static var allPermissions: AccountRules {
        let all = AccountPermission.allCases
        return AccountRules(
            apps: all,
            version: all,
            users: all,
            review: all,
            testFlight: all,
            analytics: all
        )
    }

    subscript(resource: AccountRuleResource) -> [AccountPermission] {
        get {
            switch resource {
            case .apps:      return apps
            case .version:   return version
            case .users:     return users
            case .review:    return review
            case .testFlight: return testFlight
            case .analytics: return analytics
            }
        }
        set {
            switch resource {
            case .apps:      apps = newValue
            case .version:   version = newValue
            case .users:     users = newValue
            case .review:    review = newValue
            case .testFlight: testFlight = newValue
            case .analytics: analytics = newValue
            }
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

    init(
        id: String = UUID().uuidString,
        name: String,
        providerType: ProviderType,
        createdAt: Date = .now,
        rules: AccountRules = .allPermissions
    ) {
        self.id = id
        self.name = name
        self.providerType = providerType
        self.createdAt = createdAt
        self.rules = rules
    }

    /// Ensures all rule resources have values. Fills missing ones with all permissions.
    mutating func fillMissingRules() {
        let all = AccountPermission.allCases
        for resource in AccountRuleResource.allCases {
            if self.rules[resource].isEmpty {
                self.rules[resource] = all
            }
        }
    }

    // Custom decoder to handle existing accounts without rules
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        providerType = try container.decode(ProviderType.self, forKey: .providerType)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        rules = try container.decodeIfPresent(AccountRules.self, forKey: .rules) ?? .allPermissions
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, providerType, createdAt, rules
    }
}
