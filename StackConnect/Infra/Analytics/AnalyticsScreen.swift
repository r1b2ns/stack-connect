import Foundation

/// Every trackable screen and notable sheet. The `rawValue` is the snake_case
/// `screen_name` sent with each event; keep it stable once shipped, since
/// dashboards key off it.
///
/// Grouped by module folder under `StackConnect/Modules` (and the onboarding /
/// DS screens under `Infra/DS`), so auditing coverage is a matter of reading
/// this list top to bottom.
enum AnalyticsScreen: String, CaseIterable, Sendable {

    // MARK: Home
    case home = "home"
    case customizeWidgets = "customize_widgets"

    // MARK: Split view (iPad / Mac)
    /// Middle column of the In Review release queue (`RootReleaseQueue.inReview`).
    case releaseQueueInReview = "release_queue_in_review"
    /// Middle column of the Awaiting Release queue (`RootReleaseQueue.awaitingRelease`).
    case releaseQueueAwaitingRelease = "release_queue_awaiting_release"

    // MARK: Accounts
    case accountManagement = "account_management"
    case accountsList = "accounts_list"
    case accountsListImport = "accounts_list_import"
    case accountsListAddOptions = "accounts_list_add_options"
    case addAccount = "add_account"
    /// "Sign in with Apple ID" (Add Account, or signing in again).
    case appleIdSignIn = "apple_id_sign_in"
    /// The "sign in again" prompt of an expired Apple ID session.
    case appleSessionExpired = "apple_session_expired"

    // MARK: Settings
    case settings = "settings"
    case settingsAccounts = "settings_accounts"
    case settingsAccountAddOptions = "settings_account_add_options"
    case settingsAccountProviderPicker = "settings_account_provider_picker"
    case settingsAccountEdit = "settings_account_edit"
    case accountSettings = "account_settings"
    case exportAccount = "export_account"
    case importAccount = "import_account"
    case permissionPicker = "permission_picker"
    case appsPermissionPicker = "apps_permission_picker"
    case license = "license"
    case tipJar = "tip_jar"

    // MARK: Apps
    case appList = "app_list"
    case archivedApps = "archived_apps"
    case appDetail = "app_detail"
    case createPlatform = "create_platform"
    case appInformation = "app_information"
    case contentRights = "content_rights"
    case appCategoryPicker = "app_category_picker"
    case ageRating = "age_rating"
    case appPrivacy = "app_privacy"
    case appPrivacyEdit = "app_privacy_edit"
    case appAccessibility = "app_accessibility"
    case appAccessibilityAddDeviceFamily = "app_accessibility_add_device_family"
    case appAccessibilityEdit = "app_accessibility_edit"
    case appHistory = "app_history"
    case appReviewInfo = "app_review_info"
    case manageLocalizations = "manage_localizations"
    case addLocalization = "add_localization"
    case editLocalization = "edit_localization"
    case screenshotPreview = "screenshot_preview"
    case screenshotResolution = "screenshot_resolution"
    case screenshotGrid = "screenshot_grid"
    case screenshotPage = "screenshot_page"

    // MARK: Versions & review
    case versionList = "version_list"
    case versionDetail = "version_detail"
    case versionPromotionalText = "version_promotional_text"
    case versionDescription = "version_description"
    case versionWhatsNew = "version_whats_new"
    case localizationPicker = "localization_picker"
    case phasedRelease = "phased_release"
    case versionRelease = "version_release"
    case buildPicker = "build_picker"
    case preSubmitChecklist = "pre_submit_checklist"
    case submissions = "submissions"
    case appReviewDetail = "app_review_detail"

