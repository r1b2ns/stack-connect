import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/service_kind_label.dart';
import '../../core/stack_error_message.dart';

/// Home tab: the list of connected accounts.
///
/// Each row navigates to that account's apps. An "Add account" action (app bar
/// + FAB) routes to the add-account form. Renders empty/loading/error states.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsControllerProvider);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.accountsTitle),
        actions: [
          IconButton(
            tooltip: l10n.addAccount,
            icon: const Icon(Icons.add),
            onPressed: () => context.go('/accounts/add'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/accounts/add'),
        icon: const Icon(Icons.add),
        label: Text(l10n.addAccount),
      ),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _AccountsError(message: stackErrorMessage(error)),
        data: (records) => records.isEmpty
            ? const _EmptyAccounts()
            : _AccountsList(records: records),
      ),
    );
  }
}

class _AccountsList extends ConsumerWidget {
  const _AccountsList({required this.records});

  final List<AccountRecord> records;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      itemCount: records.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final record = records[index];
        return _AccountTile(record: record);
      },
    );
  }
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.record});

  final AccountRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.cloud_outlined)),
      title: Text(record.label),
      subtitle: Text(record.kind.label),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'remove') {
            ref
                .read(accountsControllerProvider.notifier)
                .removeAccount(record.id);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'remove', child: Text(l10n.removeAction)),
        ],
      ),
      onTap: () => context.go('/accounts/${record.id}/apps'),
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  const _EmptyAccounts();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(l10n.noAccountsYet, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              l10n.connectAccountToStart,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/accounts/add'),
              icon: const Icon(Icons.add),
              label: Text(l10n.addAccount),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountsError extends StatelessWidget {
  const _AccountsError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
