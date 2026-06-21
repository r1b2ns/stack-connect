import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app license text, loaded from the bundled `assets/LICENSE.txt`.
///
/// Surfaced as a [FutureProvider] so [LicenseDialog] can render a loading/error
/// state while [rootBundle] resolves the asset. Mirrors the iOS `LicenseView`,
/// which reads the same `LICENSE.txt` resource.
final _licenseTextProvider = FutureProvider<String>((ref) async {
  return rootBundle.loadString('assets/LICENSE.txt');
});

/// Read-only viewer for the app license, mirroring the iOS `LicenseView`.
///
/// The text is scrollable, selectable, and monospaced so the legal text reads
/// faithfully. Presented as a nested [ContentDialog] from the Settings modal's
/// About section, with a single "Close" action that pops back to Settings.
class LicenseDialog extends ConsumerWidget {
  const LicenseDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licenseAsync = ref.watch(_licenseTextProvider);

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
      title: const Text('License'),
      content: licenseAsync.when(
        loading: () => const Center(child: ProgressRing()),
        error: (error, _) =>
            Center(child: Text('Could not load the license text.\n$error')),
        data: (text) => SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New'],
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
