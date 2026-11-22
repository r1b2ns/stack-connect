import Foundation
import StackProtocols

// Small, closed sets of values sent as analytics parameters. Each raw value is
// a stable snake_case string that dashboards and GA4 custom dimensions are
// built on: never rename one, and map new cases onto existing ones first.
// None of them can carry user data (names, ids, text, URLs).

// MARK: - Errors

/// How an error was shown (`presentation` of `error_shown`).
enum AnalyticsErrorPresentation: String, CaseIterable, Sendable {
    /// `StackErrorContentView`: nothing else on screen.
    case fullScreen = "full_screen"
    /// `StackInlineErrorSection`: above content that stays on screen.
    case inline = "inline"
}

// MARK: - Buckets

/// Coarse duration buckets (`duration_bucket`).
enum AnalyticsDurationBucket: String, CaseIterable, Sendable {
    case under5s = "under_5s"
    case from5To15s = "5_15s"
    case from15To30s = "15_30s"
    case from30To60s = "30_60s"
    case over60s = "over_60s"

    init(duration: Duration) {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        self.init(seconds: seconds)
    }

    init(seconds: Double) {
        switch seconds {
        case ..<5:  self = .under5s
        case ..<15: self = .from5To15s
        case ..<30: self = .from15To30s
        case ..<60: self = .from30To60s
        default:    self = .over60s
        }
    }
}

/// Coarse count buckets (`result_count_bucket`): enough to tell "nothing
/// found" from "a few" and "many", never an exact count of a user's data.
enum AnalyticsCountBucket: String, CaseIterable, Sendable {
    case zero = "0"
    case one = "1"
    case twoToFive = "2_5"
    case sixToTwenty = "6_20"
    case overTwenty = "21_plus"

    init(count: Int) {
        switch count {
        case ..<1:     self = .zero
        case 1:        self = .one
        case 2...5:    self = .twoToFive
        case 6...20:   self = .sixToTwenty
        default:       self = .overTwenty
        }
    }
}

// MARK: - Sync

/// What started a `SyncService` run (`trigger` of the `sync` action).
enum SyncTrigger: String, CaseIterable, Sendable {
    /// Automatic, while the app is in front (Home appearing).
    case foreground = "foreground"
    /// The background refresh task (`BGAppRefreshTask`).
    case background = "background"
    /// The user asked for it (pull to refresh).
    case manual = "manual"
}

// MARK: - Deep links

/// Where an app open came from (`source` of `app_opened_from`).
enum DeepLinkSource: String, CaseIterable, Sendable {
    case notification = "notification"
    case widget = "widget"
    /// Any other `stackconnect://` URL (Spotlight, Shortcuts, another app).
    case url = "url"

    /// Query item the widget adds to every URL it opens, so the app can tell a
    /// widget tap from any other URL. Ignored by `DeepLink(url:)`.
    static let queryItemName = "source"
    static let widgetQueryValue = "widget"

    /// The source of a URL that reached `onOpenURL`: the widget marks its
    /// URLs, anything else is a plain URL.
    init(openedURL url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let isWidget = items.contains { $0.name == Self.queryItemName && $0.value == Self.widgetQueryValue }
        self = isWidget ? .widget : .url
    }
}

/// The route kind a deep link opened (`destination` of `app_opened_from`).
enum AnalyticsDeepLinkDestination: String, CaseIterable, Sendable {
    case home = "home"
    case reviews = "reviews"
    case app = "app"
    case review = "review"
    case reimport = "reimport"
    /// Not a link the app understands.
    case unknown = "unknown"

    init(url: URL) {
        guard let link = DeepLink(url: url) else {
            self = .unknown
            return
        }
        switch link {
        case .home:     self = .home
        case .reviews:  self = .reviews
        case .app:      self = .app
        case .review:   self = .review
        case .reimport: self = .reimport
        }
    }
}

// MARK: - Google Play

/// A Google Play track by kind (`track`). Custom track names are chosen by
/// the developer, so they all collapse into `custom`.
enum AnalyticsTrackKind: String, CaseIterable, Sendable {
    case production = "production"
    case openTesting = "open_testing"
    case closedTesting = "closed_testing"
    case internalTesting = "internal_testing"
    case custom = "custom"

    init(_ kind: GooglePlayTrackKind) {
        switch kind {
        case .production:      self = .production
        case .openTesting:     self = .openTesting
        case .closedTesting:   self = .closedTesting
        case .internalTesting: self = .internalTesting
        case .custom:          self = .custom
        }
    }

    init(track: String) {
        self.init(GooglePlayTrackKind(track: track))
    }
}

/// What a Google Play release write does (`kind` of `release_write`).
enum AnalyticsReleaseWriteKind: String, CaseIterable, Sendable {
    case setRollout = "set_rollout"
    case halt = "halt"
    case resume = "resume"
    case complete = "complete"
    case updateMetadata = "update_metadata"
    case create = "create"
    case promote = "promote"

