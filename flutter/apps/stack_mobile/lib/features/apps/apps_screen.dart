import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/stack_error_message.dart';

/// Lists the apps for a single account, offline-first (cache then synced).
///
/// Pull-to-refresh triggers `AppsController.refresh()`. Tapping an app routes to
/// its detail screen.
class AppsScreen extends ConsumerWidget {
  const AppsScreen({required this.accountId, super.key});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(appsControllerProvider(accountId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apps'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(appsControllerProvider(accountId).notifier).refresh(),
        child: apps.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _AppsError(message: stackErrorMessage(error)),
          data: (items) => items.isEmpty
              ? const _EmptyApps()
              : _AppsList(accountId: accountId, items: items),
        ),
      ),
    );
  }
}

class _AppsList extends StatelessWidget {
  const _AppsList({required this.accountId, required this.items});

  final String accountId;
  final List<AppInfo> items;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // AlwaysScrollable so pull-to-refresh works even with few items.
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final app = items[index];
        return ListTile(
          leading: const Icon(Icons.apps),
          title: Text(app.name),
          subtitle: Text(
            app.platform == null
                ? app.bundleId
                : '${app.bundleId} · ${app.platform}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              context.go('/accounts/$accountId/apps/${app.id}'),
        );
      },
    );
  }
}

class _EmptyApps extends StatelessWidget {
  const _EmptyApps();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        Center(child: Text('No apps found for this account.')),
      ],
    );
  }
}

class _AppsError extends StatelessWidget {
  const _AppsError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.error_outline, size: 48),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
      ],
    );
  }
}
