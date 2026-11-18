import Foundation

/// Outcome events for meaningful (usually async) work, sent as `action_name`
/// with `action` events alongside an optional `AnalyticsResult`. Generic names
/// (`refresh`, …) are reused across screens; `screen_name` disambiguates.
enum AnalyticsAction: String, CaseIterable, Sendable {

    // MARK: Generic
    case refresh = "refresh"
    /// A screen's first (automatic) load, as opposed to `refresh` (pull to
    /// refresh, Retry). Sent with its outcome and `error_category`.
    case load = "load"
    /// A search session on a `.searchable` list: once per session, with
    /// `result_count_bucket` only — never the query (`View.trackSearch`).
    case search = "search"

    // MARK: Sync & connectivity
    /// One `SyncService` run (not a coalesced call), with `trigger`,
    /// `duration_bucket`, `count` / `failed_count` (accounts) and
    /// `error_category` on failure. Sent without `screen_name` from the
    /// background refresh task.
    case sync = "sync"
    /// The global offline banner appeared (once per appearance, no screen).
    case offlineBannerShown = "offline_banner_shown"

    // MARK: Notifications & prompts
    /// The system notification permission prompt was answered: `success`
    /// (granted), `cancelled` (denied) or `failure`.
    case requestNotificationPermission = "request_notification_permission"
    /// The App Store review request was handed to StoreKit (which decides
    /// whether it is actually displayed).
    case reviewPromptRequested = "review_prompt_requested"
    /// The Home "support the project" card became visible.
    case tipCardShown = "tip_card_shown"

    // MARK: Home
    case shareAgreementsRequest = "share_agreements_request"
    case addWidget = "add_widget"
    case removeWidget = "remove_widget"
    case reorderWidgets = "reorder_widgets"

    // MARK: Split view (iPad / Mac)
    /// A split view sidebar destination was opened, with `destination`
    /// (`AnalyticsSidebarDestination`) and `source` (`AnalyticsNavigationOrigin`:
    /// sidebar click, menu / keyboard command or dashboard KPI tile). Sent
    /// without `screen_name`, and only when the selection actually changes.
    case navigate = "navigate"
    /// The Find menu command (⌘F) asked the screen on display to focus its
    /// search field, with `source`. Never the search text.
    case find = "find"

    // MARK: Settings
    case deleteAllAccounts = "delete_all_accounts"
    case togglePreReviewChecklist = "toggle_pre_review_checklist"

    // MARK: Tip jar
    /// Sent with the outcome and `product_id` only: never a price, receipt or
    /// transaction identifier.
    case purchaseTip = "purchase_tip"

    // MARK: Accounts
    case createAccount = "create_account"
    case saveAccount = "save_account"
    case deleteAccount = "delete_account"
    case exportAccount = "export_account"
    case importAccount = "import_account"
    case reimportAccount = "reimport_account"
    /// "Sign in with Google" opened Google's page from Add Account, with `kind`
    /// (provider). The first step of the Google sign-in funnel.
    case googleSignInStarted = "google_sign_in_started"
    /// The Google sign-in finished: `success` (consent completed, with
    /// `missing_scope_count` for unticked checkboxes), `cancelled` (sheet
    /// closed) or `failure` with `error_category`. Sent with `kind`. The
    /// accounts then added are `create_account` with `auth_method`.
    case googleSignIn = "google_sign_in"

    // MARK: Activation
    /// The install's "first value" moment: the first time an app list loaded
    /// with at least one app. Sent once per install (`FirstAppsLoadedTracker`)
    /// with `count` (apps in that list) and `kind` (provider).
    case firstAppsLoaded = "first_apps_loaded"

    // MARK: Apps
    case syncApps = "sync_apps"
    case toggleArchive = "toggle_archive"
    case toggleFavorite = "toggle_favorite"

    // MARK: App Information / Privacy / Accessibility
    case updateContentRights = "update_content_rights"
    case updatePrimaryLocale = "update_primary_locale"
    case updateCategory = "update_category"
    case updateAgeRating = "update_age_rating"
    case updateAppPrivacy = "update_app_privacy"
    case updateAccessibility = "update_accessibility"
    case publishAccessibility = "publish_accessibility"
    case createAccessibility = "create_accessibility"
    case deleteAccessibility = "delete_accessibility"
    case updateAppReviewInfo = "update_app_review_info"
    case createLocalization = "create_localization"
    case updateLocalization = "update_localization"
    case deleteLocalization = "delete_localization"

    // MARK: Screenshots
    case downloadScreenshots = "download_screenshots"
    case deleteScreenshots = "delete_screenshots"

