import 'package:flutter_test/flutter_test.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_desktop/app.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('app builds and shows the empty accounts detail', (tester) async {
    // No RustLib.init / dylib: the gateway is faked and the host stores are
    // in-memory, so this is a pure widget-tree smoke test.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsStoreProvider.overrideWithValue(FakeAccountsStore()),
          blobCacheProvider.overrideWithValue(FakeBlobCache()),
          secretStoreProvider.overrideWithValue(FakeSecretStore()),
          coreGatewayProvider.overrideWithValue(const FakeCoreGateway()),
        ],
        child: const StackDesktopApp(),
      ),
    );
    // Let the accounts AsyncNotifier resolve its initial (empty) list.
    await tester.pumpAndSettle();

    // The Fluent master-detail shell builds and lands on the Home dashboard
    // (the default selection), proving the widget tree and the host overrides
    // wire up.
    expect(find.text('No widgets yet'), findsOneWidget);
  });
}
