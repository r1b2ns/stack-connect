import Foundation

// MARK: - Domain Options
//
// Shared analytics vocabulary used by the predefined-report menu and the report
// detail screen. The raw values are the exact App Store Connect wire strings
// expected by the Rust core; the display names are user-facing. (Relocated from
// the retired AnalyticsReportConfig module.)

/// How Apple keeps the report data fresh. Set at request time.
enum AnalyticsAccessType: String, CaseIterable, Identifiable {
    case ongoing = "ONGOING"
    case oneTimeSnapshot = "ONE_TIME_SNAPSHOT"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ongoing:          return String(localized: "Ongoing")
        case .oneTimeSnapshot:  return String(localized: "One-Time Snapshot")
        }
    }

    var summary: String {
        switch self {
        case .ongoing:
            return String(localized: "Continuously generated and updated daily.")
        case .oneTimeSnapshot:
            return String(localized: "A single historical snapshot generated once.")
        }
    }
}

/// The report category. Doubles as the section grouping in the predefined menu
/// and as the browsing filter when resolving a report from the API.
enum AnalyticsCategory: String, CaseIterable, Identifiable {
    case appStoreEngagement = "APP_STORE_ENGAGEMENT"
    case appStoreCommerce = "COMMERCE"
    case appUsage = "APP_USAGE"
    case frameworks = "FRAMEWORK_USAGE"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appStoreEngagement: return String(localized: "App Store Engagement")
        case .appStoreCommerce:   return String(localized: "App Store Commerce")
        case .appUsage:           return String(localized: "App Usage")
        case .frameworks:         return String(localized: "Frameworks")
        }
    }

    /// Best-effort display name for a raw ASC category value, falling back to
    /// the raw string when it is not one of the known categories.
    static func displayName(forRaw raw: String) -> String {
        AnalyticsCategory(rawValue: raw)?.displayName ?? raw
    }
}

/// The reporting granularity. Used both as a segmented toggle on the detail
/// screen and as the browsing filter over a report's instances.
enum AnalyticsGranularity: String, CaseIterable, Identifiable {
    case daily = "DAILY"
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily:   return String(localized: "Daily")
        case .weekly:  return String(localized: "Weekly")
        case .monthly: return String(localized: "Monthly")
        }
    }

    static func displayName(forRaw raw: String) -> String {
        AnalyticsGranularity(rawValue: raw)?.displayName ?? raw
    }
}

// MARK: - Catalog Report

/// A single predefined report shown in the menu. `apiName` is the canonical
/// Apple report name used to match the `report.name` returned by the API;
/// `displayName` is the short, user-facing label. `id == apiName` keeps rows
/// stable and lets the struct flow through `HomeRoute` as a `Hashable` value.
struct AnalyticsCatalogReport: Hashable, Identifiable {
    var id: String { apiName }
    let displayName: String
    let apiName: String
    let category: AnalyticsCategory
}

// MARK: - Catalog

/// Static, curated catalog of predefined App Store Connect analytics reports,
/// grouped by category. No network access — purely presentational. The
/// `apiName` values are verified against Apple's `analytics-reports`
/// documentation and are matched (normalized) against the live report names.
enum AnalyticsCatalog {

