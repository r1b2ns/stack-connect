import 'package:fluent_ui/fluent_ui.dart';
// fluent_ui re-exports Material but hides `Icons`, so import it directly for the
// Material `view_sidebar` glyph used by the sidebar toggle.
import 'package:flutter/material.dart' show Icons;
// Brand logo glyphs (Apple, Google Play, Firebase, GitHub) for the grouped
// "Mobile"/"Development" navigation sections. FluentIcons/Material ship none of
// these, so `simple_icons` supplies them as `IconData` usable in `Icon(...)`.
import 'package:simple_icons/simple_icons.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/service_kind_label.dart';
import '../../core/stack_error_message.dart';
import '../accounts/add_account_pane.dart' show showAddAccountDialog;
import '../apps/app_detail_pane.dart';
import '../apps/apps_pane.dart';
import '../home/home_view.dart';
import '../reviews/reviews_pane.dart';
import '../settings/settings_dialog.dart';
import 'selection.dart';

/// Desktop master-detail shell.
///
/// The left [NavigationPane] is the master. Top to bottom it renders:
///   1. "Home" — the landing item (effective index 0). It renders a dedicated
///      Home dashboard ([HomeView]), distinct from the accounts landing.
///   2. A "Mobile" section header followed by three brand destinations:
///      "App Store Connect" (enabled, effective index 1) and the
///      coming-soon "Play Store" and "Firebase" entries. "App Store Connect"
///      renders the accounts landing ([_AccountsEmptyDetail]).
///   3. A "Development" section header with the coming-soon "Github" entry.
///   4. An "Accounts" header followed by the connected accounts (each a
///      navigable `PaneItem`, effective indices 2..N+1).
///
/// The coming-soon entries (Play Store, Firebase, Github) are rendered as
/// dimmed, non-interactive [PaneItemAction]s. [PaneItemAction] is excluded from
/// fluent_ui's `effectiveItems`, so these placeholders never occupy a `selected`
/// index — keeping the selection math in [_selectedPaneIndex] tied solely to the
/// navigable items (Home, App Store Connect, and the accounts).
///
/// There is no pane footer: the "Add account" command lives in the accounts
/// detail view's [PageHeader] as a [CommandBar] button (see
/// [_AccountsEmptyDetail]), not in the navigation rail.
///
/// Selecting an account drives the [selectionControllerProvider]; the right
/// detail pane renders apps → app detail → reviews for that selection. This is
/// deliberately a multi-pane Fluent layout, distinct from the mobile
/// single-stack navigation.
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
        // body, so index 0 is a synthetic "Home" item that always exists.
        // "App Store Connect" is the next navigable item (index 1) and the
        // accounts occupy indices 2..N+1 below it. The section headers and the
        // coming-soon [PaneItemAction]s carry no index (see [_selectedPaneIndex]).
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
            // Routes the detail pane to the dedicated Home dashboard
            // ([HomeView]) — distinct from "App Store Connect", which clears to
            // the accounts landing.
            onTap: selectionCtrl.showHome,
          ),
          // --- Mobile section -------------------------------------------------
          // A non-navigable header; excluded from `effectiveItems`.
          PaneItemHeader(header: const Text('Mobile')),
          // The only enabled new destination. It is a navigable [PaneItem] with
          // a body, so it counts toward `effectiveItems` (effective index 1).
          // Tapping it clears the account selection ([DetailView.none]), which
          // routes the detail pane to the accounts landing
          // (`_AccountsEmptyDetail`). This is the distinct counterpart to Home,
          // which routes to the [HomeView] dashboard.
          PaneItem(
            icon: const Icon(SimpleIcons.apple),
            title: const Text('App Store Connect'),
            body: _DetailPane(selection: selection),
            onTap: selectionCtrl.clear,
          ),
          // Coming-soon placeholders. Rendered as [PaneItemAction] (NOT
          // [PaneItem]) precisely because actions are excluded from
          // `effectiveItems` — so they never take a `selected` index and keep
          // [_selectedPaneIndex] math intact. Styled via [_comingSoonItem] to
          // read as dimmed and inert (no-op tap, "Coming soon" tooltip).
          _comingSoonItem(
            icon: SimpleIcons.googleplay,
            label: 'Play Store',
          ),
          _comingSoonItem(
            icon: SimpleIcons.firebase,
            label: 'Firebase',
          ),
          // --- Development section --------------------------------------------
          PaneItemHeader(header: const Text('Development')),
          _comingSoonItem(
            icon: SimpleIcons.github,
            label: 'Github',
          ),
          // --- Accounts section -----------------------------------------------
          PaneItemHeader(header: const Text('Accounts')),
          for (final record in records)
            PaneItem(
              icon: const Icon(FluentIcons.cloud),
              title: Text(record.label),
              body: _DetailPane(selection: selection),
              onTap: () => selectionCtrl.selectAccountApps(record.id),
            ),
        ],
      ),
    );
  }

  /// Maps the current [selection] to the selected pane index so the master pane
  /// highlight tracks the detail view.
  ///
  /// `NavigationPane.selected` indexes into fluent_ui's `effectiveItems`, which
  /// (per fluent_ui 4.15.1) keeps only `i is PaneItem && i is! PaneItemAction &&
  /// i.body != null`. That EXCLUDES every [PaneItemHeader] ("Mobile",
  /// "Development", "Accounts"), [PaneItemSeparator], and [PaneItemAction] —
  /// including the dimmed coming-soon placeholders (Play Store, Firebase,
  /// Github).
  ///
  /// The surviving effective order is therefore:
  ///   - index 0 → Home
  ///   - index 1 → App Store Connect
  ///   - indices 2..N+1 → the connected accounts, in list order
  ///
  /// Home and App Store Connect now highlight independently because they route
  /// to distinct detail views:
  ///   - [DetailView.home] → Home (index 0).
  ///   - no account selected and not Home (e.g. [DetailView.none]) → App Store
  ///     Connect (index 1), the accounts landing.
  ///   - an account selected → `pos + accountsOffset`, falling back to App
  ///     Store Connect (1) if the id is no longer in `records`.
  ///
  /// `accountsOffset` (= 2) is the count of navigable items that precede the
  /// accounts (Home + App Store Connect). This method never returns the index
  /// of a header or action.
  int _selectedPaneIndex(
    List<AccountRecord> records,
    DesktopSelection selection,
  ) {
    const homeIndex = 0;
    const appStoreConnectIndex = 1;
    // Navigable items rendered before the accounts: Home (0) + App Store
    // Connect (1). The first account therefore lands at effective index 2.
    const accountsOffset = 2;

    if (selection.view == DetailView.home) return homeIndex;

    final accountId = selection.accountId;
    // No account in scope (and not Home) → the App Store Connect landing.
    if (accountId == null) return appStoreConnectIndex;

    final pos = records.indexWhere((r) => r.id == accountId);
    // The account at list position `pos` is `pos + accountsOffset`; if the id
    // is stale, fall back to the App Store Connect landing.
    return pos < 0 ? appStoreConnectIndex : pos + accountsOffset;
  }
}

