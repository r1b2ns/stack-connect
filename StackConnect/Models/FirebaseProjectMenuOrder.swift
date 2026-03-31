import Foundation

struct FirebaseProjectMenuOrder: Codable {
    let projectId: String
    var orderedItems: [String]

    static let defaultItems: [String] = [
        "apps",
        "remoteConfig",
        "messaging",
        "analyticsDashboard"
    ]
}
