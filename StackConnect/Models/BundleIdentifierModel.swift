import Foundation

struct BundleIdentifierModel: Identifiable, Hashable, Codable {
    let id: String
    let identifier: String
    let name: String
    let platform: String
    let seedId: String?

    var platformDisplayName: String {
        BundleIdPlatformLabel.label(for: platform, style: .expanded)
    }
}
