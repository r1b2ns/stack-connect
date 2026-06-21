import 'package:fluent_ui/fluent_ui.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/service_kind_label.dart';
import '../../core/stack_error_message.dart';

/// Accounts-management sub-view of the Settings modal.
///
/// A focused desktop equivalent of the iOS Settings > Accounts screen: it lists
/// every connected account (from [accountsControllerProvider]) and offers a
/// per-account **Remove** action guarded by a confirmation dialog. On confirm it
/// calls [AccountsController.removeAccount], which drops the account's secrets,
/// its record, and invalidates the cached connected provider.
///
/// Out of scope (follow-up): the richer iOS import/export and edit-name flows.
/// This view is intentionally list + remove only.
class AccountsDialog extends ConsumerWidget {
  const AccountsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsControllerProvider);

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
      title: const Text('Accounts'),
      content: accounts.when(
        loading: () => const Center(child: ProgressRing()),
        error: (error, _) => Center(child: Text(stackErrorMessage(error))),
        data: (records) => records.isEmpty
            ? const Center(
                child: Text('No accounts connected yet.'),
              )
            : SizedBox(
                width: 520,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: records.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return _AccountRow(record: record);
                  },
                ),
              ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// A single account row: its label, its service kind, and a Remove command.
class _AccountRow extends ConsumerWidget {
  const _AccountRow({required this.record});

  final AccountRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(FluentIcons.cloud),
      title: Text(record.label),
      subtitle: Text(record.kind.label),
      trailing: Button(
        onPressed: () => _confirmRemove(context, ref),
        child: const Text('Remove'),
      ),
    );
  }

  /// Asks for confirmation before removing [record]; on confirm delegates to the
  /// accounts controller. Errors surface in an [InfoBar] flyout.
  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Remove account'),
        content: Text(
          'Remove "${record.label}"? Its apps, versions, and credentials '
          'will be deleted from the app. This cannot be undone.',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(Colors.red),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(accountsControllerProvider.notifier)
          .removeAccount(record.id);
    } catch (error) {
      if (context.mounted) {
        await displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: const Text('Could not remove account'),
            content: Text(stackErrorMessage(error)),
            severity: InfoBarSeverity.error,
            onClose: close,
          ),
        );
      }
    }
  }
}
