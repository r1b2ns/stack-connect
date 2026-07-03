// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appsTitle => 'Apps';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get archived => 'Archiviert';

  @override
  String get favoritesSection => 'Favoriten';

  @override
  String get allAppsSection => 'All apps';

  @override
  String get noAppsForAccount => 'Keine Apps für diesen Account gefunden.';

  @override
  String get addToFavorites => 'Add to favorites';

  @override
  String get removeFromFavorites => 'Remove from favorites';

  @override
  String get archiveAction => 'Archivieren';

  @override
  String get addedToFavorites => 'Zu Favoriten hinzugefügt';

  @override
  String get removedFromFavorites => 'Aus Favoriten entfernt';

  @override
  String get archivedToast => 'Archiviert';

  @override
  String get unarchivedToast => 'Archivierung aufgehoben';

  @override
  String get couldNotUpdateApp => 'Could not update app';

  @override
  String get couldNotLoadApps => 'Could not load apps';

  @override
  String get noArchivedApps => 'No archived apps.';

  @override
  String get unarchiveAction => 'Archivierung aufheben';

  @override
  String get appFallbackTitle => 'App';

  @override
  String get appNotFound => 'App not found.';

  @override
  String get favoriteAction => 'Favorit';

  @override
  String get unfavoriteAction => 'Aus Favoriten entfernen';

  @override
  String get fieldName => 'Name';

  @override
  String get fieldBundleId => 'Bundle ID';

  @override
  String get fieldPlatform => 'Plattform';

  @override
  String get ratingsAndReviews => 'Bewertungen & Rezensionen';

  @override
  String get navHome => 'Home';

  @override
  String get navMobileSection => 'Mobile';

  @override
  String get navAppStoreConnect => 'App Store Connect';

  @override
  String get navDevelopmentSection => 'Entwicklung';

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
  String get noWidgetsYet => 'Noch keine Widgets';

  @override
  String get noWidgetsDescription =>
      'Widgets to keep an eye on your apps will live here.';

  @override
  String get accountsTitle => 'Accounts';

  @override
  String get noAccountsConnected => 'No accounts connected yet.';

  @override
  String get close => 'Schließen';

  @override
  String get removeAccountTitle => 'Remove account';

  @override
  String get removeAction => 'Entfernen';

  @override
  String get couldNotRemoveAccount => 'Could not remove account';

  @override
  String get couldNotLoadReviews => 'Could not load reviews';

  @override
  String get noReviewsYet => 'No reviews yet.';

  @override
  String get replyAction => 'Antworten';

  @override
  String get editReplyAction => 'Edit reply';

  @override
  String get replyToReviewTitle => 'Reply to review';

  @override
  String get writeYourResponse => 'Write your response…';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get submit => 'Einreichen';

  @override
  String get replySubmitted => 'Reply submitted';

  @override
  String get replySubmittedToast => 'Reply submitted.';

  @override
  String get replyFailed => 'Reply failed';

  @override
  String get developerResponse => 'Developer response';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsGeneral => 'Allgemein';

  @override
  String get settingsAbout => 'About';

  @override
  String get github => 'GitHub';

  @override
  String get license => 'Lizenz';

  @override
  String get settingsDanger => 'Danger';

  @override
  String get deleteAllAccounts => 'Alle Konten löschen';

  @override
  String get deleteAllAccountsBody =>
      'Dadurch werden alle Konten, Apps, Versionen und Anmeldedaten dauerhaft aus der App gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get deleteAll => 'Alle löschen';

  @override
  String get couldNotOpenGitHub => 'Could not open GitHub';

  @override
  String get done => 'Fertig';

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
  String get expired => 'Abgelaufen';

  @override
  String get processing => 'Wird verarbeitet';

  @override
  String get external => 'Extern';

  @override
  String get internal => 'Intern';

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
  String get fieldRelease => 'Freigeben';

  @override
  String get betaGroups => 'Beta-Gruppen';

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
  String get yes => 'Ja';

  @override
  String get no => 'Nein';

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
