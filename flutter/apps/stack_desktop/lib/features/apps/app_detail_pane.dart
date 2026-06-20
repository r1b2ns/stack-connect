import 'package:fluent_ui/fluent_ui.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../shell/selection.dart';

/// Detail pane: basic metadata for the selected app plus an entry point to its
/// Ratings & Reviews.
///
/// The [AppInfo] is sourced from the already-loaded apps list for the account
/// (no single-app endpoint exists in this slice's controller API).
class AppDetailPane extends ConsumerWidget {
  const AppDetailPane({
    required this.accountId,
    required this.appId,
    super.key,
  });

  final String accountId;
  final String appId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(appsControllerProvider(accountId));
    final app = apps.valueOrNull?.where((a) => a.id == appId).firstOrNull;
    final selection = ref.read(selectionControllerProvider.notifier);

    return ScaffoldPage(
      header: PageHeader(
        title: Text(app?.name ?? 'App'),
        leading: IconButton(
          icon: const Icon(FluentIcons.back),
          onPressed: selection.backToApps,
        ),
      ),
      content: app == null
          ? const Center(child: Text('App not found.'))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(label: 'Name', value: app.name),
                  _InfoRow(label: 'Bundle ID', value: app.bundleId),
                  _InfoRow(label: 'Platform', value: app.platform ?? '—'),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: selection.openReviews,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.favorite_star),
                        SizedBox(width: 8),
                        Text('Ratings & Reviews'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final typography = FluentTheme.of(context).typography;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: typography.bodyStrong),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
