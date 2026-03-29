import Foundation
import AppStoreConnect_Swift_SDK

struct CreateAppVersionRequest {
    let appId: String
    let platform: AppPlatform
    let version: String

    func toSDKRequest() -> AppStoreVersionCreateRequest {
        let sdkPlatform: Platform
        switch platform {
        case .ios:      sdkPlatform = .ios
        case .macOs:    sdkPlatform = .macOs
        case .tvOs:     sdkPlatform = .tvOs
        case .visionOs: sdkPlatform = .visionOs
        }

        return AppStoreVersionCreateRequest(
            data: .init(
                type: .appStoreVersions,
                attributes: .init(
                    platform: sdkPlatform,
                    versionString: version,
                    releaseType: .manual
                ),
                relationships: .init(
                    app: .init(
                        data: .init(
                            type: .apps,
                            id: appId
                        )
                    )
                )
            )
        )
    }
}
