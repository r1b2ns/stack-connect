import 'package:fluent_ui/fluent_ui.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

/// Fluent home: lists the services reported by the Rust core through the
/// shared [availableServicesProvider]. Intentionally a Fluent-idiom UI, distinct
/// from the Material mobile screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(availableServicesProvider);

    return ScaffoldPage(
      header: const PageHeader(title: Text('Stack Connect')),
      content: services.when(
        loading: () => const Center(child: ProgressRing()),
        error: (error, _) => Center(
          child: InfoBar(
            title: const Text('Failed to load services'),
            content: Text('$error'),
            severity: InfoBarSeverity.error,
          ),
        ),
        data: (items) => ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final service = items[index];
            return ListTile(
              leading: const Icon(FluentIcons.cloud),
              title: Text(service.label),
            );
          },
        ),
      ),
    );
  }
}

/// Human-readable label for a [ServiceKind] in the Fluent UI.
extension on ServiceKind {
  String get label => switch (this) {
        ServiceKind.appStoreConnect => 'App Store Connect',
      };
}
