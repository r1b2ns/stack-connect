import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/stack_error_message.dart';
import 'widgets/app_icon.dart';

/// Lists the ACTIVE apps for a single account, offline-first (cache then synced).
///
/// Consumes [activeAppListProvider] (favorites first, archived excluded). A
/// "Favorites" section header precedes the favorited rows, then "All apps".
/// Each row carries a ⋮ menu to favorite/unfavorite or archive. Pull-to-refresh
/// triggers `AppsController.refresh()`. The app-bar overflow menu opens the
/// archived list. Tapping an app routes to its detail screen.
class AppsScreen extends ConsumerWidget {
  const AppsScreen({required this.accountId, super.key});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(activeAppListProvider(accountId));
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'archived') {
                context.go('/accounts/$accountId/archived-apps');
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'archived', child: Text(l10n.archived)),
            ],
          ),
        ],
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

/// The active apps list, partitioned into a "Favorites" section (when any) and
/// the remaining apps. [items] is already favorites-first, so a single split on
/// [AppView.isFavorite] reconstructs both groups in order.
class _AppsList extends StatelessWidget {
  const _AppsList({required this.accountId, required this.items});

  final String accountId;
  final List<AppView> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final favorites = items.where((a) => a.isFavorite).toList();
    final rest = items.where((a) => !a.isFavorite).toList();

    // A flat row model so one ListView.separated renders both section headers
    // and app rows. Each entry knows whether it is a header (no divider above).
    final rows = <Widget>[
      if (favorites.isNotEmpty) ...[
        _SectionHeader(label: l10n.favoritesSection),
        for (final app in favorites) _AppRow(accountId: accountId, app: app),
      ],
      if (rest.isNotEmpty) ...[
        if (favorites.isNotEmpty) _SectionHeader(label: l10n.allAppsSection),
        for (final app in rest) _AppRow(accountId: accountId, app: app),
      ],
    ];

    return ListView.separated(
      // AlwaysScrollable so pull-to-refresh works even with few items.
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => rows[index],
    );
  }
}

/// A non-interactive section label rendered above a group of rows.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// A single active-app row: tap to open detail; the ⋮ menu toggles flags.
class _AppRow extends ConsumerWidget {
  const _AppRow({required this.accountId, required this.app});

  final String accountId;
  final AppView app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final platform = app.platform;
    return ListTile(
      leading: AppIcon(accountId: accountId, appId: app.id),
      title: Text(app.name),
      subtitle: Text(
        platform == null
            ? app.bundleId
            : l10n.appSubtitleWithPlatform(app.bundleId, platform),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) => _onSelected(context, ref, value),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'favorite',
            child: Text(
              app.isFavorite ? l10n.removeFromFavorites : l10n.addToFavorites,
            ),
          ),
          PopupMenuItem(value: 'archive', child: Text(l10n.archiveAction)),
        ],
      ),
      onTap: () => context.go('/accounts/$accountId/apps/${app.id}'),
    );
  }

  Future<void> _onSelected(
    BuildContext context,
    WidgetRef ref,
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
          await notifier.toggleArchive(app.id);
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.archivedToast)),
          );
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(stackErrorMessage(error))),
      );
    }
  }
}

class _EmptyApps extends StatelessWidget {
  const _EmptyApps();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(child: Text(l10n.noAppsForAccount)),
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
