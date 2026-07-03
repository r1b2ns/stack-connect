import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('nl'),
    Locale('pt'),
  ];

  /// No description provided for @appsTitle.
  ///
  /// In en, this message translates to:
  /// **'Apps'**
  String get appsTitle;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @archived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archived;

  /// No description provided for @favoritesSection.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesSection;

  /// No description provided for @allAppsSection.
  ///
  /// In en, this message translates to:
  /// **'All apps'**
  String get allAppsSection;

  /// No description provided for @noAppsForAccount.
  ///
  /// In en, this message translates to:
  /// **'No apps found for this account.'**
  String get noAppsForAccount;

  /// No description provided for @addToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get addToFavorites;

  /// No description provided for @removeFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get removeFromFavorites;

  /// No description provided for @archiveAction.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archiveAction;

  /// No description provided for @addedToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get addedToFavorites;

  /// No description provided for @removedFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get removedFromFavorites;

  /// Success toast shown after archiving an app.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archivedToast;

  /// No description provided for @unarchivedToast.
  ///
  /// In en, this message translates to:
  /// **'Unarchived'**
  String get unarchivedToast;

  /// No description provided for @couldNotUpdateApp.
  ///
  /// In en, this message translates to:
  /// **'Could not update app'**
  String get couldNotUpdateApp;

  /// No description provided for @couldNotLoadApps.
  ///
  /// In en, this message translates to:
  /// **'Could not load apps'**
  String get couldNotLoadApps;

  /// No description provided for @noArchivedApps.
  ///
  /// In en, this message translates to:
  /// **'No archived apps.'**
  String get noArchivedApps;

  /// No description provided for @unarchiveAction.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get unarchiveAction;

  /// No description provided for @appFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get appFallbackTitle;

  /// No description provided for @appNotFound.
  ///
  /// In en, this message translates to:
  /// **'App not found.'**
  String get appNotFound;

  /// No description provided for @favoriteAction.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favoriteAction;

  /// No description provided for @unfavoriteAction.
  ///
  /// In en, this message translates to:
  /// **'Unfavorite'**
  String get unfavoriteAction;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fieldName;

  /// No description provided for @fieldBundleId.
  ///
  /// In en, this message translates to:
  /// **'Bundle ID'**
  String get fieldBundleId;

  /// No description provided for @fieldPlatform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get fieldPlatform;

  /// No description provided for @ratingsAndReviews.
  ///
  /// In en, this message translates to:
  /// **'Ratings & Reviews'**
  String get ratingsAndReviews;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navMobileSection.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get navMobileSection;

  /// No description provided for @navAppStoreConnect.
  ///
  /// In en, this message translates to:
  /// **'App Store Connect'**
  String get navAppStoreConnect;

  /// No description provided for @navDevelopmentSection.
  ///
  /// In en, this message translates to:
  /// **'Development'**
  String get navDevelopmentSection;

  /// No description provided for @soonTag.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get soonTag;

  /// No description provided for @collapseSidebar.
  ///
  /// In en, this message translates to:
  /// **'Collapse sidebar'**
  String get collapseSidebar;

  /// No description provided for @expandSidebar.
  ///
  /// In en, this message translates to:
  /// **'Expand sidebar'**
  String get expandSidebar;

  /// No description provided for @addAccount.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get addAccount;

  /// No description provided for @noAccountsYetDesktop.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet. Use \"Add account\" above to connect one.'**
  String get noAccountsYetDesktop;

  /// No description provided for @couldNotLoadAccounts.
  ///
  /// In en, this message translates to:
  /// **'Could not load accounts'**
  String get couldNotLoadAccounts;

  /// No description provided for @noWidgetsYet.
  ///
  /// In en, this message translates to:
  /// **'No widgets yet'**
  String get noWidgetsYet;

  /// No description provided for @noWidgetsDescription.
  ///
  /// In en, this message translates to:
  /// **'Widgets to keep an eye on your apps will live here.'**
  String get noWidgetsDescription;

  /// No description provided for @accountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accountsTitle;

  /// No description provided for @noAccountsConnected.
  ///
  /// In en, this message translates to:
  /// **'No accounts connected yet.'**
  String get noAccountsConnected;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @removeAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove account'**
  String get removeAccountTitle;

  /// No description provided for @removeAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeAction;

  /// No description provided for @couldNotRemoveAccount.
  ///
  /// In en, this message translates to:
  /// **'Could not remove account'**
  String get couldNotRemoveAccount;

  /// No description provided for @couldNotLoadReviews.
  ///
  /// In en, this message translates to:
  /// **'Could not load reviews'**
  String get couldNotLoadReviews;

  /// No description provided for @noReviewsYet.
  ///
  /// In en, this message translates to:
  /// **'No reviews yet.'**
  String get noReviewsYet;

  /// No description provided for @replyAction.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get replyAction;

  /// No description provided for @editReplyAction.
  ///
  /// In en, this message translates to:
  /// **'Edit reply'**
  String get editReplyAction;

  /// No description provided for @replyToReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Reply to review'**
  String get replyToReviewTitle;

  /// No description provided for @writeYourResponse.
  ///
  /// In en, this message translates to:
  /// **'Write your response…'**
  String get writeYourResponse;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @replySubmitted.
  ///
  /// In en, this message translates to:
  /// **'Reply submitted'**
  String get replySubmitted;

  /// No description provided for @replySubmittedToast.
  ///
  /// In en, this message translates to:
  /// **'Reply submitted.'**
  String get replySubmittedToast;

  /// No description provided for @replyFailed.
  ///
  /// In en, this message translates to:
  /// **'Reply failed'**
  String get replyFailed;

  /// No description provided for @developerResponse.
  ///
  /// In en, this message translates to:
  /// **'Developer response'**
  String get developerResponse;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneral;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @github.
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get github;

  /// No description provided for @license.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get license;

  /// No description provided for @settingsDanger.
  ///
  /// In en, this message translates to:
  /// **'Danger'**
  String get settingsDanger;

  /// No description provided for @deleteAllAccounts.
  ///
  /// In en, this message translates to:
  /// **'Delete All Accounts'**
  String get deleteAllAccounts;

  /// No description provided for @deleteAllAccountsBody.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete all accounts, apps, versions, and credentials from the app. This action cannot be undone.'**
  String get deleteAllAccountsBody;

  /// No description provided for @deleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete All'**
  String get deleteAll;

  /// No description provided for @couldNotOpenGitHub.
  ///
  /// In en, this message translates to:
  /// **'Could not open GitHub'**
  String get couldNotOpenGitHub;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'StackConnect'**
  String get appName;

  /// No description provided for @couldNotLoadLicense.
  ///
  /// In en, this message translates to:
  /// **'Could not load the license text.'**
  String get couldNotLoadLicense;

  /// No description provided for @settingsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Settings coming soon'**
  String get settingsComingSoon;

  /// No description provided for @noAccountsYet.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet'**
  String get noAccountsYet;

  /// No description provided for @connectAccountToStart.
  ///
  /// In en, this message translates to:
  /// **'Connect an App Store Connect account to get started.'**
  String get connectAccountToStart;

  /// No description provided for @testFlightBuilds.
  ///
  /// In en, this message translates to:
  /// **'TestFlight Builds'**
  String get testFlightBuilds;

  /// No description provided for @noBuildsYet.
  ///
  /// In en, this message translates to:
  /// **'No builds yet.'**
  String get noBuildsYet;

  /// No description provided for @expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expired;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get processing;

  /// No description provided for @external.
  ///
  /// In en, this message translates to:
  /// **'External'**
  String get external;

  /// No description provided for @internal.
  ///
  /// In en, this message translates to:
  /// **'Internal'**
  String get internal;

  /// No description provided for @buildFallback.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get buildFallback;

  /// No description provided for @appStoreVersions.
  ///
  /// In en, this message translates to:
  /// **'App Store Versions'**
  String get appStoreVersions;

  /// No description provided for @noVersionsYet.
  ///
  /// In en, this message translates to:
  /// **'No versions yet.'**
  String get noVersionsYet;

  /// No description provided for @versionFallback.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get versionFallback;

  /// No description provided for @fieldState.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get fieldState;

  /// No description provided for @fieldRelease.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get fieldRelease;

  /// No description provided for @betaGroups.
  ///
  /// In en, this message translates to:
  /// **'Beta Groups'**
  String get betaGroups;

  /// No description provided for @noBetaGroupsYet.
  ///
  /// In en, this message translates to:
  /// **'No beta groups yet.'**
  String get noBetaGroupsYet;

  /// No description provided for @betaGroupFallback.
  ///
  /// In en, this message translates to:
  /// **'Beta Group'**
  String get betaGroupFallback;

  /// No description provided for @fieldAllBuilds.
  ///
  /// In en, this message translates to:
  /// **'All builds'**
  String get fieldAllBuilds;

  /// No description provided for @fieldPublicLink.
  ///
  /// In en, this message translates to:
  /// **'Public link'**
  String get fieldPublicLink;

  /// No description provided for @fieldFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get fieldFeedback;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// App row subtitle combining bundle id and platform.
  ///
  /// In en, this message translates to:
  /// **'{bundleId} · {platform}'**
  String appSubtitleWithPlatform(String bundleId, String platform);

  /// Title for a coming-soon navigation item.
  ///
  /// In en, this message translates to:
  /// **'{label} (soon)'**
  String comingSoonLabel(String label);

  /// Confirmation body shown before removing a single account.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{label}\"? Its apps, versions, and credentials will be deleted from the app. This cannot be undone.'**
  String removeAccountConfirmBody(String label);

  /// Settings footer showing the app version and build.
  ///
  /// In en, this message translates to:
  /// **'StackConnect v{version} ({build})'**
  String appVersionFooter(String version, String build);

  /// License dialog error with the underlying error appended.
  ///
  /// In en, this message translates to:
  /// **'Could not load the license text.\\n{error}'**
  String couldNotLoadLicenseDetail(String error);

  /// Build title using only the build number.
  ///
  /// In en, this message translates to:
  /// **'Build {number}'**
  String buildNumberLabel(String number);

  /// Build title combining marketing version and build number.
  ///
  /// In en, this message translates to:
  /// **'{marketing} ({number})'**
  String buildVersionLabel(String marketing, String number);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'it',
    'ja',
    'ko',
    'nl',
    'pt',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'nl':
      return AppLocalizationsNl();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
