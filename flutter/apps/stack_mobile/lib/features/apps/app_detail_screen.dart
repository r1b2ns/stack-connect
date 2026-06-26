import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/stack_error_message.dart';
import 'widgets/app_icon.dart';

/// Basic app detail: icon, name, bundle id, platform, local favorite/archive
/// flags, and entry points to the app's Ratings & Reviews, TestFlight Builds,
/// App Store Versions, and Beta Groups.
///
/// The [AppView] is sourced from [appListProvider] (which includes archived
/// apps), found by [appId] — no dedicated single-app endpoint exists in this
/// slice's controller API. The app-bar ⋮ menu reflects and toggles the flags.
class AppDetailScreen extends ConsumerWidget {
  const AppDetailScreen({
    required this.accountId,
    required this.appId,
    super.key,
  });

  final String accountId;
  final String appId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(appListProvider(accountId));
    final app = apps.valueOrNull?.where((a) => a.id == appId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(app?.name ?? 'App'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/accounts/$accountId/apps'),
        ),
        actions: [
          if (app != null)
            PopupMenuButton<String>(
              onSelected: (value) => _onSelected(context, ref, app, value),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'favorite',
                  child: Text(app.isFavorite ? 'Unfavorite' : 'Favorite'),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: Text(app.isArchived ? 'Unarchive' : 'Archive'),
                ),
              ],
            ),
        ],
      ),
      body: app == null
          ? const Center(child: Text('App not found.'))
          : ListView(
              children: [
                _AppHeader(accountId: accountId, app: app),
                const Divider(height: 1),
                _DetailTile(
                  icon: Icons.badge_outlined,
                  label: 'Name',
                  value: app.name,
                ),
                _DetailTile(
                  icon: Icons.tag,
                  label: 'Bundle ID',
                  value: app.bundleId,
                ),
                _DetailTile(
                  icon: Icons.devices_outlined,
                  label: 'Platform',
                  value: app.platform ?? '—',
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.star_outline),
                  title: const Text('Ratings & Reviews'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(
                    '/accounts/$accountId/apps/$appId/reviews',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('TestFlight Builds'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(
                    '/accounts/$accountId/apps/$appId/builds',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.layers_outlined),
                  title: const Text('App Store Versions'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(
                    '/accounts/$accountId/apps/$appId/versions',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: const Text('Beta Groups'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(
                    '/accounts/$accountId/apps/$appId/beta-groups',
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _onSelected(
    BuildContext context,
    WidgetRef ref,
    AppView app,
    String value,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(appFlagsControllerProvider(accountId).notifier);
    try {
      switch (value) {
        case 'favorite':
          final wasFavorite = app.isFavorite;
          await notifier.toggleFavorite(app.id);
          messenger.showSnackBar(SnackBar(
            content: Text(
              wasFavorite ? 'Removed from favorites' : 'Added to favorites',
            ),
          ));
        case 'archive':
          final wasArchived = app.isArchived;
          await notifier.toggleArchive(app.id);
          messenger.showSnackBar(SnackBar(
            content: Text(wasArchived ? 'Unarchived' : 'Archived'),
          ));
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(stackErrorMessage(error))),
      );
    }
  }
}

/// The detail header: a larger app icon beside the app name.
class _AppHeader extends StatelessWidget {
  const _AppHeader({required this.accountId, required this.app});

  final String accountId;
  final AppView app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          AppIcon(
            accountId: accountId,
            appId: app.id,
            size: 56,
            radius: 12,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(app.name, style: theme.textTheme.titleLarge),
          ),
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}
