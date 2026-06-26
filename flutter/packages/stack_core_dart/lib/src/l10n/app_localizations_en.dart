// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appsTitle => 'Apps';

  @override
  String get refresh => 'Refresh';

  @override
  String get archived => 'Archived';

  @override
  String get favoritesSection => 'Favorites';

  @override
  String get allAppsSection => 'All apps';

  @override
  String get noAppsForAccount => 'No apps found for this account.';

  @override
  String get addToFavorites => 'Add to favorites';

  @override
  String get removeFromFavorites => 'Remove from favorites';

  @override
  String get archiveAction => 'Archive';

  @override
  String get addedToFavorites => 'Added to favorites';

  @override
  String get removedFromFavorites => 'Removed from favorites';

  @override
  String get archivedToast => 'Archived';

  @override
  String get unarchivedToast => 'Unarchived';

  @override
  String get couldNotUpdateApp => 'Could not update app';

  @override
  String get couldNotLoadApps => 'Could not load apps';

  @override
  String get noArchivedApps => 'No archived apps.';

  @override
  String get unarchiveAction => 'Unarchive';

  @override
  String get appFallbackTitle => 'App';

  @override
  String get appNotFound => 'App not found.';

  @override
  String get favoriteAction => 'Favorite';

  @override
  String get unfavoriteAction => 'Unfavorite';

  @override
  String get fieldName => 'Name';

  @override
  String get fieldBundleId => 'Bundle ID';

  @override
  String get fieldPlatform => 'Platform';

  @override
  String get ratingsAndReviews => 'Ratings & Reviews';

  @override
  String get navHome => 'Home';

  @override
  String get navMobileSection => 'Mobile';

  @override
  String get navAppStoreConnect => 'App Store Connect';

  @override
  String get navDevelopmentSection => 'Development';

  @override
  String get soonTag => 'Soon';

  @override
  String get collapseSidebar => 'Collapse sidebar';

  @override
  String get expandSidebar => 'Expand sidebar';

  @override
  String get addAccount => 'Add account';

  @override
  String get noAccountsYetDesktop =>
      'No accounts yet. Use \"Add account\" above to connect one.';

  @override
  String get couldNotLoadAccounts => 'Could not load accounts';

  @override
  String get noWidgetsYet => 'No widgets yet';

  @override
  String get noWidgetsDescription =>
      'Widgets to keep an eye on your apps will live here.';

  @override
  String get accountsTitle => 'Accounts';

  @override
  String get noAccountsConnected => 'No accounts connected yet.';

  @override
  String get close => 'Close';

  @override
  String get removeAccountTitle => 'Remove account';

  @override
  String get removeAction => 'Remove';

  @override
  String get couldNotRemoveAccount => 'Could not remove account';

  @override
  String get couldNotLoadReviews => 'Could not load reviews';

  @override
  String get noReviewsYet => 'No reviews yet.';

  @override
  String get replyAction => 'Reply';

  @override
  String get editReplyAction => 'Edit reply';

  @override
  String get replyToReviewTitle => 'Reply to review';

  @override
  String get writeYourResponse => 'Write your response…';

  @override
  String get cancel => 'Cancel';

  @override
  String get submit => 'Submit';

  @override
  String get replySubmitted => 'Reply submitted';

  @override
  String get replySubmittedToast => 'Reply submitted.';

  @override
  String get replyFailed => 'Reply failed';

  @override
  String get developerResponse => 'Developer response';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsAbout => 'About';

  @override
  String get github => 'GitHub';

  @override
  String get license => 'License';

  @override
  String get settingsDanger => 'Danger';

  @override
  String get deleteAllAccounts => 'Delete All Accounts';

  @override
  String get deleteAllAccountsBody =>
      'This will permanently delete all accounts, apps, versions, and credentials from the app. This action cannot be undone.';

  @override
  String get deleteAll => 'Delete All';

  @override
  String get couldNotOpenGitHub => 'Could not open GitHub';

  @override
  String get done => 'Done';

  @override
  String get appName => 'StackConnect';

  @override
  String get couldNotLoadLicense => 'Could not load the license text.';

  @override
  String get settingsComingSoon => 'Settings coming soon';

  @override
  String get noAccountsYet => 'No accounts yet';

  @override
  String get connectAccountToStart =>
      'Connect an App Store Connect account to get started.';

  @override
  String get testFlightBuilds => 'TestFlight Builds';

  @override
  String get noBuildsYet => 'No builds yet.';

  @override
  String get expired => 'Expired';

  @override
  String get processing => 'Processing';

  @override
  String get external => 'External';

  @override
  String get internal => 'Internal';

  @override
  String get buildFallback => 'Build';

  @override
  String get appStoreVersions => 'App Store Versions';

  @override
  String get noVersionsYet => 'No versions yet.';

  @override
  String get versionFallback => 'Version';

  @override
  String get fieldState => 'State';

  @override
  String get fieldRelease => 'Release';

  @override
  String get betaGroups => 'Beta Groups';

  @override
  String get noBetaGroupsYet => 'No beta groups yet.';

  @override
  String get betaGroupFallback => 'Beta Group';

  @override
  String get fieldAllBuilds => 'All builds';

  @override
  String get fieldPublicLink => 'Public link';

  @override
  String get fieldFeedback => 'Feedback';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String appSubtitleWithPlatform(String bundleId, String platform) {
    return '$bundleId · $platform';
  }

  @override
  String comingSoonLabel(String label) {
    return '$label (soon)';
  }

  @override
  String removeAccountConfirmBody(String label) {
    return 'Remove \"$label\"? Its apps, versions, and credentials will be deleted from the app. This cannot be undone.';
  }

  @override
  String appVersionFooter(String version, String build) {
    return 'StackConnect v$version ($build)';
  }

  @override
  String couldNotLoadLicenseDetail(String error) {
    return 'Could not load the license text.\\n$error';
  }

  @override
  String buildNumberLabel(String number) {
    return 'Build $number';
  }

  @override
  String buildVersionLabel(String marketing, String number) {
    return '$marketing ($number)';
  }
}
