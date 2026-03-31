import Foundation

// MARK: - Remote Config Template

/// The full Remote Config template returned by `GET /v1/projects/{projectId}/remoteConfig`.
public struct RemoteConfigTemplate: Codable {
    /// Remote Config conditions.
    public var conditions: [RemoteConfigCondition]?

    /// All parameters keyed by name.
    public var parameters: [String: RemoteConfigParameter]?

    /// Parameter groups keyed by group name.
    public var parameterGroups: [String: RemoteConfigParameterGroup]?

    /// Version metadata (read-only, returned by GET).
    public let version: RemoteConfigVersion?

    public init(
        conditions: [RemoteConfigCondition]? = nil,
        parameters: [String: RemoteConfigParameter]? = nil,
        parameterGroups: [String: RemoteConfigParameterGroup]? = nil,
        version: RemoteConfigVersion? = nil
    ) {
        self.conditions = conditions
        self.parameters = parameters
        self.parameterGroups = parameterGroups
        self.version = version
    }
}

// MARK: - Condition

public struct RemoteConfigCondition: Codable, Identifiable, Hashable {
    public var name: String
    public var expression: String?
    public var tagColor: TagColor?
    public var description: String?

    public var id: String { name }

    public init(name: String, expression: String? = nil, tagColor: TagColor? = nil, description: String? = nil) {
        self.name = name
        self.expression = expression
        self.tagColor = tagColor
        self.description = description
    }

    public enum TagColor: String, Codable, CaseIterable, Hashable {
        case unspecified = "CONDITION_DISPLAY_COLOR_UNSPECIFIED"
        case blue = "BLUE"
        case brown = "BROWN"
        case cyan = "CYAN"
        case deepOrange = "DEEP_ORANGE"
        case green = "GREEN"
        case indigo = "INDIGO"
        case lime = "LIME"
        case orange = "ORANGE"
        case pink = "PINK"
        case purple = "PURPLE"
        case teal = "TEAL"
    }
}

// MARK: - Parameter

public struct RemoteConfigParameter: Codable, Hashable {
    public var defaultValue: RemoteConfigParameterValue?
    public var conditionalValues: [String: RemoteConfigParameterValue]?
    public var description: String?
    public var valueType: ValueType?

    public init(
        defaultValue: RemoteConfigParameterValue? = nil,
        conditionalValues: [String: RemoteConfigParameterValue]? = nil,
        description: String? = nil,
        valueType: ValueType? = nil
    ) {
        self.defaultValue = defaultValue
        self.conditionalValues = conditionalValues
        self.description = description
        self.valueType = valueType
    }

    public enum ValueType: String, Codable, CaseIterable, Hashable {
        case string = "STRING"
        case number = "NUMBER"
        case boolean = "BOOLEAN"
        case json = "JSON"
    }
}

// MARK: - Parameter Value

public struct RemoteConfigParameterValue: Codable, Hashable {
    public var value: String?
    public var useInAppDefault: Bool?

    public init(value: String? = nil, useInAppDefault: Bool? = nil) {
        self.value = value
        self.useInAppDefault = useInAppDefault
    }
}

// MARK: - Parameter Group

public struct RemoteConfigParameterGroup: Codable, Hashable {
    public var description: String?
    public var parameters: [String: RemoteConfigParameter]?

    public init(description: String? = nil, parameters: [String: RemoteConfigParameter]? = nil) {
        self.description = description
        self.parameters = parameters
    }
}

// MARK: - Version

public struct RemoteConfigVersion: Codable, Hashable {
    public let versionNumber: String?
    public let updateOrigin: String?
    public let updateType: String?
    public let updateUser: UpdateUser?
    public let updateTime: String?
    public let description: String?

    public struct UpdateUser: Codable, Hashable {
        public let email: String?
        public let name: String?
        public let imageUrl: String?
    }
}

// MARK: - List Versions Response

public struct ListRemoteConfigVersionsResponse: Decodable {
    public let versions: [RemoteConfigVersion]?
    public let nextPageToken: String?
}

// MARK: - Rollback Request

public struct RollbackRemoteConfigRequest: Encodable {
    public let versionNumber: String

    public init(versionNumber: String) {
        self.versionNumber = versionNumber
    }

    enum CodingKeys: String, CodingKey {
        case versionNumber = "version_number"
    }
}
