import AppIntents
import Foundation

struct RejectVersionIntent: AppIntent {

    static var title: LocalizedStringResource = "Reject App Version"

    static var description = IntentDescription(
        "Reject an app version that is pending developer release on App Store Connect.",
        categoryName: "App Management"
    )

    @Parameter(title: "App Version", description: "The app version to reject")
    var appVersion: AppVersionEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Reject \(\.$appVersion)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let keychain = KeychainStorable.shared

        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(appVersion.accountId)") else {
            throw IntentError.credentialsNotFound
        }

        try await requestConfirmation(
            result: .result(
                dialog: "Reject \(appVersion.appName) v\(appVersion.versionString)? This will cancel the release."
            )
        )

        let connection = AppleAccountConnection(credentials: credentials)

        do {
            try await connection.rejectVersion(appId: appVersion.appId)
        } catch {
            throw IntentError.rejectFailed(error.localizedDescription)
        }

        return .result(
            dialog: "\(appVersion.appName) v\(appVersion.versionString) has been rejected."
        )
    }
}
