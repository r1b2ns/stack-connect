import 'package:flutter/material.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

/// Material home: lists the services reported by the Rust core through the
/// shared [availableServicesProvider].
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(availableServicesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Stack Connect')),
      body: services.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load services: $error')),
        data: (items) => ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final service = items[index];
            return ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(service.label),
            );
          },
        ),
      ),
    );
  }
}

/// Human-readable label for a [ServiceKind] in the Material UI.
extension on ServiceKind {
  String get label => switch (this) {
        ServiceKind.appStoreConnect => 'App Store Connect',
      };
}
