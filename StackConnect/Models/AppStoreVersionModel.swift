import Foundation

struct AppStoreVersionModel: Codable, Identifiable, Hashable {
    let id: String
    let platform: AppPlatform?
    var appStoreState: AppStoreState?
    var appVersionState: String?
    var versionString: String?
    var copyright: String?
    var releaseType: String?
    var createdDate: Date?
    let appId: String

    init(
        id: String,
        platform: AppPlatform? = nil,
        appStoreState: AppStoreState? = nil,
        appVersionState: String? = nil,
        versionString: String? = nil,
        copyright: String? = nil,
        releaseType: String? = nil,
        createdDate: Date? = nil,
        appId: String
    ) {
        self.id = id
        self.platform = platform
        self.appStoreState = appStoreState
        self.appVersionState = appVersionState
        self.versionString = versionString
        self.copyright = copyright
        self.releaseType = releaseType
        self.createdDate = createdDate
        self.appId = appId
    }
}
