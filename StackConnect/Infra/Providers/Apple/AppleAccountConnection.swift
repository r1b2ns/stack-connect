import Foundation
import AppStoreConnect_Swift_SDK
import StackProtocols

final class AppleAccountConnection: AccountConnectionProtocol, @unchecked Sendable {

    private let credentials: AppleCredentials
    private var provider: APIProvider?

    init(credentials: AppleCredentials) {
        self.credentials = credentials
    }

    // MARK: - AccountConnectionProtocol

    func validateCredentials() async throws {
        let provider = try createProvider()
        self.provider = provider

        let request = APIEndpoint
            .v1
            .apps
            .get(parameters: .init(limit: 1))

        _ = try await provider.request(request)
        Log.print.info("[Apple] Credentials validated successfully")
    }

    func fetchApps() async throws -> [StackProtocols.AppInfo] {
        guard let provider else {
            try await validateCredentials()
            return try await fetchApps()
        }

        let request = APIEndpoint
            .v1
            .apps
            .get(parameters: .init(sort: [.minusname], limit: 200))

        let response = try await provider.request(request)

        let apps = response.data.map { app in
            StackProtocols.AppInfo(
                id: app.id,
                name: app.attributes?.name ?? "",
                bundleId: app.attributes?.bundleID ?? "",
                platform: nil
            )
        }

        Log.print.info("[Apple] Fetched \(apps.count) apps")
        return apps
    }

    func disconnect() {
        provider = nil
        Log.print.info("[Apple] Disconnected")
    }

    // MARK: - Private

    private func createProvider() throws -> APIProvider {
        let config = try APIConfiguration(
            issuerID: credentials.issuerID,
            privateKeyID: credentials.privateKeyID,
            privateKey: credentials.privateKey
        )
        return APIProvider(configuration: config)
    }
}
