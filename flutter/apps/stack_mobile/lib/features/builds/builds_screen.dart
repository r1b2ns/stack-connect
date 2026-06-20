import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/stack_error_message.dart';

/// TestFlight Builds for a single (account, app).
///
/// Lists each build (marketing + build version, processing state, external /
/// internal build state, upload date, and an expired flag), newest first. This
/// is a read-only slice: it surfaces the builds but offers no mutations.
class BuildsScreen extends ConsumerWidget {
  const BuildsScreen({
    required this.accountId,
    required this.appId,
    super.key,
  });

  final String accountId;
  final String appId;

  BuildsKey get _key => (accountId: accountId, appId: appId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final builds = ref.watch(buildsControllerProvider(_key));

    return Scaffold(
      appBar: AppBar(
        title: const Text('TestFlight Builds'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/accounts/$accountId/apps/$appId'),
        ),
      ),
      body: builds.when(
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
            ? const Center(child: Text('No builds yet.'))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _BuildCard(buildInfo: items[index]),
              ),
      ),
    );
  }
}

class _BuildCard extends StatelessWidget {
  const _BuildCard({required this.buildInfo});

  final BuildInfo buildInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                    _versionLabel,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (buildInfo.expired == true)
                  _Pill(
                    label: 'Expired',
                    color: theme.colorScheme.error,
                  ),
              ],
            ),
            if (buildInfo.processingState != null &&
                buildInfo.processingState!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _Field(label: 'Processing', value: buildInfo.processingState!),
            ],
            if (buildInfo.externalBuildState != null &&
                buildInfo.externalBuildState!.isNotEmpty) ...[
              const SizedBox(height: 4),
              _Field(label: 'External', value: buildInfo.externalBuildState!),
            ],
            if (buildInfo.internalBuildState != null &&
                buildInfo.internalBuildState!.isNotEmpty) ...[
              const SizedBox(height: 4),
              _Field(label: 'Internal', value: buildInfo.internalBuildState!),
            ],
            if (buildInfo.uploadedDate != null &&
                buildInfo.uploadedDate!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                buildInfo.uploadedDate!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "1.2.0 (45)" when both are present, falling back to whichever exists.
  String get _versionLabel {
    final marketing = buildInfo.marketingVersion;
    final number = buildInfo.version;
    if (marketing != null && marketing.isNotEmpty) {
      return number != null && number.isNotEmpty
          ? '$marketing ($number)'
          : marketing;
    }
    if (number != null && number.isNotEmpty) return 'Build $number';
    return 'Build';
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
