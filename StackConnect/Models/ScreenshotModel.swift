import Foundation

struct ScreenshotSetModel: Codable, Identifiable, Hashable {
    let id: String
    let displayType: String?
    var screenshots: [ScreenshotModel]

    init(id: String, displayType: String? = nil, screenshots: [ScreenshotModel] = []) {
        self.id = id
        self.displayType = displayType
        self.screenshots = screenshots
    }

    var deviceCategory: ScreenshotDeviceType? {
        guard let displayType else { return nil }
        if displayType.hasPrefix("APP_IPHONE") { return .iPhone }
        if displayType.hasPrefix("APP_IPAD") { return .iPad }
        if displayType.hasPrefix("APP_WATCH") { return .appleWatch }
        if displayType.hasPrefix("IMESSAGE_APP") { return .iMessage }
        if displayType.hasPrefix("APP_APPLE_TV") { return .appleTV }
        if displayType.hasPrefix("APP_DESKTOP") { return .mac }
        if displayType.hasPrefix("APP_APPLE_VISION") { return .visionPro }
        return nil
    }

    var displayName: String {
        guard let displayType else { return "Unknown" }
        return displayType
            .replacingOccurrences(of: "APP_", with: "")
            .replacingOccurrences(of: "IMESSAGE_APP_", with: "iMessage ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

struct ScreenshotModel: Codable, Identifiable, Hashable {
    let id: String
    var imageUrl: String?
    var fileName: String?
    var fileSize: Int?
    var width: Int?
    var height: Int?

    init(
        id: String,
        imageUrl: String? = nil,
        fileName: String? = nil,
        fileSize: Int? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.id = id
        self.imageUrl = imageUrl
        self.fileName = fileName
        self.fileSize = fileSize
        self.width = width
        self.height = height
    }
}
