import Foundation

public struct AppInfo: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let bundleId: String
    public let platform: String?

    public init(
        id: String,
        name: String,
        bundleId: String,
        platform: String? = nil
    ) {
        self.id = id
        self.name = name
        self.bundleId = bundleId
        self.platform = platform
    }
}
