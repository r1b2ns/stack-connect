import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/stack_error_message.dart';
import 'widgets/app_icon.dart';

/// Lists the ARCHIVED apps for a single account.
///
/// Opened from the Apps screen's app-bar overflow menu. Consumes
/// [archivedAppListProvider]. Each row exposes a ⋮ menu with a single
/// "Unarchive" action that flips the local archive flag back off (returning the
/// app to the active list). Shows an empty state when no app is archived.
class ArchivedAppsScreen extends ConsumerWidget {
  const ArchivedAppsScreen({required this.accountId, super.key});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(archivedAppListProvider(accountId));
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.archived),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/accounts/$accountId/apps'),
        ),
      ),
      body: apps.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ArchivedError(message: stackErrorMessage(error)),
        data: (items) => items.isEmpty
            ? const _EmptyArchived()
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) =>
                    _ArchivedRow(accountId: accountId, app: items[index]),
              ),
      ),
    );
  }
}

/// A single archived-app row with a ⋮ "Unarchive" action.
class _ArchivedRow extends ConsumerWidget {
  const _ArchivedRow({required this.accountId, required this.app});

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
        onSelected: (value) {
          if (value == 'unarchive') _unarchive(context, ref);
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'unarchive',
            child: Text(l10n.unarchiveAction),
          ),
        ],
      ),
    );
  }

  Future<void> _unarchive(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // The flag is a single boolean toggle; archived rows can only un-archive.
      await ref
          .read(appFlagsControllerProvider(accountId).notifier)
          .toggleArchive(app.id);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.unarchivedToast)),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(stackErrorMessage(error))),
      );
    }
  }
}

class _EmptyArchived extends StatelessWidget {
  const _EmptyArchived();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(child: Text(l10n.noArchivedApps));
  }
}

class _ArchivedError extends StatelessWidget {
  const _ArchivedError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