    static let sections: [(category: AnalyticsCategory, reports: [AnalyticsCatalogReport])] = [
        (
            .appStoreEngagement,
            [
                AnalyticsCatalogReport(displayName: String(localized: "Discovery and Engagement"), apiName: "App Store Discovery and Engagement", category: .appStoreEngagement),
                AnalyticsCatalogReport(displayName: String(localized: "Web Preview"), apiName: "App Store Web Preview", category: .appStoreEngagement),
                AnalyticsCatalogReport(displayName: String(localized: "Retention Messaging"), apiName: "App Store Retention Messaging", category: .appStoreEngagement)
            ]
        ),
        (
            .appStoreCommerce,
            [
                AnalyticsCatalogReport(displayName: String(localized: "Downloads"), apiName: "App Store Downloads", category: .appStoreCommerce),
                AnalyticsCatalogReport(displayName: String(localized: "Pre-Orders"), apiName: "App Store Pre-orders", category: .appStoreCommerce),
                AnalyticsCatalogReport(displayName: String(localized: "Purchases"), apiName: "App Store Purchases", category: .appStoreCommerce),
                AnalyticsCatalogReport(displayName: String(localized: "Subscription State"), apiName: "App Store Subscription State", category: .appStoreCommerce),
                AnalyticsCatalogReport(displayName: String(localized: "Subscription Events"), apiName: "App Store Subscription Event", category: .appStoreCommerce)
            ]
        ),
        (
            .appUsage,
            [
                AnalyticsCatalogReport(displayName: String(localized: "Shortcut App Usage"), apiName: "Shortcut App Usage", category: .appUsage),
                AnalyticsCatalogReport(displayName: String(localized: "Installation and Deletion"), apiName: "App Store Installations and Deletions", category: .appUsage),
                AnalyticsCatalogReport(displayName: String(localized: "Sessions"), apiName: "App Sessions", category: .appUsage),
                AnalyticsCatalogReport(displayName: String(localized: "Clip Usage"), apiName: "App Clip Usage", category: .appUsage),
                AnalyticsCatalogReport(displayName: String(localized: "App Crashes"), apiName: "App Crashes", category: .appUsage),
                AnalyticsCatalogReport(displayName: String(localized: "Platform App Installs"), apiName: "Platform App Installs", category: .appUsage),
                AnalyticsCatalogReport(displayName: String(localized: "Shortcuts Actions Usage"), apiName: "Shortcuts Actions Usage", category: .appUsage),
                AnalyticsCatalogReport(displayName: String(localized: "App Opt-In"), apiName: "App Store Opt-in", category: .appUsage),
                AnalyticsCatalogReport(displayName: String(localized: "CarPlay App Usage"), apiName: "CarPlay App Usage", category: .appUsage)
            ]
        ),
        (
            .frameworks,
            [
                AnalyticsCatalogReport(displayName: String(localized: "Photos Picker"), apiName: "Photos Picker", category: .frameworks),
                AnalyticsCatalogReport(displayName: String(localized: "Photos Library Access"), apiName: "Photos Library Access", category: .frameworks),
                AnalyticsCatalogReport(displayName: String(localized: "Home Screen Widgets"), apiName: "Home Screen Widgets", category: .frameworks),
                AnalyticsCatalogReport(displayName: String(localized: "Home Screen Widget Usage"), apiName: "Home Screen Widget Usage", category: .frameworks),
                AnalyticsCatalogReport(displayName: String(localized: "Live Activities"), apiName: "Live Activity Use", category: .frameworks),
                AnalyticsCatalogReport(displayName: String(localized: "Notification Summary Engagement"), apiName: "Notification Summary Engagement", category: .frameworks),
                AnalyticsCatalogReport(displayName: String(localized: "CarPlay Navigation"), apiName: "CarPlay Navigation", category: .frameworks),
                AnalyticsCatalogReport(displayName: String(localized: "Core Location Authorization"), apiName: "Core Location Authorization Results", category: .frameworks),
                AnalyticsCatalogReport(displayName: String(localized: "ARKit World Tracking"), apiName: "ARKit World Tracking", category: .frameworks),
                AnalyticsCatalogReport(displayName: String(localized: "ShazamKit Usage"), apiName: "ShazamKit Usage", category: .frameworks),
                AnalyticsCatalogReport(displayName: String(localized: "SharePlay Usage"), apiName: "SharePlay Usage by Activity Type", category: .frameworks),
                AnalyticsCatalogReport(displayName: String(localized: "Flashlight Usage"), apiName: "Flashlight Usage", category: .frameworks)
            ]
        )
    ]
}
