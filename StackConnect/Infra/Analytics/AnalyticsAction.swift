import Foundation

/// Outcome events for meaningful (usually async) work, sent as `action_name`
/// with `action` events alongside an optional `AnalyticsResult`. Generic names
/// (`refresh`, …) are reused across screens; `screen_name` disambiguates.
enum AnalyticsAction: String, CaseIterable, Sendable {

    // MARK: Generic
    case refresh = "refresh"

    // MARK: Home
    case shareAgreementsRequest = "share_agreements_request"
    case addWidget = "add_widget"
    case removeWidget = "remove_widget"
    case reorderWidgets = "reorder_widgets"

    // MARK: Settings
    case deleteAllAccounts = "delete_all_accounts"
    case togglePreReviewChecklist = "toggle_pre_review_checklist"

    // MARK: Accounts
    case createAccount = "create_account"
    case saveAccount = "save_account"
    case deleteAccount = "delete_account"
    case exportAccount = "export_account"
    case importAccount = "import_account"
    case reimportAccount = "reimport_account"

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
}

/// Result of an `AnalyticsAction`. Never carries error text: send an error
/// *category* as a separate typed parameter when needed.
enum AnalyticsResult: String, CaseIterable, Sendable {
    case success = "success"
    case failure = "failure"
    case cancelled = "cancelled"
}
