import 'package:fluent_ui/fluent_ui.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/stack_error_message.dart';
import '../shell/selection.dart';
import 'widgets/app_icon.dart';

/// Detail pane: the ACTIVE apps for the selected account, offline-first.
///
/// Consumes [activeAppListProvider] (favorites first, archived excluded). A
/// "Favorites" section header precedes the favorited rows, then the rest. Each
/// row carries always-visible trailing actions: a star toggle (favorite) and an
/// archive button. A toolbar Refresh command re-syncs via
/// `AppsController.refresh()`; an "Archived" command opens the archived list.
/// Selecting a row (its main body, not the trailing buttons) opens app detail.
class AppsPane extends ConsumerWidget {
  const AppsPane({required this.accountId, super.key});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(activeAppListProvider(accountId));
    final selection = ref.read(selectionControllerProvider.notifier);
    final l10n = AppLocalizations.of(context)!;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(l10n.appsTitle),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.archive),
              label: Text(l10n.archived),
              onPressed: selection.openArchivedApps,
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              label: Text(l10n.refresh),
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
            ? Center(child: Text(l10n.noAppsForAccount))
            : _AppsList(accountId: accountId, items: items),
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

    // A flat row model so a single ListView.builder renders both the section
    // header and the app rows without nesting scroll views.
    final rows = <Widget>[
      if (favorites.isNotEmpty) ...[
        _SectionHeader(label: l10n.favoritesSection),
        for (final app in favorites)
          _AppRow(accountId: accountId, app: app),
      ],
      if (rest.isNotEmpty) ...[
        if (favorites.isNotEmpty) _SectionHeader(label: l10n.allAppsSection),
        for (final app in rest) _AppRow(accountId: accountId, app: app),
      ],
    ];

    return ListView.builder(
      itemCount: rows.length,
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
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: theme.typography.bodyStrong?.copyWith(
          color: theme.resources.textFillColorSecondary,
        ),
      ),
    );
  }
}

/// A single active-app row: tap the body to open detail; the trailing star and
/// archive buttons toggle the local flags (always visible, never gating the row
/// tap).
class _AppRow extends ConsumerWidget {
  const _AppRow({required this.accountId, required this.app});

  final String accountId;
  final AppView app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final platform = app.platform;
    return ListTile.selectable(
      leading: AppIcon(accountId: accountId, appId: app.id),
      title: Text(app.name),
      subtitle: Text(
        platform == null
            ? app.bundleId
            : l10n.appSubtitleWithPlatform(app.bundleId, platform),
      ),
      onPressed: () => ref
          .read(selectionControllerProvider.notifier)
          .openAppDetail(app.id),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: app.isFavorite
                ? l10n.removeFromFavorites
                : l10n.addToFavorites,
            child: IconButton(
              icon: Icon(
                app.isFavorite
                    ? FluentIcons.favorite_star_fill
                    : FluentIcons.favorite_star,
              ),
              onPressed: () => _toggleFavorite(context, ref),
            ),
          ),
          Tooltip(
            message: l10n.archiveAction,
            child: IconButton(
              icon: const Icon(FluentIcons.archive),
              onPressed: () => _archive(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFavorite(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final wasFavorite = app.isFavorite;
    try {
      await ref
          .read(appFlagsControllerProvider(accountId).notifier)
          .toggleFavorite(app.id);
      if (context.mounted) {
        await _toast(
          context,
          wasFavorite ? l10n.removedFromFavorites : l10n.addedToFavorites,
        );
      }
    } catch (error) {
      if (context.mounted) await _errorToast(context, error);
    }
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref
          .read(appFlagsControllerProvider(accountId).notifier)
          .toggleArchive(app.id);
      if (context.mounted) await _toast(context, l10n.archivedToast);
    } catch (error) {
      if (context.mounted) await _errorToast(context, error);
    }
  }
}

/// Shows a brief success [InfoBar] with [message].
Future<void> _toast(BuildContext context, String message) => displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: Text(message),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );

/// Shows a mapped-error [InfoBar] for a failed flag toggle.
Future<void> _errorToast(BuildContext context, Object error) {
  final title = AppLocalizations.of(context)!.couldNotUpdateApp;
  return displayInfoBar(
    context,
    builder: (context, close) => InfoBar(
      title: Text(title),
      content: Text(stackErrorMessage(error)),
      severity: InfoBarSeverity.error,
      onClose: close,
    ),
  );
}

class _PaneError extends StatelessWidget {
  const _PaneError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: InfoBar(
          title: Text(l10n.couldNotLoadApps),
          content: Text(message),
          severity: InfoBarSeverity.error,
        ),
      ),
    );
  }
}
