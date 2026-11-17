import Foundation

/// An app offered by the export per-app scope picker (`AppsPermissionPickerSheet`),
/// independent of each provider's own app model.
///
/// `bundleId` is the scope key written to `appsBundles`: the bundle id for App
/// Store Connect and the package name for Google Play — the same value the
/// importing side checks with `AccountModel.allowsApp(bundleId:)`.
struct ExportableApp: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleId: String
    let iconURL: URL?
}

extension ExportableApp {

    init(app: AppModel) {
        self.init(
            id: app.id,
            name: app.name,
            bundleId: app.bundleId,
            iconURL: app.iconUrl.flatMap { URL(string: $0) }
        )
    }

    init(playApp: GooglePlayAppItem) {
        self.init(
            id: playApp.id,
            name: playApp.displayName,
            bundleId: playApp.packageName,
            iconURL: playApp.iconURL
        )
    }
}

// MARK: - Loader

/// Loads the apps an account can scope its export to, sorted by name.
///
/// App Store Connect apps live in `AppModel`; Google Play apps live in the
/// account's cached `[GooglePlayAppItem]` list (plan D6). Firebase accounts
/// can't be exported, so they have none. Shared by both export entry points.
enum ExportableAppsLoader {

    static func apps(for account: AccountModel, storage: PersistentStorable) async -> [ExportableApp] {
        switch account.providerType {
        case .apple:
            let all: [AppModel] = (try? await storage.fetchAll(AppModel.self)) ?? []
            return all
                .filter { $0.accountId == account.id }
                .sorted { $0.name < $1.name }
                .map(ExportableApp.init(app:))

        case .googlePlay:
            let cacheKey = GooglePlayAppItem.cacheKey(accountId: account.id)
            let cached = (try? await storage.fetch([GooglePlayAppItem].self, id: cacheKey)) ?? []
            return cached
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                .map(ExportableApp.init(playApp:))

        case .firebase:
            return []
        }
    }
}
