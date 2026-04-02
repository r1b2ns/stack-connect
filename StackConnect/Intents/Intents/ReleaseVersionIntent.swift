import AppIntents
import Foundation

struct ReleaseVersionIntent: AppIntent {

    static var title: LocalizedStringResource = "Release App Version"

    static var description = IntentDescription(
        "Release an app version that is pending developer release on App Store Connect.",
        categoryName: "App Management"
    )

    @Parameter(title: "App Version", description: "The app version to release")
    var appVersion: AppVersionEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Release \(\.$appVersion)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let keychain = KeychainStorable.shared

        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(appVersion.accountId)") else {
            throw IntentError.credentialsNotFound
        }

        try await requestConfirmation(
            result: .result(
                dialog: "Release \(appVersion.appName) v\(appVersion.versionString) to the App Store?"
            )
        )

        let connection = AppleAccountConnection(credentials: credentials)

        do {
            try await connection.releaseVersion(versionId: appVersion.id)
        } catch {
            throw IntentError.releaseFailed(error.localizedDescription)
        }

        return .result(
            dialog: "\(appVersion.appName) v\(appVersion.versionString) has been released to the App Store."
        )
    }
}

// MARK: - Errors

enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case credentialsNotFound
    case releaseFailed(String)
    case rejectFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .credentialsNotFound:
            return "Account credentials not found. Please reconnect your account in StackConnect."
        case .releaseFailed(let reason):
            return "Failed to release version: \(reason)"
        case .rejectFailed(let reason):
            return "Failed to reject version: \(reason)"
        }
    }
}
