import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/stack_error_message.dart';

/// App Store Versions for a single (account, app).
///
/// Lists each version (version string, platform, App Store / app version state,
/// release type, and creation date), newest first. This is a read-only slice:
/// it surfaces the versions but offers no mutations.
class VersionsScreen extends ConsumerWidget {
  const VersionsScreen({
    required this.accountId,
    required this.appId,
    super.key,
  });

  final String accountId;
  final String appId;

  VersionsKey get _key => (accountId: accountId, appId: appId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = ref.watch(versionsControllerProvider(_key));
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appStoreVersions),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/accounts/$accountId/apps/$appId'),
        ),
      ),
      body: versions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              stackErrorMessage(error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (items) => items.isEmpty
            ? Center(child: Text(l10n.noVersionsYet))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _VersionCard(version: items[index]),
              ),
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.version});

  final AppStoreVersionInfo version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _versionLabel(l10n),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (version.appStoreState != null &&
                    version.appStoreState!.isNotEmpty)
                  _Pill(
                    label: version.appStoreState!,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
            if (version.platform != null && version.platform!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _Field(label: l10n.fieldPlatform, value: version.platform!),
            ],
            if (version.appVersionState != null &&
                version.appVersionState!.isNotEmpty) ...[
              const SizedBox(height: 4),
              _Field(label: l10n.fieldState, value: version.appVersionState!),
            ],
            if (version.releaseType != null &&
                version.releaseType!.isNotEmpty) ...[
              const SizedBox(height: 4),
              _Field(label: l10n.fieldRelease, value: version.releaseType!),
            ],
            if (version.createdDate != null &&
                version.createdDate!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                version.createdDate!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The version string when present, falling back to a generic label.
  String _versionLabel(AppLocalizations l10n) {
    final string = version.versionString;
    if (string != null && string.isNotEmpty) return string;
    return l10n.versionFallback;
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        Expanded(
          child: Text(value, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}