    // MARK: Builds & TestFlight
    case platformBuilds = "platform_builds"
    case availableBuilds = "available_builds"
    case buildDetail = "build_detail"
    case testFlight = "test_flight"
    case betaGroupDetail = "beta_group_detail"
    case createBetaGroup = "create_beta_group"
    case editBetaGroup = "edit_beta_group"
    case addTester = "add_tester"
    case internalTesterPicker = "internal_tester_picker"
    case submitBuildForReview = "submit_build_for_review"
    case betaGroupTesters = "beta_group_testers"
    case csvTesterImport = "csv_tester_import"
    case betaAppReviewInfo = "beta_app_review_info"

    // MARK: Certificates, Identifiers & Profiles
    case certificatesList = "certificates_list"
    case certificateDetail = "certificate_detail"
    case createCertificate = "create_certificate"
    case identifiersList = "identifiers_list"
    case identifierDetail = "identifier_detail"
    case createBundleId = "create_bundle_id"
    case addCapability = "add_capability"
    case profilesList = "profiles_list"
    case profileDetail = "profile_detail"
    case createProfile = "create_profile"
    case devicesList = "devices_list"
    case deviceDetail = "device_detail"
    case createDevice = "create_device"
    case importDevices = "import_devices"

    // MARK: Users
    case userAccess = "user_access"
    case inviteUser = "invite_user"
    case userDetail = "user_detail"
    case userRoleEditor = "user_role_editor"
    case userResourcesEditor = "user_resources_editor"
    case userVisibleAppsEditor = "user_visible_apps_editor"
    case userPermissions = "user_permissions"

    // MARK: Analytics reports (App Store Connect)
    case analyticsDashboard = "analytics_dashboard"
    case analyticsReports = "analytics_reports"
    case analyticsReportDetail = "analytics_report_detail"
    case analyticsReportFiles = "analytics_report_files"

    // MARK: Ratings & Reviews
    case ratingsReviews = "ratings_reviews"
    case allReviews = "all_reviews"
    case reviewDetail = "review_detail"
    case reviewReply = "review_reply"
    case replyTemplates = "reply_templates"
    case replyTemplateForm = "reply_template_form"

    // MARK: Firebase
    case firebaseProjectList = "firebase_project_list"
    case firebaseProjectDetail = "firebase_project_detail"
    case firebaseAppList = "firebase_app_list"
    case firebaseAppDetail = "firebase_app_detail"
    case createFirebaseApp = "create_firebase_app"
    case remoteConfig = "remote_config"
    case remoteConfigConditions = "remote_config_conditions"
    case remoteConfigAddCondition = "remote_config_add_condition"
    case remoteConfigCreateParameter = "remote_config_create_parameter"
    case remoteConfigParameterDetail = "remote_config_parameter_detail"
    case messaging = "messaging"
    case newCampaign = "new_campaign"

    // MARK: Google Play
    case googlePlayAppList = "google_play_app_list"
    case addGooglePlayApp = "add_google_play_app"
    case googlePlayUsers = "google_play_users"
    case googlePlayUserDetail = "google_play_user_detail"
    case googlePlayInviteUser = "google_play_invite_user"
    case googlePlayAppPermissions = "google_play_app_permissions"
    case googlePlayAccessExpiry = "google_play_access_expiry"
    case googlePlayAppDetail = "google_play_app_detail"
    case googlePlayAppInfo = "google_play_app_info"
    case googlePlayStoreListings = "google_play_store_listings"
    case googlePlayStoreListingDetail = "google_play_store_listing_detail"
    case googlePlayTracks = "google_play_tracks"
    case googlePlayReleaseDetail = "google_play_release_detail"
    case googlePlayNewRelease = "google_play_new_release"
    case googlePlayPromoteRelease = "google_play_promote_release"
    case googlePlayBundlePicker = "google_play_bundle_picker"
    case googlePlayRollout = "google_play_rollout"
    case googlePlayReviewChecklist = "google_play_review_checklist"

    // MARK: Onboarding & shared DS screens
    case welcome = "welcome"
    case onboarding = "onboarding"
    case releaseNotes = "release_notes"
    case feedback = "feedback"
    case importTutorial = "import_tutorial"
}
