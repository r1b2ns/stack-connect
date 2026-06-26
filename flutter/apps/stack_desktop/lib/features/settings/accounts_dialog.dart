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
    final l10n = AppLocalizations.of(context)!;

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
      title: Text(l10n.accountsTitle),
      content: accounts.when(
        loading: () => const Center(child: ProgressRing()),
        error: (error, _) => Center(child: Text(stackErrorMessage(error))),
        data: (records) => records.isEmpty
            ? Center(
                child: Text(l10n.noAccountsConnected),
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
          child: Text(l10n.close),
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
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: const Icon(FluentIcons.cloud),
      title: Text(record.label),
      subtitle: Text(record.kind.label),
      trailing: Button(
        onPressed: () => _confirmRemove(context, ref),
        child: Text(l10n.removeAction),
      ),
    );
  }

  /// Asks for confirmation before removing [record]; on confirm delegates to the
  /// accounts controller. Errors surface in an [InfoBar] flyout.
  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(l10n.removeAccountTitle),
        content: Text(l10n.removeAccountConfirmBody(record.label)),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(Colors.red),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.removeAction),
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
            title: Text(l10n.couldNotRemoveAccount),
            content: Text(stackErrorMessage(error)),
            severity: InfoBarSeverity.error,
            onClose: close,
          ),
        );
      }
    }
  }
}
