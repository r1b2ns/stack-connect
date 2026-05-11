import Foundation

struct BuildModel: Codable, Identifiable, Hashable {
    let id: String
    var version: String?
    var processingState: String?
    var uploadedDate: Date?
    var iconUrl: String?
    var platform: String?

    init(
        id: String,
        version: String? = nil,
        processingState: String? = nil,
        uploadedDate: Date? = nil,
        iconUrl: String? = nil,
        platform: String? = nil
    ) {
        self.id = id
        self.version = version
        self.processingState = processingState
        self.uploadedDate = uploadedDate
        self.iconUrl = iconUrl
        self.platform = platform
    }
}
