import Foundation

/// Foundation-pure value model for an App Store version. Migrated into
/// StackHomeCore so the SDK-free `AppleAccountSyncing` protocol can reference it
/// from core. `AppStoreState` already lives in core (AppModel.swift).
public struct AppStoreVersionModel: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let platform: AppPlatform?
    public var appStoreState: AppStoreState?
    public var appVersionState: String?
    public var versionString: String?
    public var copyright: String?
    public var releaseType: String?
    public var createdDate: Date?
    public let appId: String

    public init(
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
