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
  String appSubtitleWithPlatform(String bundleId, String platform) {
    return '$bundleId · $platform';
  }
}
