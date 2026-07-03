// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appsTitle => 'アプリ';

  @override
  String get refresh => '更新';

  @override
  String get archived => 'アーカイブ済み';

  @override
  String get favoritesSection => 'お気に入り';

  @override
  String get allAppsSection => 'All apps';

  @override
  String get noAppsForAccount => 'このアカウントのアプリが見つかりません。';

  @override
  String get addToFavorites => 'Add to favorites';

  @override
  String get removeFromFavorites => 'Remove from favorites';

  @override
  String get archiveAction => 'アーカイブ';

  @override
  String get addedToFavorites => 'お気に入りに追加しました';

  @override
  String get removedFromFavorites => 'お気に入りから削除しました';

  @override
  String get archivedToast => 'アーカイブ済み';

  @override
  String get unarchivedToast => 'アーカイブを解除しました';

  @override
  String get couldNotUpdateApp => 'Could not update app';

  @override
  String get couldNotLoadApps => 'Could not load apps';

  @override
  String get noArchivedApps => 'No archived apps.';

  @override
  String get unarchiveAction => 'アーカイブ解除';

  @override
  String get appFallbackTitle => 'App';

  @override
  String get appNotFound => 'App not found.';

  @override
  String get favoriteAction => 'お気に入り';

  @override
  String get unfavoriteAction => 'お気に入りから削除';

  @override
  String get fieldName => '名前';

  @override
  String get fieldBundleId => 'Bundle ID';

  @override
  String get fieldPlatform => 'プラットフォーム';

  @override
  String get ratingsAndReviews => '評価とレビュー';

  @override
  String get navHome => 'Home';

  @override
  String get navMobileSection => 'Mobile';

  @override
  String get navAppStoreConnect => 'App Store Connect';

  @override
  String get navDevelopmentSection => '開発';

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
  String get noWidgetsYet => 'ウィジェットはまだありません';

  @override
  String get noWidgetsDescription =>
      'Widgets to keep an eye on your apps will live here.';

  @override
  String get accountsTitle => 'アカウント';

  @override
  String get noAccountsConnected => 'No accounts connected yet.';

  @override
  String get close => '閉じる';

  @override
  String get removeAccountTitle => 'Remove account';

  @override
  String get removeAction => '削除';

  @override
  String get couldNotRemoveAccount => 'Could not remove account';

  @override
  String get couldNotLoadReviews => 'Could not load reviews';

  @override
  String get noReviewsYet => 'No reviews yet.';

  @override
  String get replyAction => '返信';

  @override
  String get editReplyAction => 'Edit reply';

  @override
  String get replyToReviewTitle => 'Reply to review';

  @override
  String get writeYourResponse => 'Write your response…';

  @override
  String get cancel => 'キャンセル';

  @override
  String get submit => '提出';

  @override
  String get replySubmitted => 'Reply submitted';

  @override
  String get replySubmittedToast => 'Reply submitted.';

  @override
  String get replyFailed => 'Reply failed';

  @override
  String get developerResponse => 'Developer response';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsGeneral => '一般';

  @override
  String get settingsAbout => 'About';

  @override
  String get github => 'GitHub';

  @override
  String get license => 'ライセンス';

  @override
  String get settingsDanger => 'Danger';

  @override
  String get deleteAllAccounts => 'すべてのアカウントを削除';

  @override
  String get deleteAllAccountsBody =>
      'これにより、すべてのアカウント、アプリ、バージョン、認証情報がアプリから完全に削除されます。この操作は取り消せません。';

  @override
  String get deleteAll => 'すべて削除';

  @override
  String get couldNotOpenGitHub => 'Could not open GitHub';

  @override
  String get done => '完了';

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
  String get expired => '期限切れ';

  @override
  String get processing => '処理中';

  @override
  String get external => '外部';

  @override
  String get internal => '内部';

  @override
  String get buildFallback => 'ビルド';

  @override
  String get appStoreVersions => 'App Store Versions';

  @override
  String get noVersionsYet => 'No versions yet.';

  @override
  String get versionFallback => 'バージョン';

  @override
  String get fieldState => 'State';

  @override
  String get fieldRelease => 'リリース';

  @override
  String get betaGroups => 'ベータグループ';

  @override
  String get noBetaGroupsYet => 'No beta groups yet.';

  @override
  String get betaGroupFallback => 'Beta Group';

  @override
  String get fieldAllBuilds => 'All builds';

  @override
  String get fieldPublicLink => 'Public link';

  @override
  String get fieldFeedback => 'フィードバック';

  @override
  String get yes => 'はい';

  @override
  String get no => 'いいえ';

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
