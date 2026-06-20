import 'package:flutter_test/flutter_test.dart';
// `ExternalLibrary` (host-path dylib loader) lives in the for-generated API.
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_desktop/app.dart';

/// Absolute path to the host (macOS) dylib built with:
///   cargo build -p stack_core --features frb
const _hostDylibPath =
    '/Users/rubensmachion/repos/Open/stack-connect-core/target/debug/libstack_core.dylib';

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(_hostDylibPath),
    );
  });

  tearDownAll(() {
    RustLib.dispose();
  });

  testWidgets('home renders services from the FRB binding via Riverpod',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: StackDesktopApp()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('App Store Connect'), findsOneWidget);
  });
}
