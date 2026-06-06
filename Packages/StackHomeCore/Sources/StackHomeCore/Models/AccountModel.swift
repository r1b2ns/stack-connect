import Foundation

// MARK: - Permission

public enum AccountPermission: String, Codable, CaseIterable, Hashable, Sendable {
    case view
    case edit
    case delete
    case add
}

// MARK: - Rule Resource

public enum AccountRuleResource: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case apps
    case version
    case users
    case review
    case testFlight
    case analytics
    case provisioning

    /// Stable identity (the raw value), e.g. for SwiftUI `ForEach`/`sheet(item:)`.
    public var id: String { rawValue }
}

// MARK: - Rules

public struct AccountRules: Codable, Hashable, Sendable {
    public var apps: [AccountPermission]
    public var version: [AccountPermission]
    public var users: [AccountPermission]
    public var review: [AccountPermission]
    public var testFlight: [AccountPermission]
    public var analytics: [AccountPermission]
    public var provisioning: [AccountPermission]

    public init(
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
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps = try container.decodeIfPresent([AccountPermission].self, forKey: .apps) ?? []
        version = try container.decodeIfPresent([AccountPermission].self, forKey: .version) ?? []
        users = try container.decodeIfPresent([AccountPermission].self, forKey: .users) ?? []
        review = try container.decodeIfPresent([AccountPermission].self, forKey: .review) ?? []
        testFlight = try container.decodeIfPresent([AccountPermission].self, forKey: .testFlight) ?? []
        analytics = try container.decodeIfPresent([AccountPermission].self, forKey: .analytics) ?? []
        provisioning = try container.decodeIfPresent([AccountPermission].self, forKey: .provisioning) ?? []
    }

    public static var allPermissions: AccountRules {
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

    public subscript(resource: AccountRuleResource) -> [AccountPermission] {
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

public enum AccountOrigin: String, Codable, Hashable, Sendable {
    case created
    case imported
}

// MARK: - Account Model

public struct AccountModel: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let providerType: ProviderType
    public let createdAt: Date
    public var rules: AccountRules
    public var origin: AccountOrigin
    /// Optional expiration set on the export. When reached, the account must be removed.
    public var expirationDate: Date?

    public init(
        id: String = UUID().uuidString,
        name: String,
        providerType: ProviderType,
        createdAt: Date = .now,
        rules: AccountRules = .allPermissions,
        origin: AccountOrigin = .created,
        expirationDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.providerType = providerType
        self.createdAt = createdAt
        self.rules = rules
        self.origin = origin
        self.expirationDate = expirationDate
    }

    public var isExportable: Bool {
        origin == .created
    }

    public var isExpired: Bool {
        guard let expirationDate else { return false }
        return Date() >= expirationDate
    }

    /// True when the account has not expired yet but will within the next 24 hours.
    public var isExpiringSoon: Bool {
        guard let expirationDate else { return false }
        let now = Date()
        return expirationDate > now && expirationDate <= now.addingTimeInterval(24 * 60 * 60)
    }

    // MARK: - Permission Checks (respects hierarchy: add→edit→view, delete→edit→view)

    public func canView(_ resource: AccountRuleResource) -> Bool {
        let perms = rules[resource]
        return perms.contains(.view) || perms.contains(.edit) || perms.contains(.delete) || perms.contains(.add)
    }

    public func canEdit(_ resource: AccountRuleResource) -> Bool {
        let perms = rules[resource]
        return perms.contains(.edit) || perms.contains(.delete) || perms.contains(.add)
    }

    public func canDelete(_ resource: AccountRuleResource) -> Bool {
        rules[resource].contains(.delete)
    }

    public func canAdd(_ resource: AccountRuleResource) -> Bool {
        rules[resource].contains(.add)
    }

    /// Ensures all rule resources have values for created accounts.
    /// Imported accounts keep their original permissions (even if empty).
    public mutating func fillMissingRules() {
        guard origin == .created else { return }
        let all = AccountPermission.allCases
        for resource in AccountRuleResource.allCases {
            if self.rules[resource].isEmpty {
                self.rules[resource] = all
            }
        }
    }

    // Custom decoder to handle existing accounts without rules/origin
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        providerType = try container.decode(ProviderType.self, forKey: .providerType)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        rules = try container.decodeIfPresent(AccountRules.self, forKey: .rules) ?? .allPermissions
        origin = try container.decodeIfPresent(AccountOrigin.self, forKey: .origin) ?? .created
        expirationDate = try container.decodeIfPresent(Date.self, forKey: .expirationDate)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, providerType, createdAt, rules, origin, expirationDate
    }
}
