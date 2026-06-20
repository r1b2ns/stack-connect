import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

/// Basic app detail: name, bundle id, platform, and entry points to the app's
/// Ratings & Reviews, TestFlight Builds, and App Store Versions.
///
/// The [AppInfo] is sourced from the already-loaded apps list for the account
/// (no dedicated single-app endpoint exists in this slice's controller API).
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
    final apps = ref.watch(appsControllerProvider(accountId));
    final app = apps.valueOrNull?.where((a) => a.id == appId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(app?.name ?? 'App'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/accounts/$accountId/apps'),
        ),
      ),
      body: app == null
          ? const Center(child: Text('App not found.'))
          : ListView(
              children: [
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
