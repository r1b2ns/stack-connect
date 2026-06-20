import 'package:stack_core_dart/stack_core_dart.dart';

/// What the desktop detail pane is currently showing.
enum DetailView { none, addAccount, apps, appDetail, reviews }

/// Immutable selection driving the desktop master-detail layout.
///
/// The left (master) pane selects an account; the right (detail) pane renders
/// according to [view], scoped to [accountId]/[appId]. This is a plain value
/// object so equality drives Riverpod rebuilds.
class DesktopSelection {
  const DesktopSelection({
    this.view = DetailView.none,
    this.accountId,
    this.appId,
  });

  final DetailView view;
  final String? accountId;
  final String? appId;

  DesktopSelection showApps(String accountId) =>
      DesktopSelection(view: DetailView.apps, accountId: accountId);

  DesktopSelection showAppDetail(String appId) => DesktopSelection(
        view: DetailView.appDetail,
        accountId: accountId,
        appId: appId,
      );

  DesktopSelection showReviews() => DesktopSelection(
        view: DetailView.reviews,
        accountId: accountId,
        appId: appId,
      );

  DesktopSelection get addAccount =>
      const DesktopSelection(view: DetailView.addAccount);

  @override
  int get hashCode => Object.hash(view, accountId, appId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopSelection &&
          runtimeType == other.runtimeType &&
          view == other.view &&
          accountId == other.accountId &&
          appId == other.appId;
}

/// Holds the desktop master-detail selection.
class SelectionController extends Notifier<DesktopSelection> {
  @override
  DesktopSelection build() => const DesktopSelection();

  void selectAccountApps(String accountId) =>
      state = state.showApps(accountId);

  void openAddAccount() => state = state.addAccount;

  void openAppDetail(String appId) => state = state.showAppDetail(appId);

  void openReviews() => state = state.showReviews();

  void backToApps() {
    final accountId = state.accountId;
    if (accountId != null) state = state.showApps(accountId);
  }

  void clear() => state = const DesktopSelection();
}

/// The desktop selection controller the shell and panes consume.
final selectionControllerProvider =
    NotifierProvider<SelectionController, DesktopSelection>(
  SelectionController.new,
);