    // MARK: Versions
    case createVersion = "create_version"
    case deleteVersion = "delete_version"
    case preSubmitValidation = "pre_submit_validation"
    case submitForReview = "submit_for_review"
    case cancelReview = "cancel_review"
    case releaseVersion = "release_version"
    case rejectVersion = "reject_version"
    case cancelSubmission = "cancel_submission"
    case completePhasedRelease = "complete_phased_release"
    case pausePhasedRelease = "pause_phased_release"
    case updatePhasedRelease = "update_phased_release"
    case updateReleaseType = "update_release_type"
    case updatePromotionalText = "update_promotional_text"
    case updateDescription = "update_description"
    case updateWhatsNew = "update_whats_new"
    case saveVersionMetadata = "save_version_metadata"
    case selectBuild = "select_build"

    // MARK: Submissions
    case submitSubmission = "submit_submission"
    case discardSubmission = "discard_submission"

    // MARK: TestFlight / Builds
    case createBetaGroup = "create_beta_group"
    case deleteBetaGroup = "delete_beta_group"
    case updateBetaGroup = "update_beta_group"
    case expireBuild = "expire_build"
    case addBuildToGroup = "add_build_to_group"
    case removeBuildFromGroup = "remove_build_from_group"
    case submitBuildForBetaReview = "submit_build_for_beta_review"
    case inviteTester = "invite_tester"
    case inviteTesters = "invite_testers"
    case importTesters = "import_testers"
    case removeTester = "remove_tester"
    case resendInvite = "resend_invite"
    case updateBetaAppReviewInfo = "update_beta_app_review_info"

    // MARK: Certificates / Identifiers / Profiles / Devices
    case importCsr = "import_csr"
    case createCertificate = "create_certificate"
    case downloadCertificate = "download_certificate"
    case revokeCertificate = "revoke_certificate"
    case createBundleId = "create_bundle_id"
    case renameBundleId = "rename_bundle_id"
    case deleteBundleId = "delete_bundle_id"
    case enableCapability = "enable_capability"
    case disableCapability = "disable_capability"
    case createProfile = "create_profile"
    case downloadProfile = "download_profile"
    case deleteProfile = "delete_profile"
    case registerDevice = "register_device"
    case renameDevice = "rename_device"
    case toggleDeviceStatus = "toggle_device_status"
    case loadDevicesFile = "load_devices_file"
    case importDevices = "import_devices"

    // MARK: Users
    case inviteUser = "invite_user"
    case deleteUser = "delete_user"
    case updateUserRole = "update_user_role"
    case updateUserAccess = "update_user_access"
    case updateVisibleApps = "update_visible_apps"
    case updateUserPermissions = "update_user_permissions"
    case updateAppAccess = "update_app_access"
    case removeAppAccess = "remove_app_access"
    case saveDeveloperId = "save_developer_id"

    // MARK: Analytics reports
    case toggleHidden = "toggle_hidden"
    case enableReports = "enable_reports"
    case reactivateReports = "reactivate_reports"
    case deleteFiles = "delete_files"
    case shareFiles = "share_files"

    // MARK: Ratings & Reviews / Reply templates
    case filterReviews = "filter_reviews"
    case replyToReview = "reply_to_review"
    case updateReviewReply = "update_review_reply"
    case deleteReviewResponse = "delete_review_response"
    case createReplyTemplate = "create_reply_template"
    case updateReplyTemplate = "update_reply_template"
    case deleteReplyTemplate = "delete_reply_template"

    // MARK: Firebase / Google Play
    case reorderServices = "reorder_services"
    case createFirebaseApp = "create_firebase_app"
    case deleteFirebaseApp = "delete_firebase_app"
    case updateNickname = "update_nickname"
    case publishRemoteConfig = "publish_remote_config"
    case sendCampaign = "send_campaign"
    case deleteCampaign = "delete_campaign"
    case addGooglePlayApp = "add_google_play_app"
    case removeGooglePlayApp = "remove_google_play_app"

    // MARK: Google Play releases
    /// A committed Google Play release change (`GooglePlayReleaseWriteViewModel`),
    /// with `kind` (`AnalyticsReleaseWriteKind`), `track` (`AnalyticsTrackKind`),
    /// `send_for_review` and `error_category` on failure. Never a release
    /// name, version code or custom track name.
    case releaseWrite = "release_write"
    /// Listing the bundles uploaded to Google Play (New Release sheet).
    case fetchBundles = "fetch_bundles"
}

/// Result of an `AnalyticsAction`. Never carries error text: send an error
/// *category* as a separate typed parameter when needed.
enum AnalyticsResult: String, CaseIterable, Sendable {
    case success = "success"
    case failure = "failure"
    case cancelled = "cancelled"
    /// Deferred by the store (e.g. Ask to Buy): it may still complete later.
    case pending = "pending"
}
