import 'package:stack_core_dart/stack_core_dart.dart';

/// Whether the desktop navigation rail is expanded (full width, labels) or
/// collapsed (icons-only compact rail).
///
/// Drives [NavigationPane.displayMode] in the shell so the custom top-bar
/// sidebar toggle can flip the rail explicitly. Defaults to `true` (expanded),
/// so the rail starts full width with labels on launch. A [StateProvider] keeps
/// this in line with the app's Riverpod usage and lets the title-bar button and
/// the pane read/write the same source of truth.
final paneExpandedProvider = StateProvider<bool>((ref) => true);

/// What the desktop detail pane is currently showing.
///
/// [home] renders the dedicated Home dashboard (the desktop counterpart of the
/// iOS `HomeView.swift`); [none] renders the App Store Connect accounts landing.
/// These two are intentionally distinct so the "Home" and "App Store Connect"
/// pane items diverge into separate detail views.
enum DetailView { home, none, apps, archivedApps, appDetail, reviews }

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

  /// Returns the Home dashboard landing (no account scope).
  DesktopSelection showHome() => const DesktopSelection(view: DetailView.home);

  DesktopSelection showApps(String accountId) =>
      DesktopSelection(view: DetailView.apps, accountId: accountId);

  /// Returns the archived-apps list for the currently scoped account.
  DesktopSelection showArchivedApps() => DesktopSelection(
        view: DetailView.archivedApps,
        accountId: accountId,
      );

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
  DesktopSelection build() => const DesktopSelection(view: DetailView.home);

  /// Routes the detail pane to the dedicated Home dashboard.
  void showHome() => state = const DesktopSelection(view: DetailView.home);

  void selectAccountApps(String accountId) =>
      state = state.showApps(accountId);

  void openAppDetail(String appId) => state = state.showAppDetail(appId);

  /// Routes the detail pane to the archived-apps list for the scoped account.
  void openArchivedApps() => state = state.showArchivedApps();

  void openReviews() => state = state.showReviews();

  void backToApps() {
    final accountId = state.accountId;
    if (accountId != null) state = state.showApps(accountId);
  }

  /// Returns to the App Store Connect accounts landing ([DetailView.none] with
  /// no account selected). This is distinct from [showHome]: "Home" routes to
  /// the dashboard, "App Store Connect" clears to this accounts landing.
  void clear() => state = const DesktopSelection(view: DetailView.none);
}

/// The desktop selection controller the shell and panes consume.
final selectionControllerProvider =
    NotifierProvider<SelectionController, DesktopSelection>(
  SelectionController.new,
);
