import 'package:fluent_ui/fluent_ui.dart';
// fluent_ui re-exports Material but hides `Icons`, so import it directly for the
// Material `view_sidebar` glyph used by the sidebar toggle.
import 'package:flutter/material.dart' show Icons;
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/service_kind_label.dart';
import '../../core/stack_error_message.dart';
import '../accounts/add_account_pane.dart' show showAddAccountDialog;
import '../apps/app_detail_pane.dart';
import '../apps/apps_pane.dart';
import '../reviews/reviews_pane.dart';
import '../settings/settings_dialog.dart';
import 'selection.dart';

/// Desktop master-detail shell.
///
/// The left [NavigationPane] is the master: connected accounts (each a
/// `PaneItem`) plus an "Add account" footer command (a [PaneItemAction] that
/// opens a modal rather than navigating). Selecting an account drives the
/// [selectionControllerProvider]; the right detail pane renders apps → app
/// detail → reviews for that selection. This is deliberately a multi-pane Fluent
/// layout, distinct from the mobile single-stack navigation.
///
/// The [NavigationView.titleBar] hosts an in-app top bar: a custom sidebar
/// toggle on the far left followed by the "Stack Connect" app name. The toggle
/// flips [paneExpandedProvider], which drives [NavigationPane.displayMode]
/// between `expanded` (full width with labels) and `compact` (icons-only rail).
/// The pane's built-in toggle is suppressed (`toggleButton: null`) so only this
/// single custom toggle is ever shown.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsControllerProvider);
    final selection = ref.watch(selectionControllerProvider);
    final selectionCtrl = ref.read(selectionControllerProvider.notifier);
    final isExpanded = ref.watch(paneExpandedProvider);

    final records = accounts.valueOrNull ?? const <AccountRecord>[];
    final selectedIndex = _selectedPaneIndex(records, selection);

    return NavigationView(
      titleBar: _ShellTitleBar(isExpanded: isExpanded),
      pane: NavigationPane(
        // fluent_ui asserts a non-null `selected` whenever any item renders its
        // body, so index 0 is a synthetic "Home" item that always exists; the
        // accounts occupy indices 1..N below it.
        selected: selectedIndex,
        // The rail layout is driven explicitly by [paneExpandedProvider]:
        // `expanded` shows the full-width rail with labels, `compact` collapses
        // it to an icons-only rail (labels surface as tooltips on hover). The
        // custom top-bar toggle is the sole control flipping this state, so we
        // bind `displayMode` directly to it rather than relying on fluent_ui's
        // internal compact-overlay open state. This only affects layout; the
        // `selected` indexing into `effectiveItems` documented in
        // [_selectedPaneIndex] is unchanged.
        displayMode:
            isExpanded ? PaneDisplayMode.expanded : PaneDisplayMode.compact,
        // Suppress fluent_ui's built-in `PaneToggleButton` (☰): the title bar
        // provides the single custom sidebar toggle instead, so a null here
        // guarantees there is never a second, duplicate toggle in the pane.
        toggleButton: null,
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.home),
            title: const Text('Home'),
            body: _DetailPane(selection: selection),
            onTap: selectionCtrl.clear,
          ),
          PaneItemHeader(header: const Text('Accounts')),
          for (final record in records)
            PaneItem(
              icon: const Icon(FluentIcons.cloud),
              title: Text(record.label),
              body: _DetailPane(selection: selection),
              onTap: () => selectionCtrl.selectAccountApps(record.id),
            ),
        ],
        footerItems: [
          PaneItemSeparator(),
          // A [PaneItemAction] — a tappable footer command that opens the
          // "Add account" modal. Unlike [PaneItem] it has no navigable body and
          // is excluded from fluent_ui's `effectiveItems`, so it never becomes a
          // selectable destination nor occupies a `selected` index (see
          // [_selectedPaneIndex]).
          PaneItemAction(
            icon: const Icon(FluentIcons.add),
            title: const Text('Add account'),
            onTap: () => showAddAccountDialog(context),
          ),
        ],
      ),
    );
  }

  /// Maps the current [selection] to the selected pane index so the master pane
  /// highlight tracks the detail view.
  ///
  /// `NavigationPane.selected` indexes into fluent_ui's `effectiveItems`, which
  /// keeps only navigable [PaneItem]s and EXCLUDES [PaneItemHeader],
  /// [PaneItemSeparator], and [PaneItemAction]. So the effective order is just
  /// Home(0) then accounts(1..N) — the "Accounts" header, the footer separator,
  /// and the footer "Add account" action do not occupy an index. As a result
  /// this only ever returns Home(0) or an account index (1..N), never the
  /// footer command.
  int _selectedPaneIndex(
    List<AccountRecord> records,
    DesktopSelection selection,
  ) {
    const homeIndex = 0;

    final accountId = selection.accountId;
    if (accountId == null) return homeIndex;
    final pos = records.indexWhere((r) => r.id == accountId);
    // Home occupies index 0, so the account at list position `pos` is `pos + 1`.
    return pos < 0 ? homeIndex : pos + 1;
  }
}

