// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appsTitle => 'Apps';

  @override
  String get refresh => 'Actualiser';

  @override
  String get archived => 'Archivé';

  @override
  String get favoritesSection => 'Favoris';

  @override
  String get allAppsSection => 'All apps';

  @override
  String get noAppsForAccount => 'Aucune app trouvée pour ce compte.';

  @override
  String get addToFavorites => 'Add to favorites';

  @override
  String get removeFromFavorites => 'Remove from favorites';

  @override
  String get archiveAction => 'Archiver';

  @override
  String get addedToFavorites => 'Ajouté aux favoris';

  @override
  String get removedFromFavorites => 'Retiré des favoris';

  @override
  String get archivedToast => 'Archivé';

  @override
  String get unarchivedToast => 'Désarchivée';

  @override
  String get couldNotUpdateApp => 'Could not update app';

  @override
  String get couldNotLoadApps => 'Could not load apps';

  @override
  String get noArchivedApps => 'No archived apps.';

  @override
  String get unarchiveAction => 'Désarchiver';

  @override
  String get appFallbackTitle => 'App';

  @override
  String get appNotFound => 'App not found.';

  @override
  String get favoriteAction => 'Favori';

  @override
  String get unfavoriteAction => 'Retirer des favoris';

  @override
  String get fieldName => 'Nom';

  @override
  String get fieldBundleId => 'Bundle ID';

  @override
  String get fieldPlatform => 'Plateforme';

  @override
  String get ratingsAndReviews => 'Notes et avis';

  @override
  String get navHome => 'Home';

  @override
  String get navMobileSection => 'Mobile';

  @override
  String get navAppStoreConnect => 'App Store Connect';

  @override
  String get navDevelopmentSection => 'Développement';

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
  String get noWidgetsYet => 'Aucun widget pour le moment';

  @override
  String get noWidgetsDescription =>
      'Widgets to keep an eye on your apps will live here.';

  @override
  String get accountsTitle => 'Comptes';

  @override
  String get noAccountsConnected => 'No accounts connected yet.';

  @override
  String get close => 'Fermer';

  @override
  String get removeAccountTitle => 'Remove account';

  @override
  String get removeAction => 'Supprimer';

  @override
  String get couldNotRemoveAccount => 'Could not remove account';

  @override
  String get couldNotLoadReviews => 'Could not load reviews';

  @override
  String get noReviewsYet => 'No reviews yet.';

  @override
  String get replyAction => 'Répondre';

  @override
  String get editReplyAction => 'Edit reply';

  @override
  String get replyToReviewTitle => 'Reply to review';

  @override
  String get writeYourResponse => 'Write your response…';

  @override
  String get cancel => 'Annuler';

  @override
  String get submit => 'Soumettre';

  @override
  String get replySubmitted => 'Reply submitted';

  @override
  String get replySubmittedToast => 'Reply submitted.';

  @override
  String get replyFailed => 'Reply failed';

  @override
  String get developerResponse => 'Developer response';

  @override
  String get settingsTitle => 'Réglages';

  @override
  String get settingsGeneral => 'Général';

  @override
  String get settingsAbout => 'About';

  @override
  String get github => 'GitHub';

  @override
  String get license => 'Licence';

  @override
  String get settingsDanger => 'Danger';

  @override
  String get deleteAllAccounts => 'Supprimer tous les comptes';

  @override
  String get deleteAllAccountsBody =>
      'Cela supprimera définitivement tous les comptes, apps, versions et identifiants de l\'app. Cette action est irréversible.';

  @override
  String get deleteAll => 'Tout supprimer';

  @override
  String get couldNotOpenGitHub => 'Could not open GitHub';

  @override
  String get done => 'OK';

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
  String get expired => 'Expiré';

  @override
  String get processing => 'Traitement en cours';

  @override
  String get external => 'Externe';

  @override
  String get internal => 'Interne';

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
  String get fieldRelease => 'Publier';

  @override
  String get betaGroups => 'Groupes bêta';

  @override
  String get noBetaGroupsYet => 'No beta groups yet.';

  @override
  String get betaGroupFallback => 'Beta Group';

  @override
  String get fieldAllBuilds => 'All builds';

  @override
  String get fieldPublicLink => 'Public link';

  @override
  String get fieldFeedback => 'Retours';

  @override
  String get yes => 'Oui';

  @override
  String get no => 'Non';

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
