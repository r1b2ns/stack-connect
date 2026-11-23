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
    case next = "next"
    case loadMore = "load_more"
    /// "Share Error" on a full-screen / inline error or an error alert.
    case shareError = "share_error"
    /// Skips the rest of a paged guide (the connection guide).
    case skip = "skip"

    // MARK: Home
    case customizeWidgets = "customize_widgets"
    case dismissAgreementsBanner = "dismiss_agreements_banner"
    case shareAgreementsRequest = "share_agreements_request"
    case reviewAgreements = "review_agreements"
    /// The Home "support the project" card (or its Support button) was tapped.
    case openTipCard = "open_tip_card"
    /// The Home "support the project" card was closed.
    case dismissTipCard = "dismiss_tip_card"
    /// The Home "sign in again" banner, with several expired sign-ins: open
    /// the list to choose one. (With one, its button tracks `signInAgain`.)
    case chooseSignInAgain = "choose_sign_in_again"
    /// The Home "sign in again" banner was closed (until the next launch).
    case dismissSignInAgainBanner = "dismiss_sign_in_again_banner"
    /// The Home banner (or its list) of an Apple ID whose automatic sign-in
    /// is waiting for the two-factor code Apple sent: type it.
    case enterCode = "enter_code"
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
    /// Add Account: the primary "Sign in with Google" button (Play, Firebase).
    case signInWithGoogle = "sign_in_with_google"
    /// Add Account: switch to the service account JSON form (advanced path).
    case useServiceAccount = "use_service_account"
    /// Add Account: back from the JSON form to "Sign in with Google".
    case useGoogleSignIn = "use_google_sign_in"
    /// Add Account: ask Google again for the scopes left unticked.
    case grantMissingAccess = "grant_missing_access"
    /// Remote Config / Analytics of a Google sign-in account: ask Google for
    /// the extra permission the screen needs.
    case grantGoogleAccess = "grant_google_access"
    /// A Firebase screen whose Google sign-in expired or was revoked, or the
    /// Home "sign in again" banner (Apple ID or Google): sign in again with
    /// the same account.
    case signInAgain = "sign_in_again"
    /// Add Account (App Store Connect): open "Sign in with Apple ID", and its
    /// primary button on the Apple ID and password screen.
    case signInWithAppleId = "sign_in_with_apple_id"
    /// Apple ID sign-in: submit the two-factor code.
    case submitCode = "submit_code"
    /// Apple ID sign-in: text the code to a trusted phone instead.
    case sendSms = "send_sms"
    /// Apple ID sign-in: (de)select a team to add.
    case toggleTeam = "toggle_team"
    /// Apple ID sign-in: open appleid.apple.com (the Apple ID needs action).
    case openAppleIdWebsite = "open_apple_id_website"
    /// Apple ID sign-in: type a password instead of the one saved on the device.
    case useDifferentPassword = "use_different_password"
    /// Apple ID sign-in: "Save password on this device" turned on / off.
    case savePasswordOn = "save_password_on"
    case savePasswordOff = "save_password_off"
    /// The expired Apple ID session prompt: dismiss it for now.
    case notNow = "not_now"
    /// Add Account's method chooser: the API key card (App Store Connect).
    /// The other cards report `use_apple_id_sign_in`, `use_google_sign_in`
    /// and `use_service_account` (see `connectionMethodButton(for:)`).
    case useApiKey = "use_api_key"
    /// Add Account's method chooser: the "Sign in with email and password"
    /// card (App Store Connect).
    case useAppleIdSignIn = "use_apple_id_sign_in"
    /// Add Account (method chooser or form): reopens the connection guide.
    case howItWorks = "how_it_works"
    /// The email and password screen's trust panel: opens "How Your Password
    /// Is Used".
    case howPasswordIsUsed = "how_password_is_used"
    /// Opens the open-source repository on GitHub (connection guide, "How
    /// Your Password Is Used").
    case sourceCode = "source_code"
    /// Opens one source file on GitHub ("How Your Password Is Used").
    case sourceFile = "source_file"
    /// Opens StackConnect's privacy policy (connection guide, "How Your
    /// Password Is Used").
    case privacyPolicy = "privacy_policy"
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
    case confirmResendInvite = "confirm_resend_invite"

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

    // MARK: Ratings & Reviews
    case showAllRatings = "show_all_ratings"

    // MARK: Users (Google Play)
    case addApp = "add_app"
    case removeAppAccess = "remove_app_access"

    // MARK: Google Play app & releases
    case storeListings = "store_listings"
    case storeListing = "store_listing"
    case tracks = "tracks"
    case appDetails = "app_details"
    case seeAllTracks = "see_all_tracks"
    case openPlayConsole = "open_play_console"
    case newRelease = "new_release"
    case stagedRollout = "staged_rollout"
    case rollOut = "roll_out"
    case increaseRollout = "increase_rollout"
    case haltRollout = "halt_rollout"
    case resumeRollout = "resume_rollout"
    case releaseToAll = "release_to_all"
    case promote = "promote"
    /// A Play app's website / email / phone link (App Details).
    case contact = "contact"
    case promoVideo = "promo_video"
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

    /// The method chooser card of `method` (Add Account). Google sign-in and
    /// the service account reuse the names of the in-form switch they replace.
    static func connectionMethodButton(for method: AccountConnectionMethod) -> AnalyticsButton {
        switch method {
        case .apiKey:         return .useApiKey
        case .appleIdSignIn:  return .useAppleIdSignIn
        case .googleSignIn:   return .useGoogleSignIn
        case .serviceAccount: return .useServiceAccount
        }
    }
}
