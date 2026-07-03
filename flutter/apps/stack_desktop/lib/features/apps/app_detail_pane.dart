import 'package:fluent_ui/fluent_ui.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/stack_error_message.dart';
import '../shell/selection.dart';
import 'widgets/app_icon.dart';

/// Detail pane: basic metadata for the selected app plus an entry point to its
/// Ratings & Reviews and commands to toggle its local favorite/archive flags.
///
/// The [AppView] is sourced from [appListProvider] (which includes archived
/// apps), found by [appId] — no single-app endpoint exists in this slice's
/// controller API. The command bar reflects and toggles the local flags.
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
    final apps = ref.watch(appListProvider(accountId));
    final app = apps.valueOrNull?.where((a) => a.id == appId).firstOrNull;
    final selection = ref.read(selectionControllerProvider.notifier);
    final l10n = AppLocalizations.of(context)!;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(app?.name ?? l10n.appFallbackTitle),
        leading: IconButton(
          icon: const Icon(FluentIcons.back),
          onPressed: selection.backToApps,
        ),
        commandBar: app == null
            ? null
            : CommandBar(
                mainAxisAlignment: MainAxisAlignment.end,
                primaryItems: [
                  CommandBarButton(
                    icon: Icon(
                      app.isFavorite
                          ? FluentIcons.favorite_star_fill
                          : FluentIcons.favorite_star,
                    ),
                    label: Text(
                      app.isFavorite
                          ? l10n.unfavoriteAction
                          : l10n.favoriteAction,
                    ),
                    onPressed: () => _toggleFavorite(context, ref, app),
                  ),
                  CommandBarButton(
                    icon: Icon(
                      app.isArchived
                          ? FluentIcons.archive_undo
                          : FluentIcons.archive,
                    ),
                    label: Text(
                      app.isArchived
                          ? l10n.unarchiveAction
                          : l10n.archiveAction,
                    ),
                    onPressed: () => _toggleArchive(context, ref, app),
                  ),
                ],
              ),
      ),
      content: app == null
          ? Center(child: Text(l10n.appNotFound))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppIcon(
                        accountId: accountId,
                        appId: app.id,
                        size: 56,
                        radius: 12,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          app.name,
                          style: FluentTheme.of(context).typography.subtitle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _InfoRow(label: l10n.fieldName, value: app.name),
                  _InfoRow(label: l10n.fieldBundleId, value: app.bundleId),
                  _InfoRow(
                    label: l10n.fieldPlatform,
                    value: app.platform ?? '—',
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: selection.openReviews,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(FluentIcons.favorite_star),
                        const SizedBox(width: 8),
                        Text(l10n.ratingsAndReviews),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    AppView app,
  ) async {
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

  Future<void> _toggleArchive(
    BuildContext context,
    WidgetRef ref,
    AppView app,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final wasArchived = app.isArchived;
    try {
      await ref
          .read(appFlagsControllerProvider(accountId).notifier)
          .toggleArchive(app.id);
      if (context.mounted) {
        await _toast(
          context,
          wasArchived ? l10n.unarchivedToast : l10n.archivedToast,
        );
      }
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
