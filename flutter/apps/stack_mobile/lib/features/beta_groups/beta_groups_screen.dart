import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/stack_error_message.dart';

/// Beta Groups (TestFlight) for a single (account, app).
///
/// Lists each group (name, internal / external kind, and the useful access /
/// link / feedback flags plus creation date). This is a read-only slice: it
/// surfaces the groups but offers no mutations.
class BetaGroupsScreen extends ConsumerWidget {
  const BetaGroupsScreen({
    required this.accountId,
    required this.appId,
    super.key,
  });

  final String accountId;
  final String appId;

  BetaGroupsKey get _key => (accountId: accountId, appId: appId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(betaGroupsControllerProvider(_key));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beta Groups'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/accounts/$accountId/apps/$appId'),
        ),
      ),
      body: groups.when(
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
            ? const Center(child: Text('No beta groups yet.'))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _BetaGroupCard(group: items[index]),
              ),
      ),
    );
  }
}

class _BetaGroupCard extends StatelessWidget {
  const _BetaGroupCard({required this.group});

  final BetaGroupInfo group;

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
                    _nameLabel,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                _Pill(
                  label: group.isInternalGroup == true ? 'Internal' : 'External',
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
            if (group.hasAccessToAllBuilds != null) ...[
              const SizedBox(height: 8),
              _Field(
                label: 'All builds',
                value: _yesNo(group.hasAccessToAllBuilds),
              ),
            ],
            if (group.publicLinkEnabled != null) ...[
              const SizedBox(height: 4),
              _Field(
                label: 'Public link',
                value: _yesNo(group.publicLinkEnabled),
              ),
            ],
            if (group.feedbackEnabled != null) ...[
              const SizedBox(height: 4),
              _Field(
                label: 'Feedback',
                value: _yesNo(group.feedbackEnabled),
              ),
            ],
            if (group.createdDate != null &&
                group.createdDate!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                group.createdDate!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The group name when present, falling back to a generic label.
  String get _nameLabel {
    final name = group.name;
    if (name != null && name.isNotEmpty) return name;
    return 'Beta Group';
  }

  String _yesNo(bool? value) => value == true ? 'Yes' : 'No';
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
