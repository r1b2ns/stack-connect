import Foundation

/// Tap identifiers sent as `button_name` with `button_tap` events. Generic
/// names (`save`, `delete`, `cancel`, …) are reused across screens because
/// `screen_name` disambiguates them. Keep raw values snake_case and stable once
/// shipped.
enum AnalyticsButton: String, CaseIterable, Sendable {

    // MARK: Generic
    case add = "add"
    case cancel = "cancel"
    case close = "close"
    case confirmDelete = "confirm_delete"
    case copy = "copy"
    case delete = "delete"
    case done = "done"
    case edit = "edit"
    case export = "export"
    case ok = "ok"
    case paste = "paste"
    case save = "save"
    case seeMore = "see_more"
    case selectAll = "select_all"
    case selectNone = "select_none"
    case tryAgain = "try_again"
    case select = "select"
    case create = "create"
    case remove = "remove"
    case confirmRemove = "confirm_remove"
    case invite = "invite"
    case back = "back"
    case `continue` = "continue"
    case download = "download"

    // MARK: Home
    case customizeWidgets = "customize_widgets"
    case dismissAgreementsBanner = "dismiss_agreements_banner"
    case shareAgreementsRequest = "share_agreements_request"
    case reviewAgreements = "review_agreements"
    /// The Home "support the project" card (or its Support button) was tapped.
    case openTipCard = "open_tip_card"
    /// The Home "support the project" card was closed.
    case dismissTipCard = "dismiss_tip_card"
    case widgetApp = "widget_app"
    case widgetReview = "widget_review"
    case appleProvider = "apple_provider"
    case firebaseProvider = "firebase_provider"
    case googlePlayProvider = "google_play_provider"

    // MARK: Settings
    case settings = "settings"
    case accounts = "accounts"
    case github = "github"
    case license = "license"
    case supportProject = "support_project"
    case deleteAllAccounts = "delete_all_accounts"
    case confirmDeleteAllAccounts = "confirm_delete_all_accounts"

    // MARK: Tip jar
    case purchaseTip = "purchase_tip"

    // MARK: Accounts
    case account = "account"
    case addAccount = "add_account"
    case createNew = "create_new"
    case editName = "edit_name"
    case certificates = "certificates"
    case identifiers = "identifiers"
    case devices = "devices"
    case profiles = "profiles"

    // MARK: Account import / export
    case importAccount = "import_account"
    case howToImport = "how_to_import"
    case importFile = "import_file"
    case decrypt = "decrypt"
    case confirmImport = "confirm_import"
    case reimport = "reimport"
    case editPermission = "edit_permission"
    case togglePermission = "toggle_permission"
    case selectApps = "select_apps"
    case toggleApp = "toggle_app"
    case togglePasswordVisibility = "toggle_password_visibility"
    case generatePassword = "generate_password"
    case copyPassword = "copy_password"

    // MARK: Apps
    case app = "app"
    case accountSettings = "account_settings"
    case editDeveloperId = "edit_developer_id"
    case saveDeveloperId = "save_developer_id"
    case accessExpiry = "access_expiry"
    case preset = "preset"
    case inviteUser = "invite_user"
    case archive = "archive"
    case unarchive = "unarchive"
    case favorite = "favorite"
    case archivedApps = "archived_apps"

    // MARK: App Detail
    case appInformation = "app_information"
    case submissions = "submissions"
    case history = "history"
    case appPrivacy = "app_privacy"
    case appAccessibility = "app_accessibility"
    case ratingsReviews = "ratings_reviews"
    case analytics = "analytics"
    case testFlight = "test_flight"
    case resolutionCenter = "resolution_center"
    case createPlatform = "create_platform"

    // MARK: App Information / Privacy / Accessibility
    case localizations = "localizations"
    case localization = "localization"
    case category = "category"
    case contentRights = "content_rights"
    case ageRating = "age_rating"
    case viewOnAppStore = "view_on_app_store"
    case manageDataCollection = "manage_data_collection"
    case declaration = "declaration"
    case deviceFamily = "device_family"
    case publish = "publish"

    // MARK: Versions
    case version = "version"
    case seeAll = "see_all"
    case submitForReview = "submit_for_review"
    case confirmSubmit = "confirm_submit"
    case release = "release"
    case confirmRelease = "confirm_release"
    case reject = "reject"
    case confirmReject = "confirm_reject"
    case cancelReview = "cancel_review"
    case confirmCancelReview = "confirm_cancel_review"
    case cancelSubmission = "cancel_submission"
    case confirmCancelSubmission = "confirm_cancel_submission"
    case completePhasedRelease = "complete_phased_release"
    case confirmCompletePhasedRelease = "confirm_complete_phased_release"
    case build = "build"
    case screenshots = "screenshots"
    case promotionalText = "promotional_text"
    case appDescription = "app_description"
    case whatsNew = "whats_new"
    case appReviewInfo = "app_review_info"
    case releaseOptions = "release_options"
    case releaseType = "release_type"
    case phasedRelease = "phased_release"
    case usePhasedRelease = "use_phased_release"
    case releaseImmediately = "release_immediately"
    case pausePhasedRelease = "pause_phased_release"
    case resumePhasedRelease = "resume_phased_release"
    case manageSubmissions = "manage_submissions"

    // MARK: Screenshots
    case device = "device"
    case screenshotSet = "screenshot_set"
    case screenshot = "screenshot"
    case downloadAll = "download_all"

    // MARK: Submissions / App Review
    case submission = "submission"
    case discard = "discard"
    case confirmDiscard = "confirm_discard"
    case resubmit = "resubmit"
    case confirmResubmit = "confirm_resubmit"
    case openAppStoreConnect = "open_app_store_connect"

    // MARK: TestFlight / Builds
    case betaGroup = "beta_group"
    case expire = "expire"
    case confirmExpire = "confirm_expire"
    case addBuild = "add_build"
    case testInformation = "test_information"
    case testers = "testers"
    case resendInvite = "resend_invite"

    // MARK: Certificates / Identifiers / Profiles / Devices
    case certificate = "certificate"
    case revoke = "revoke"
    case confirmRevoke = "confirm_revoke"
    case identifier = "identifier"
    case addCapability = "add_capability"
    case removeCapability = "remove_capability"
    case profile = "profile"
    case registerDevice = "register_device"
    case importDevices = "import_devices"
    case register = "register"
    case toggleStatus = "toggle_status"

    // MARK: Users
    case user = "user"
    case filter = "filter"
    case toggleRole = "toggle_role"
    case editRole = "edit_role"
    case editAccess = "edit_access"
    case editVisibleApps = "edit_visible_apps"
    case permissions = "permissions"

    // MARK: Analytics reports
    case enableApi = "enable_api"
    case report = "report"
    case hide = "hide"
    case hiddenSection = "hidden_section"
    case enableReports = "enable_reports"
    case reactivate = "reactivate"
    case files = "files"
    case share = "share"

    // MARK: Ratings & Reviews / Reply templates
    case review = "review"
    case reply = "reply"
    case sort = "sort"
    case send = "send"
    case replyTemplates = "reply_templates"
    case template = "template"

    // MARK: Firebase / Google Play
    case project = "project"
    case apps = "apps"
    case remoteConfig = "remote_config"
    case messaging = "messaging"
    case parameter = "parameter"
    case duplicate = "duplicate"
}

extension AnalyticsButton {
    /// The provider card / picker row for `provider`.
    static func providerButton(for provider: ProviderType) -> AnalyticsButton {
        switch provider {
        case .apple: return .appleProvider
        case .firebase: return .firebaseProvider
        case .googlePlay: return .googlePlayProvider
        }
    }
}
