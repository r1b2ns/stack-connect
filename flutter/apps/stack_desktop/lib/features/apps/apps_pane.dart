import 'package:fluent_ui/fluent_ui.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/stack_error_message.dart';
import '../shell/selection.dart';

/// Detail pane: the apps for the selected account, offline-first.
///
/// A toolbar Refresh command re-syncs via `AppsController.refresh()`. Selecting
/// an app drives the selection controller to the app-detail view.
class AppsPane extends ConsumerWidget {
  const AppsPane({required this.accountId, super.key});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(appsControllerProvider(accountId));

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Apps'),
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
        error: (error, _) => _PaneError(message: stackErrorMessage(error)),
        data: (items) => items.isEmpty
            ? const Center(child: Text('No apps found for this account.'))
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final app = items[index];
                  return _AppRow(app: app);
                },
              ),
      ),
    );
  }
}

class _AppRow extends ConsumerWidget {
  const _AppRow({required this.app});

  final AppInfo app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile.selectable(
      leading: const Icon(FluentIcons.cube_shape),
      title: Text(app.name),
      subtitle: Text(
        app.platform == null
            ? app.bundleId
            : '${app.bundleId} · ${app.platform}',
      ),
      onPressed: () =>
          ref.read(selectionControllerProvider.notifier).openAppDetail(app.id),
    );
  }
}

class _PaneError extends StatelessWidget {
  const _PaneError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: InfoBar(
          title: const Text('Could not load apps'),
          content: Text(message),
          severity: InfoBarSeverity.error,
        ),
      ),
    );
  }
}