/// In-app top bar rendered as the [NavigationView.titleBar].
///
/// Lays out, left to right: the sidebar toggle button, the "Stack Connect" app
/// name, a flexible spacer, then a settings gear on the far right. The toggle
/// flips [paneExpandedProvider]; its glyph swaps between an "open" and "close"
/// sidebar icon to reflect the current rail state. This is the only sidebar
/// toggle in the shell — the pane's built-in one is suppressed. The gear opens
/// the Settings modal (see [showSettingsDialog]).
class _ShellTitleBar extends ConsumerWidget {
  const _ShellTitleBar({required this.isExpanded});

  /// Whether the navigation rail is currently expanded. Provided by the parent
  /// so the bar and the pane share one rebuild-driving value.
  final bool isExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          const SizedBox(width: 4),
          Tooltip(
            message: isExpanded ? 'Collapse sidebar' : 'Expand sidebar',
            child: IconButton(
              icon: Icon(
                // Material `view_sidebar` glyph: a rounded rectangle with a
                // vertical divider carving out a narrow left column — the
                // standard VS Code / macOS show-hide sidebar icon. fluent_ui's
                // own glyphs (`FluentIcons.side_panel`, `open_pane`, …) are
                // Segoe MDL2 marks that don't read as a left-column sidebar, so
                // Material is the closer match. `IconButton` accepts any
                // `IconData`, so a Material glyph drops in cleanly.
                isExpanded
                    ? Icons.view_sidebar_outlined
                    : Icons.view_sidebar,
                size: 18,
              ),
              onPressed: () {
                ref.read(paneExpandedProvider.notifier).state = !isExpanded;
              },
            ),
          ),
          const SizedBox(width: 8),
          const Text('Stack Connect'),
          const Spacer(),
          Tooltip(
            message: 'Settings',
            child: IconButton(
              icon: const Icon(FluentIcons.settings, size: 18),
              onPressed: () => showSettingsDialog(context),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// The right-hand detail pane: renders according to the selection.
class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.selection});

  final DesktopSelection selection;

  @override
  Widget build(BuildContext context) {
    switch (selection.view) {
      case DetailView.none:
        return const _AccountsEmptyDetail();
      case DetailView.apps:
        return AppsPane(accountId: selection.accountId!);
      case DetailView.appDetail:
        return AppDetailPane(
          accountId: selection.accountId!,
          appId: selection.appId!,
        );
      case DetailView.reviews:
        return ReviewsPane(
          accountId: selection.accountId!,
          appId: selection.appId!,
        );
    }
  }
}

/// Detail placeholder shown before any account is selected. Also surfaces the
/// accounts controller's loading/error states (the master pane itself cannot).
class _AccountsEmptyDetail extends ConsumerWidget {
  const _AccountsEmptyDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsControllerProvider);

    return ScaffoldPage(
      content: accounts.when(
        loading: () => const Center(child: ProgressRing()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: InfoBar(
              title: const Text('Could not load accounts'),
              content: Text(stackErrorMessage(error)),
              severity: InfoBarSeverity.error,
            ),
          ),
        ),
        data: (records) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(FluentIcons.cloud_add, size: 48),
              const SizedBox(height: 12),
              Text(
                records.isEmpty
                    ? 'No accounts yet. Use "Add account" to connect one.'
                    : 'Select an account to view its apps.',
              ),
              if (records.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${records.length} account(s): '
                  '${records.map((r) => r.kind.label).toSet().join(', ')}',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
