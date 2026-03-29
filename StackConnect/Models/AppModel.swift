import Foundation

struct AppModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let bundleId: String
    let platform: String?
    let accountId: String

    init(
        id: String,
        name: String,
        bundleId: String,
        platform: String? = nil,
        accountId: String
    ) {
        self.id = id
        self.name = name
        self.bundleId = bundleId
        self.platform = platform
        self.accountId = accountId
    }
}
