import AppIntents
import Foundation

struct AppVersionEntity: AppEntity {

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: "App Version",
            numericFormat: "\(placeholder: .int) app versions"
        )
    }

    static var defaultQuery = PendingReleaseAppQuery()

    var id: String
    var appName: String
    var versionString: String
    var appId: String
    var accountId: String
    var accountName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(appName)",
            subtitle: "v\(versionString) — \(accountName)"
        )
    }
}
