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
import '../apps/archived_apps_pane.dart';
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
///      renders the connected accounts list ([_AccountsDetail]).
///      When at least one account is connected, "App Store Connect" is a
///      [PaneItemExpander] whose nested child items are the connected accounts
///      (effective indices 2..N+1), shown expanded by default so they read as
///      its children. With no accounts it degrades to a plain [PaneItem] (no
///      dangling chevron).
///   3. A "Development" section header with the coming-soon "Github" entry.
///
/// The coming-soon entries (Play Store, Firebase, Github) are rendered as
/// dimmed, non-interactive [PaneItemAction]s. [PaneItemAction] is excluded from
/// fluent_ui's `effectiveItems`, so these placeholders never occupy a `selected`
/// index — keeping the selection math in [_selectedPaneIndex] tied solely to the
/// navigable items (Home, App Store Connect, and the accounts).
///
/// There is no pane footer: the "Add account" command lives in the accounts
/// detail view's [PageHeader] as a [CommandBar] button (see
/// [_AccountsDetail]), not in the navigation rail.
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
    final l10n = AppLocalizations.of(context)!;

    final records = accounts.valueOrNull ?? const <AccountRecord>[];
    final selectedIndex = _selectedPaneIndex(records, selection);

    return NavigationView(
      titleBar: _ShellTitleBar(isExpanded: isExpanded),
      pane: NavigationPane(
        // fluent_ui asserts a non-null `selected` whenever any item renders its
        // body, so index 0 is a synthetic "Home" item that always exists.
        // "App Store Connect" is the next navigable item (index 1); when
        // accounts exist it is a [PaneItemExpander] and its nested account
        // children flatten inline right after it (indices 2..N+1). The section
        // headers and the coming-soon [PaneItemAction]s carry no index (see
        // [_selectedPaneIndex]).
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
            title: Text(l10n.navHome),
            body: _DetailPane(selection: selection),
            // Routes the detail pane to the dedicated Home dashboard
            // ([HomeView]) — distinct from "App Store Connect", which clears to
            // the accounts landing.
            onTap: selectionCtrl.showHome,
          ),
          // --- Mobile section -------------------------------------------------
          // A non-navigable header; excluded from `effectiveItems`.
          PaneItemHeader(header: Text(l10n.navMobileSection)),
          // The only enabled new destination, at effective index 1. Tapping it
          // clears the account selection ([DetailView.none]), routing the detail
          // pane to the connected accounts list (`_AccountsDetail`) — the
          // distinct counterpart to Home (which routes to [HomeView]).
          //
          // The connected accounts are nested directly under this item so the
          // grouping is unambiguous. We use a [PaneItemExpander] (a [PaneItem]
          // subclass that renders nested child `items` indented with a
          // chevron); `initiallyExpanded: true` keeps the accounts visible
          // without a manual expand. fluent_ui flattens the expander and its
          // children inline into `effectiveItems` — the expander at index 1 and
          // each account at index 2..N+1 in list order — so [_selectedPaneIndex]
          // keeps its existing math (see that method for the flattening rule).
          //
          // With no accounts we degrade to a plain [PaneItem]: an empty expander
          // would render a dangling chevron with nothing to reveal.
          if (records.isEmpty)
            PaneItem(
              icon: const Icon(SimpleIcons.apple),
              title: Text(l10n.navAppStoreConnect),
              body: _DetailPane(selection: selection),
              onTap: selectionCtrl.clear,
            )
          else
            PaneItemExpander(
              icon: const Icon(SimpleIcons.apple),
              title: Text(l10n.navAppStoreConnect),
              body: _DetailPane(selection: selection),
              // Tapping the parent still navigates to the accounts-list detail
              // view (and highlights index 1); the chevron only toggles the
              // child visibility.
              onTap: selectionCtrl.clear,
              initiallyExpanded: true,
              items: [
                for (final record in records)
                  PaneItem(
                    // Account child rows intentionally carry no leading icon —
                    // only the account label shows. `PaneItem.icon` is required
                    // and non-null, so a zero-size [SizedBox.shrink] stands in
                    // to render no glyph without reserving an icon slot that
                    // would push the label.
                    icon: const SizedBox.shrink(),
                    title: Text(record.label),
                    body: _DetailPane(selection: selection),
                    onTap: () => selectionCtrl.selectAccountApps(record.id),
                  ),
              ],
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
          PaneItemHeader(header: Text(l10n.navDevelopmentSection)),
          _comingSoonItem(
            icon: SimpleIcons.github,
            label: 'Github',
          ),
        ],
      ),
    );
  }

  /// Maps the current [selection] to the selected pane index so the master pane
  /// highlight tracks the detail view.
  ///
  /// `NavigationPane.selected` indexes into fluent_ui's `effectiveItems`, which
  /// (per fluent_ui 4.15.1) flattens the pane tree depth-first into `allItems`
  /// — a [PaneItemExpander] is followed inline by its child `items` — then
  /// keeps only `i is PaneItem && i is! PaneItemAction && i.body != null`. That
  /// EXCLUDES every [PaneItemHeader] ("Mobile", "Development"),
  /// [PaneItemSeparator], and [PaneItemAction] — including the dimmed
  /// coming-soon placeholders (Play Store, Firebase, Github) — regardless of
  /// the expander's expanded/collapsed visual state (collapsing only hides
  /// children visually; they remain in `effectiveItems`).
  ///
  /// The surviving effective order is therefore:
  ///   - index 0 → Home
  ///   - index 1 → App Store Connect (the [PaneItemExpander] parent, or a plain
  ///     [PaneItem] when no account is connected)
  ///   - indices 2..N+1 → the connected accounts, in list order — the
  ///     expander's child items, flattened inline right after the parent
  ///
  /// Because the expander itself has a non-null `body` it occupies index 1 and
  /// its children follow at 2..N+1, this is the identical layout to a flat
  /// Home / App Store Connect / accounts list; the nesting changes only the
  /// rendering, not the index math.
  ///
  /// Home and App Store Connect highlight independently because they route to
  /// distinct detail views:
  ///   - [DetailView.home] → Home (index 0).
  ///   - no account selected and not Home (e.g. [DetailView.none]) → App Store
  ///     Connect (index 1), the accounts landing / expander parent.
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
/// The "(soon)" suffix and "Soon" tag are localized via [AppLocalizations]
/// inside [Builder]s (this function runs outside a build context). The brand
/// [label] (Play Store, Firebase, Github) is a proper noun and stays verbatim.
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
    title: Builder(
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return Opacity(
          opacity: disabledOpacity,
          child: Text(l10n.comingSoonLabel(label)),
        );
      },
    ),
    // A muted "Soon" tag at the trailing edge; surfaces in the expanded rail.
    trailing: Builder(
      builder: (context) {
        final theme = FluentTheme.of(context);
        final l10n = AppLocalizations.of(context)!;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.resources.subtleFillColorSecondary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            l10n.soonTag,
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
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          const SizedBox(width: 4),
          Tooltip(
            message: isExpanded ? l10n.collapseSidebar : l10n.expandSidebar,
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
            message: l10n.settingsTitle,
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
        return const _AccountsDetail();
      case DetailView.apps:
        return AppsPane(accountId: selection.accountId!);
      case DetailView.archivedApps:
        return ArchivedAppsPane(accountId: selection.accountId!);
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

/// The "App Store Connect" detail pane: lists the connected App Store Connect
/// accounts as selectable rows. Tapping a row opens that account's apps
/// (mirrors the sidebar account items, driving [selectionControllerProvider]'s
/// [SelectionController.selectAccountApps]). Surfaces the accounts controller's
/// loading/error states (the master pane itself cannot) and an empty state when
/// no account is connected yet.
///
/// Its [PageHeader] hosts the "Add account" command — a [CommandBar] button at
/// the top-right that opens the add-account modal (see [showAddAccountDialog]).
/// This is the sole entry point for connecting an account; the navigation rail
/// no longer carries a footer command for it.
class _AccountsDetail extends ConsumerWidget {
  const _AccountsDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsControllerProvider);
    final l10n = AppLocalizations.of(context)!;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(l10n.navAppStoreConnect),
        // A right-aligned command bar (the default `MainAxisAlignment.end`)
        // hosting the "Add account" action. This replaces the former pane
        // footer [PaneItemAction]; it opens the same modal but reads as a
        // page-level command in the detail view rather than a rail entry.
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: Text(l10n.addAccount),
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
              title: Text(l10n.couldNotLoadAccounts),
              content: Text(stackErrorMessage(error)),
              severity: InfoBarSeverity.error,
            ),
          ),
        ),
        // Filter to App Store Connect so this pane stays correct once other
        // [ServiceKind]s exist; today every record already matches.
        data: (records) {
          final ascAccounts = records
              .where((r) => r.kind == ServiceKind.appStoreConnect)
              .toList();

          if (ascAccounts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.cloud_add, size: 48),
                  const SizedBox(height: 12),
                  Text(l10n.noAccountsYetDesktop),
                ],
              ),
            );
          }

          // A left-aligned, full-width, scrollable list — one selectable row
          // per account. Tapping a row opens its apps via the same selection
          // controller call the sidebar account items use.
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: ascAccounts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final record = ascAccounts[index];
              return _AccountTile(
                record: record,
                onPressed: () => ref
                    .read(selectionControllerProvider.notifier)
                    .selectAccountApps(record.id),
              );
            },
          );
        },
      ),
    );
  }
}

/// A single selectable account row in [_AccountsDetail].
///
/// Rendered as a full-width fluent_ui [Button] (its hover/press states give the
/// affordance of a tappable card) wrapping a [Row]: an Apple brand glyph, the
/// account [AccountRecord.label] over a muted [ServiceKindLabel.label]
/// subtitle, and a trailing chevron signalling it drills into the account's
/// apps. Extracted as its own widget (rather than an inline builder method) so
/// each row rebuilds in isolation.
class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.record, required this.onPressed});

  final AccountRecord record;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Button(
      onPressed: onPressed,
      style: const ButtonStyle(
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      child: Row(
        children: [
          const Icon(SimpleIcons.apple, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  record.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.bodyStrong,
                ),
                const SizedBox(height: 2),
                Text(
                  record.kind.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            FluentIcons.chevron_right,
            size: 12,
            color: theme.resources.textFillColorSecondary,
          ),
        ],
      ),
    );
  }
}
