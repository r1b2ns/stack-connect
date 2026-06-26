// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appsTitle => '앱';

  @override
  String get refresh => '새로 고침';

  @override
  String get archived => '보관됨';

  @override
  String get favoritesSection => '즐겨찾기';

  @override
  String get allAppsSection => 'All apps';

  @override
  String get noAppsForAccount => '이 계정에 대한 앱을 찾을 수 없습니다.';

  @override
  String get addToFavorites => 'Add to favorites';

  @override
  String get removeFromFavorites => 'Remove from favorites';

  @override
  String get archiveAction => '보관';

  @override
  String get addedToFavorites => '즐겨찾기에 추가됨';

  @override
  String get removedFromFavorites => '즐겨찾기에서 제거됨';

  @override
  String get archivedToast => '보관됨';

  @override
  String get unarchivedToast => '보관 해제됨';

  @override
  String get couldNotUpdateApp => 'Could not update app';

  @override
  String get couldNotLoadApps => 'Could not load apps';

  @override
  String get noArchivedApps => 'No archived apps.';

  @override
  String get unarchiveAction => '보관 해제';

  @override
  String get appFallbackTitle => 'App';

  @override
  String get appNotFound => 'App not found.';

  @override
  String get favoriteAction => '즐겨찾기';

  @override
  String get unfavoriteAction => '즐겨찾기 해제';

  @override
  String get fieldName => '이름';

  @override
  String get fieldBundleId => 'Bundle ID';

  @override
  String get fieldPlatform => '플랫폼';

  @override
  String get ratingsAndReviews => '평가 및 리뷰';

  @override
  String get navHome => 'Home';

  @override
  String get navMobileSection => 'Mobile';

  @override
  String get navAppStoreConnect => 'App Store Connect';

  @override
  String get navDevelopmentSection => '개발';

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
  String get noWidgetsYet => '아직 위젯이 없습니다';

  @override
  String get noWidgetsDescription =>
      'Widgets to keep an eye on your apps will live here.';

  @override
  String get accountsTitle => '계정';

  @override
  String get noAccountsConnected => 'No accounts connected yet.';

  @override
  String get close => '닫기';

  @override
  String get removeAccountTitle => 'Remove account';

  @override
  String get removeAction => '제거';

  @override
  String get couldNotRemoveAccount => 'Could not remove account';

  @override
  String get couldNotLoadReviews => 'Could not load reviews';

  @override
  String get noReviewsYet => 'No reviews yet.';

  @override
  String get replyAction => '답변';

  @override
  String get editReplyAction => 'Edit reply';

  @override
  String get replyToReviewTitle => 'Reply to review';

  @override
  String get writeYourResponse => 'Write your response…';

  @override
  String get cancel => '취소';

  @override
  String get submit => '제출';

  @override
  String get replySubmitted => 'Reply submitted';

  @override
  String get replySubmittedToast => 'Reply submitted.';

  @override
  String get replyFailed => 'Reply failed';

  @override
  String get developerResponse => 'Developer response';

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsGeneral => '일반';

  @override
  String get settingsAbout => 'About';

  @override
  String get github => 'GitHub';

  @override
  String get license => '라이선스';

  @override
  String get settingsDanger => 'Danger';

  @override
  String get deleteAllAccounts => '모든 계정 삭제';

  @override
  String get deleteAllAccountsBody =>
      '이 작업은 앱에서 모든 계정, 앱, 버전 및 자격 증명을 영구적으로 삭제합니다. 이 작업은 취소할 수 없습니다.';

  @override
  String get deleteAll => '모두 삭제';

  @override
  String get couldNotOpenGitHub => 'Could not open GitHub';

  @override
  String get done => '완료';

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
  String get expired => '만료됨';

  @override
  String get processing => '처리 중';

  @override
  String get external => '외부';

  @override
  String get internal => '내부';

  @override
  String get buildFallback => '빌드';

  @override
  String get appStoreVersions => 'App Store Versions';

  @override
  String get noVersionsYet => 'No versions yet.';

  @override
  String get versionFallback => '버전';

  @override
  String get fieldState => 'State';

  @override
  String get fieldRelease => '출시';

  @override
  String get betaGroups => '베타 그룹';

  @override
  String get noBetaGroupsYet => 'No beta groups yet.';

  @override
  String get betaGroupFallback => 'Beta Group';

  @override
  String get fieldAllBuilds => 'All builds';

  @override
  String get fieldPublicLink => 'Public link';

  @override
  String get fieldFeedback => '피드백';

  @override
  String get yes => '예';

  @override
  String get no => '아니요';

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
