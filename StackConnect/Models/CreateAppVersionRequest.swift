import Foundation

struct CreateAppVersionRequest {
    let appId: String
    let platform: AppPlatform
    let version: String
}
