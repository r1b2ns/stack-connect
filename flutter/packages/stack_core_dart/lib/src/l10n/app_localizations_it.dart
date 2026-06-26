// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appsTitle => 'App';

  @override
  String get refresh => 'Aggiorna';

  @override
  String get archived => 'Archiviata';

  @override
  String get favoritesSection => 'Preferiti';

  @override
  String get allAppsSection => 'All apps';

  @override
  String get noAppsForAccount => 'Nessuna app trovata per questo account.';

  @override
  String get addToFavorites => 'Add to favorites';

  @override
  String get removeFromFavorites => 'Remove from favorites';

  @override
  String get archiveAction => 'Archivia';

  @override
  String get addedToFavorites => 'Aggiunto ai preferiti';

  @override
  String get removedFromFavorites => 'Rimosso dai preferiti';

  @override
  String get archivedToast => 'Archiviata';

  @override
  String get unarchivedToast => 'Archiviazione annullata';

  @override
  String get couldNotUpdateApp => 'Could not update app';

  @override
  String get couldNotLoadApps => 'Could not load apps';

  @override
  String get noArchivedApps => 'No archived apps.';

  @override
  String get unarchiveAction => 'Annulla archiviazione';

  @override
  String get appFallbackTitle => 'App';

  @override
  String get appNotFound => 'App not found.';

  @override
  String get favoriteAction => 'Preferito';

  @override
  String get unfavoriteAction => 'Rimuovi dai preferiti';

  @override
  String get fieldName => 'Nome';

  @override
  String get fieldBundleId => 'Bundle ID';

  @override
  String get fieldPlatform => 'Piattaforma';

  @override
  String get ratingsAndReviews => 'Valutazioni e recensioni';

  @override
  String get navHome => 'Home';

  @override
  String get navMobileSection => 'Mobile';

  @override
  String get navAppStoreConnect => 'App Store Connect';

  @override
  String get navDevelopmentSection => 'Sviluppo';

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
  String get noWidgetsYet => 'Ancora nessun widget';

  @override
  String get noWidgetsDescription =>
      'Widgets to keep an eye on your apps will live here.';

  @override
  String get accountsTitle => 'Account';

  @override
  String get noAccountsConnected => 'No accounts connected yet.';

  @override
  String get close => 'Chiudi';

  @override
  String get removeAccountTitle => 'Remove account';

  @override
  String get removeAction => 'Rimuovi';

  @override
  String get couldNotRemoveAccount => 'Could not remove account';

  @override
  String get couldNotLoadReviews => 'Could not load reviews';

  @override
  String get noReviewsYet => 'No reviews yet.';

  @override
  String get replyAction => 'Rispondi';

  @override
  String get editReplyAction => 'Edit reply';

  @override
  String get replyToReviewTitle => 'Reply to review';

  @override
  String get writeYourResponse => 'Write your response…';

  @override
  String get cancel => 'Annulla';

  @override
  String get submit => 'Invia';

  @override
  String get replySubmitted => 'Reply submitted';

  @override
  String get replySubmittedToast => 'Reply submitted.';

  @override
  String get replyFailed => 'Reply failed';

  @override
  String get developerResponse => 'Developer response';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get settingsGeneral => 'Generale';

  @override
  String get settingsAbout => 'About';

  @override
  String get github => 'GitHub';

  @override
  String get license => 'Licenza';

  @override
  String get settingsDanger => 'Danger';

  @override
  String get deleteAllAccounts => 'Elimina tutti gli account';

  @override
  String get deleteAllAccountsBody =>
      'Questa operazione eliminerà definitivamente tutti gli account, le app, le versioni e le credenziali dall\'app. L\'azione non può essere annullata.';

  @override
  String get deleteAll => 'Elimina tutto';

  @override
  String get couldNotOpenGitHub => 'Could not open GitHub';

  @override
  String get done => 'Fine';

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
  String get expired => 'Scaduto';

  @override
  String get processing => 'In elaborazione';

  @override
  String get external => 'Esterno';

  @override
  String get internal => 'Interno';

  @override
  String get buildFallback => 'Build';

  @override
  String get appStoreVersions => 'App Store Versions';

  @override
  String get noVersionsYet => 'No versions yet.';

  @override
  String get versionFallback => 'Versione';

  @override
  String get fieldState => 'State';

  @override
  String get fieldRelease => 'Pubblica';

  @override
  String get betaGroups => 'Gruppi beta';

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
  String get yes => 'Sì';

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
