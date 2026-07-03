import 'package:fluent_ui/fluent_ui.dart';
// ConsumerWidget/WidgetRef come from Riverpod, re-exported by stack_core_dart
// (the same source the shell consumes), keeping the dependency surface uniform.
import 'package:stack_core_dart/stack_core_dart.dart';

/// The dedicated Home dashboard detail pane for the desktop master-detail shell.
///
/// This is the desktop counterpart of the iOS `StackConnect/Modules/Home/
/// HomeView.swift` dashboard. On iOS the Home screen is a scrollable dashboard
/// composed of: (1) a sync banner, (2) a pending-agreements banner, (3) an
/// accounts/providers card grid plus a Settings card, and (4) a customizable
/// **widgets** section with an empty state ("No widgets yet" / "Add widgets to
/// keep an eye on your apps right from here.").
///
/// On desktop, "Home" and "App Store Connect" are two SEPARATE pane items that
/// route to two SEPARATE detail views:
///   - "Home" → this [HomeView] (the dashboard).
///   - "App Store Connect" → the accounts landing (`_AccountsEmptyDetail` in
///     `home_shell.dart`), which carries the "Add account" command.
///
/// For now this view only reproduces the dashboard shell plus the empty-widgets
/// placeholder. The remaining iOS sections (accounts grid, sync/agreements
/// banners, and the real widgets) are intentionally deferred.
///
/// It is a [ConsumerWidget] because the upcoming widgets grid will consume
/// Riverpod providers (per-account app/review state) to populate its tiles.
///
/// TODO(home-widgets): Add the customizable widgets grid here, mirroring the
/// iOS `HomeView.swift` widget cards (InReview / AwaitingRelease /
/// RecentReviews). When that lands, this empty placeholder becomes the
/// zero-state shown when no widgets are configured, and a "Add widgets" /
/// "Customize" command moves into the [PageHeader] command bar.
class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typography = FluentTheme.of(context).typography;
    final resources = FluentTheme.of(context).resources;
    final l10n = AppLocalizations.of(context)!;

    return ScaffoldPage(
      header: PageHeader(title: Text(l10n.navHome)),
      content: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.view_dashboard,
              size: 48,
              color: resources.textFillColorSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noWidgetsYet,
              style: typography.subtitle,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.noWidgetsDescription,
              style: typography.body?.copyWith(
                color: resources.textFillColorSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
