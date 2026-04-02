import AppIntents
import Foundation

struct PendingReleaseAppQuery: EntityQuery {

    func entities(for identifiers: [AppVersionEntity.ID]) async throws -> [AppVersionEntity] {
        let all = try await suggestedEntities()
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AppVersionEntity] {
        let storage = await SwiftDataStorable.shared!
        let keychain = KeychainStorable.shared

        let allAccounts: [AccountModel] = try await storage.fetchAll(AccountModel.self)
        let appleAccounts = allAccounts.filter { $0.providerType == .apple }

        var entities: [AppVersionEntity] = []

        for account in appleAccounts {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(account.id)") else {
                continue
            }

            let connection = AppleAccountConnection(credentials: credentials)

            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let accountApps = allApps.filter { $0.accountId == account.id }

            for app in accountApps {
                do {
                    let versions = try await connection.fetchAppStoreVersions(appId: app.id, limit: 5)
                    let pending = versions.filter { $0.appStoreState == .pendingDeveloperRelease }

                    for version in pending {
                        let entity = AppVersionEntity(
                            id: version.id,
                            appName: app.name,
                            versionString: version.versionString ?? "?",
                            appId: app.id,
                            accountId: account.id,
                            accountName: account.name
                        )
                        entities.append(entity)
                    }
                } catch {
                    Log.print.warning("[Intent] Failed to fetch versions for app \(app.name): \(error.localizedDescription)")
                }
            }
        }

        return entities
    }
}
