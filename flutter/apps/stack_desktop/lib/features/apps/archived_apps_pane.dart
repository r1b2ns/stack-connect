import 'package:fluent_ui/fluent_ui.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/stack_error_message.dart';
import '../shell/selection.dart';

/// Detail pane: the ARCHIVED apps for the selected account.
///
/// Opened from the Apps pane's "Archived" command. Consumes
/// [archivedAppListProvider]. Each row exposes a single "Unarchive" action that
/// flips the local archive flag back off (moving the app back into the active
/// list). The header carries a Back command (to the active apps) and a Refresh
/// command that re-syncs the underlying apps. An empty state is shown when no
/// app is archived.
class ArchivedAppsPane extends ConsumerWidget {
  const ArchivedAppsPane({required this.accountId, super.key});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(archivedAppListProvider(accountId));
    final selection = ref.read(selectionControllerProvider.notifier);

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Archived'),
        leading: IconButton(
          icon: const Icon(FluentIcons.back),
          onPressed: selection.backToApps,
        ),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              label: const Text('Refresh'),
              onPressed: () => ref
                  .read(appsControllerProvider(accountId).notifier)
                  .refresh(),
            ),
          ],
        ),
      ),
      content: apps.when(
        loading: () => const Center(child: ProgressRing()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: InfoBar(
              title: const Text('Could not load apps'),
              content: Text(stackErrorMessage(error)),
              severity: InfoBarSeverity.error,
            ),
          ),
        ),
        data: (items) => items.isEmpty
            ? const Center(child: Text('No archived apps.'))
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) =>
                    _ArchivedAppRow(accountId: accountId, app: items[index]),
              ),
      ),
    );
  }
}

/// A single archived-app row with an always-visible "Unarchive" action.
class _ArchivedAppRow extends ConsumerWidget {
  const _ArchivedAppRow({required this.accountId, required this.app});

  final String accountId;
  final AppView app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(FluentIcons.cube_shape),
      title: Text(app.name),
      subtitle: Text(
        app.platform == null
            ? app.bundleId
            : '${app.bundleId} · ${app.platform}',
      ),
      trailing: Tooltip(
        message: 'Unarchive',
        child: Button(
          onPressed: () => _unarchive(context, ref),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.archive_undo),
              SizedBox(width: 6),
              Text('Unarchive'),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _unarchive(BuildContext context, WidgetRef ref) async {
    try {
      // The flag is a single boolean toggle; archived rows can only un-archive.
      await ref
          .read(appFlagsControllerProvider(accountId).notifier)
          .toggleArchive(app.id);
      if (context.mounted) {
        await displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: const Text('Unarchived'),
            severity: InfoBarSeverity.success,
            onClose: close,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        await displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: const Text('Could not update app'),
            content: Text(stackErrorMessage(error)),
            severity: InfoBarSeverity.error,
            onClose: close,
          ),
        );
      }
    }
  }
}
