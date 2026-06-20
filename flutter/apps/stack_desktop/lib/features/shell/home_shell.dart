import 'package:fluent_ui/fluent_ui.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/service_kind_label.dart';
import '../../core/stack_error_message.dart';
import '../accounts/add_account_pane.dart';
import '../apps/app_detail_pane.dart';
import '../apps/apps_pane.dart';
import '../reviews/reviews_pane.dart';
import 'selection.dart';

/// Desktop master-detail shell.
///
/// The left [NavigationPane] is the master: connected accounts (each a
/// `PaneItem`) plus an "Add account" footer command. Selecting an account drives
/// the [selectionControllerProvider]; the right detail pane renders apps → app
/// detail → reviews for that selection. This is deliberately a multi-pane Fluent
/// layout, distinct from the mobile single-stack navigation.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsControllerProvider);
    final selection = ref.watch(selectionControllerProvider);
    final selectionCtrl = ref.read(selectionControllerProvider.notifier);

    final records = accounts.valueOrNull ?? const <AccountRecord>[];
    final selectedIndex = _selectedPaneIndex(records, selection);

    return NavigationView(
      pane: NavigationPane(
        // fluent_ui asserts a non-null `selected` whenever any item renders its
        // body, so index 0 is a synthetic "Home" item that always exists; the
        // accounts occupy indices 1..N below it.
        selected: selectedIndex,
        displayMode: PaneDisplayMode.expanded,
        header: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text('Stack Connect'),
        ),
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
          PaneItem(
            icon: const Icon(FluentIcons.add),
            title: const Text('Add account'),
            body: _DetailPane(selection: selection),
            onTap: selectionCtrl.openAddAccount,
          ),
        ],
      ),
    );
  }

  /// Maps the current [selection] to the selected pane index so the master pane
  /// highlight tracks the detail view.
  ///
  /// `NavigationPane.selected` indexes into fluent_ui's `effectiveItems`, which
  /// keeps only navigable [PaneItem]s and EXCLUDES [PaneItemHeader] and
  /// [PaneItemSeparator]. So the effective order is: Home(0), accounts(1..N),
  /// then the footer "Add account"(N+1) — the "Accounts" header and the footer
  /// separator do not occupy an index.
  int _selectedPaneIndex(
    List<AccountRecord> records,
    DesktopSelection selection,
  ) {
    const homeIndex = 0;
    // Home(0) + the N accounts ⇒ "Add account" is the next effective item.
    final addAccountIndex = records.length + 1;

    if (selection.view == DetailView.addAccount) return addAccountIndex;

    final accountId = selection.accountId;
    if (accountId == null) return homeIndex;
    final pos = records.indexWhere((r) => r.id == accountId);
    // Home occupies index 0, so the account at list position `pos` is `pos + 1`.
    return pos < 0 ? homeIndex : pos + 1;
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
      case DetailView.addAccount:
        return const AddAccountPane();
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
      header: const PageHeader(title: Text('Stack Connect')),
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