    init(_ change: GooglePlayReleaseChange) {
        switch change {
        case .setRollout:     self = .setRollout
        case .halt:           self = .halt
        case .resume:         self = .resume
        case .complete:       self = .complete
        case .updateMetadata: self = .updateMetadata
        case .create:         self = .create
        case .promote:        self = .promote
        }
    }
}

// MARK: - Split view navigation

/// Where a root navigation (split view sidebar item or compact tab) came from (`source` of the `navigate` and
/// `find` actions, and of the menu `refresh`). Same key as the deep-link
/// `source` of `app_opened_from`: the action name tells the two value sets
/// apart.
enum AnalyticsNavigationOrigin: String, CaseIterable, Sendable {
    /// A click (or keyboard selection) in the split view sidebar, including
    /// its "+" header buttons and account context menus.
    case sidebar = "sidebar"
    /// A menu-bar command or its keyboard shortcut (⌘⇧N, ⌘F, ⌘R, ⌘1–4, ⌘,).
    case menuCommand = "menu_command"
    /// A release queue KPI tile on the iPad / Mac dashboard.
    case dashboardTile = "dashboard_tile"
    /// The compact-width tab bar (Accounts / Settings).
    case tabBar = "tab_bar"
}

/// The kind of split view sidebar item opened (`destination` of `navigate`).
/// Accounts are reduced to the team tool shown: never an account name or id.
/// Same key as the deep-link `destination` of `app_opened_from`.
enum AnalyticsSidebarDestination: String, CaseIterable, Sendable {
    case dashboard = "dashboard"
    case releaseQueueInReview = "release_queue_in_review"
    case releaseQueueAwaitingRelease = "release_queue_awaiting_release"
    case recentReviews = "recent_reviews"
    case accountApps = "account_apps"
    case accountUsers = "account_users"
    case accountDevices = "account_devices"
    case accountCertificates = "account_certificates"
    case accountIdentifiers = "account_identifiers"
    case accountProfiles = "account_profiles"
    case accountManage = "account_manage"
    case addAccount = "add_account"
    case settings = "settings"

    init(_ item: RootSidebarItem) {
        switch item {
        case .dashboard:                       self = .dashboard
        case .releaseQueue(.inReview):         self = .releaseQueueInReview
        case .releaseQueue(.awaitingRelease):  self = .releaseQueueAwaitingRelease
        case .recentReviews:                   self = .recentReviews
        case .account(_, let section):         self.init(section)
        case .addAccount:                      self = .addAccount
        case .settings:                        self = .settings
        }
    }

    private init(_ section: RootAccountSection) {
        switch section {
        case .apps:         self = .accountApps
        case .users:        self = .accountUsers
        case .devices:      self = .accountDevices
        case .certificates: self = .accountCertificates
        case .identifiers:  self = .accountIdentifiers
        case .profiles:     self = .accountProfiles
        case .manage:       self = .accountManage
        }
    }
}

/// The root layout picked by `AppRootView` (`ui_layout` user property).
enum AnalyticsUILayout: String, CaseIterable, Sendable {
    /// Compact width: the iPhone Home stack (iPhone, Slide Over, narrow windows).
    case compact = "compact"
    /// Regular width: the split view (iPad full screen, wide windows, Mac).
    case regular = "regular"
}

// MARK: - Reviews inbox

/// The Reviews inbox filter (`kind` of `filter_reviews` on `all_reviews`).
enum AnalyticsReviewsFilter: String, CaseIterable, Sendable {
    case all = "all"
    case appStore = "app_store"
    case googlePlay = "google_play"
    case unreplied = "unreplied"

    init(_ filter: AllReviewsFilter) {
        switch filter {
        case .all:        self = .all
        case .appStore:   self = .appStore
        case .googlePlay: self = .googlePlay
        case .unreplied:  self = .unreplied
        }
    }
}

// MARK: - Error category of any error

extension AnalyticsErrorCategory {

    /// `[error_category: …]` for `error` (by type and status code only, see
    /// `init(connectionError:)`), or nothing without an error.
    static func parameters(for error: Error?) -> [String: AnalyticsValue] {
        guard let error else { return [:] }
        return AnalyticsErrorCategory(connectionError: error).parameters
    }

    /// Categories worth a Crashlytics non-fatal: the service misbehaved or the
    /// error is not understood. User errors (validation, credentials, offline…)
    /// are expected and never recorded.
    var isReportableAsNonFatal: Bool {
        self == .server || self == .unknown
    }
}

// MARK: - Account auth method

extension AccountAuthMethod {
    /// The `auth_method` value: stable snake_case, independent of the stored raw value.
    var analyticsValue: String {
        switch self {
        case .keyFile:      return "key_file"
        case .googleSignIn: return "google_sign_in"
        case .appleIdSignIn: return "apple_id_sign_in"
        }
    }
}
