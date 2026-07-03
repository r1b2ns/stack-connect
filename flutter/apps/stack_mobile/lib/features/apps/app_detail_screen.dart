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
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(app?.name ?? l10n.appFallbackTitle),
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
                  child: Text(
                    app.isFavorite
                        ? l10n.unfavoriteAction
                        : l10n.favoriteAction,
                  ),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: Text(
                    app.isArchived
                        ? l10n.unarchiveAction
                        : l10n.archiveAction,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: app == null
          ? Center(child: Text(l10n.appNotFound))
          : ListView(
              children: [
                _AppHeader(accountId: accountId, app: app),
                const Divider(height: 1),
                _DetailTile(
                  icon: Icons.badge_outlined,
                  label: l10n.fieldName,
                  value: app.name,
                ),
                _DetailTile(
                  icon: Icons.tag,
                  label: l10n.fieldBundleId,
                  value: app.bundleId,
                ),
                _DetailTile(
                  icon: Icons.devices_outlined,
                  label: l10n.fieldPlatform,
                  value: app.platform ?? '—',
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.star_outline),
                  title: Text(l10n.ratingsAndReviews),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(
                    '/accounts/$accountId/apps/$appId/reviews',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: Text(l10n.testFlightBuilds),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(
                    '/accounts/$accountId/apps/$appId/builds',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.layers_outlined),
                  title: Text(l10n.appStoreVersions),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(
                    '/accounts/$accountId/apps/$appId/versions',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: Text(l10n.betaGroups),
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
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(appFlagsControllerProvider(accountId).notifier);
    try {
      switch (value) {
        case 'favorite':
          final wasFavorite = app.isFavorite;
          await notifier.toggleFavorite(app.id);
          messenger.showSnackBar(SnackBar(
            content: Text(
              wasFavorite ? l10n.removedFromFavorites : l10n.addedToFavorites,
            ),
          ));
        case 'archive':
          final wasArchived = app.isArchived;
          await notifier.toggleArchive(app.id);
          messenger.showSnackBar(SnackBar(
            content: Text(wasArchived ? l10n.unarchivedToast : l10n.archivedToast),
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
