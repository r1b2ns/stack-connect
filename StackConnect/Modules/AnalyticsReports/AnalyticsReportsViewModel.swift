import Foundation

// MARK: - Protocol

@MainActor
protocol AnalyticsReportsViewModelProtocol: ObservableObject {
    var appId: String { get }
    var appName: String { get }
    var account: AccountModel { get }
    var sections: [(category: AnalyticsCategory, reports: [AnalyticsCatalogReport])] { get }
}

// MARK: - Implementation

/// Purely presentational view model for the predefined-report menu. It carries
/// the app/account context forward to the detail screen and exposes the static
/// catalog. No API calls happen on this screen.
@MainActor
final class AnalyticsReportsViewModel: AnalyticsReportsViewModelProtocol {

    let appId: String
    let appName: String
    let account: AccountModel

    var sections: [(category: AnalyticsCategory, reports: [AnalyticsCatalogReport])] {
        AnalyticsCatalog.sections
    }

    init(appId: String, appName: String, account: AccountModel) {
        self.appId = appId
        self.appName = appName
        self.account = account
    }
}
