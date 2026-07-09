import Foundation

// MARK: - Protocol

@MainActor
protocol AnalyticsReportsViewModelProtocol: ObservableObject {
    var appId: String { get }
    var appName: String { get }
    var account: AccountModel { get }

    /// Catalog sections with favorited AND hidden reports removed. Any category
    /// whose reports all moved out is dropped entirely.
    var sections: [(category: AnalyticsCategory, reports: [AnalyticsCatalogReport])] { get }

    /// Favorited reports, in catalog order (not Set iteration order).
    var favoriteReports: [AnalyticsCatalogReport] { get }

    /// Hidden reports, in catalog order.
    var hiddenReports: [AnalyticsCatalogReport] { get }

    /// Whether the collapsible Hidden section is currently expanded.
    var isHiddenSectionExpanded: Bool { get }

    func toggleFavorite(_ report: AnalyticsCatalogReport)
    func toggleHidden(_ report: AnalyticsCatalogReport)
    func toggleHiddenSection()
}

// MARK: - Implementation

/// View model for the predefined-report menu. It carries the app/account context
/// forward to the detail screen, exposes the static catalog, and layers a
/// per-app favorites/hidden system on top. Favorite and hidden states are
/// mutually exclusive and persisted (scoped by `appId`) so they survive relaunch.
/// No API calls happen on this screen.
@MainActor
final class AnalyticsReportsViewModel: AnalyticsReportsViewModelProtocol {

    let appId: String
    let appName: String
    let account: AccountModel

    @Published private var favoriteIds: Set<String>
    @Published private var hiddenIds: Set<String>
    @Published private(set) var isHiddenSectionExpanded: Bool = false

    private let storage: KeyStorable

    private var favoritesKey: String { "analytics.favorites.\(appId)" }
    private var hiddenKey: String { "analytics.hidden.\(appId)" }

    /// Flattened catalog in section order — the canonical ordering used to keep
    /// favorites/hidden lists stable regardless of Set iteration order.
    private var allReports: [AnalyticsCatalogReport] {
        AnalyticsCatalog.sections.flatMap(\.reports)
    }

    init(
        appId: String,
        appName: String,
        account: AccountModel,
        storage: KeyStorable = UserDefaultsStorable()
    ) {
        self.appId = appId
        self.appName = appName
        self.account = account
        self.storage = storage

        // Hydrate synchronously so there is no empty-state flash on first render.
        let persistedFavorites: [String] = storage.object(forKey: "analytics.favorites.\(appId)") ?? []
        let persistedHidden: [String] = storage.object(forKey: "analytics.hidden.\(appId)") ?? []
        self.favoriteIds = Set(persistedFavorites)
        self.hiddenIds = Set(persistedHidden)
    }

    // MARK: - Derived state

    var sections: [(category: AnalyticsCategory, reports: [AnalyticsCatalogReport])] {
        AnalyticsCatalog.sections.compactMap { section in
            let visible = section.reports.filter { report in
                !favoriteIds.contains(report.id) && !hiddenIds.contains(report.id)
            }
            guard !visible.isEmpty else { return nil }
            return (section.category, visible)
        }
    }

    var favoriteReports: [AnalyticsCatalogReport] {
        allReports.filter { favoriteIds.contains($0.id) }
    }

    var hiddenReports: [AnalyticsCatalogReport] {
        allReports.filter { hiddenIds.contains($0.id) }
    }

    // MARK: - Actions

    func toggleFavorite(_ report: AnalyticsCatalogReport) {
        if favoriteIds.contains(report.id) {
            favoriteIds.remove(report.id)
            Log.print.info("[AnalyticsReports] Unfavorited \(report.apiName, privacy: .public) for app \(self.appId, privacy: .public)")
        } else {
            favoriteIds.insert(report.id)
            // Mutual exclusion: favoriting un-hides.
            hiddenIds.remove(report.id)
            Log.print.info("[AnalyticsReports] Favorited \(report.apiName, privacy: .public) for app \(self.appId, privacy: .public)")
        }
        persist()
    }

    func toggleHidden(_ report: AnalyticsCatalogReport) {
        if hiddenIds.contains(report.id) {
            hiddenIds.remove(report.id)
            Log.print.info("[AnalyticsReports] Unhid \(report.apiName, privacy: .public) for app \(self.appId, privacy: .public)")
        } else {
            hiddenIds.insert(report.id)
            // Mutual exclusion: hiding un-favorites.
            favoriteIds.remove(report.id)
            Log.print.info("[AnalyticsReports] Hid \(report.apiName, privacy: .public) for app \(self.appId, privacy: .public)")
        }
        persist()
    }

    func toggleHiddenSection() {
        isHiddenSectionExpanded.toggle()
    }

    // MARK: - Persistence

    private func persist() {
        storage.setObject(Array(favoriteIds), forKey: favoritesKey)
        storage.setObject(Array(hiddenIds), forKey: hiddenKey)
    }
}