/// Builds a dimmed, non-interactive "coming soon" navigation entry.
///
/// Implemented as a [PaneItemAction] rather than a [PaneItem] on purpose:
/// actions are excluded from fluent_ui's `effectiveItems`, so the placeholder
/// never claims a `selected` index and cannot perturb the [HomeShell]
/// selection math. The [icon] and [label] are rendered at reduced opacity and
/// the title is suffixed with "(soon)"; a "Coming soon" tooltip and a trailing
/// "Soon" tag reinforce the disabled state. The tap is a no-op.
///
/// Strings are intentionally in English to match the desktop app UI; they can be
/// swapped to Portuguese ("Em breve") if the product chooses a localized UI.
PaneItemAction _comingSoonItem({
  required IconData icon,
  required String label,
}) {
  const disabledOpacity = 0.4;

  return PaneItemAction(
    icon: Opacity(
      opacity: disabledOpacity,
      child: Icon(icon),
    ),
    title: Opacity(
      opacity: disabledOpacity,
      child: Text('$label (soon)'),
    ),
    // A muted "Soon" tag at the trailing edge; surfaces in the expanded rail.
    trailing: Builder(
      builder: (context) {
        final theme = FluentTheme.of(context);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.resources.subtleFillColorSecondary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Soon',
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorDisabled,
            ),
          ),
        );
      },
    ),
    // Non-interactive: a no-op tap keeps the item inert. The tooltip clarifies
    // why nothing happens.
    onTap: () {},
  );
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
      case DetailView.home:
        return const HomeView();
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
///
/// Its [PageHeader] hosts the "Add account" command — a [CommandBar] button at
/// the top-right that opens the add-account modal (see [showAddAccountDialog]).
/// This is the sole entry point for connecting an account; the navigation rail
/// no longer carries a footer command for it.
class _AccountsEmptyDetail extends ConsumerWidget {
  const _AccountsEmptyDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsControllerProvider);

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('App Store Connect'),
        // A right-aligned command bar (the default `MainAxisAlignment.end`)
        // hosting the "Add account" action. This replaces the former pane
        // footer [PaneItemAction]; it opens the same modal but reads as a
        // page-level command in the detail view rather than a rail entry.
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: const Text('Add account'),
              onPressed: () => showAddAccountDialog(context),
            ),
          ],
        ),
      ),
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
                    ? 'No accounts yet. Use "Add account" above to connect one.'
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
