import 'package:flutter_test/flutter_test.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_mobile/app.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('app builds and shows the empty accounts state', (tester) async {
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
        child: const StackMobileApp(),
      ),
    );
    // Let the accounts AsyncNotifier resolve its initial (empty) list.
    await tester.pumpAndSettle();

    // The Accounts home renders its empty state, proving the widget tree and
    // the host overrides wire up. ("Accounts" appears twice — app bar title and
    // nav bar label — so assert on the empty-state copy instead.)
    expect(find.text('No accounts yet'), findsOneWidget);
    expect(find.text('Add account'), findsWidgets);
  });
}
