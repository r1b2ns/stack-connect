import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_mobile/app.dart';

import '../support/fakes.dart';

/// Pumps the whole app under in-memory stores + a scripted gateway, then routes
/// to the add-account form. Returns the [FakeAccountsStore] so tests can assert
/// on what was (or was not) persisted.
Future<FakeAccountsStore> _pumpAddAccount(
  WidgetTester tester, {
  required ConfigurableFakeCoreGateway gateway,
}) async {
  final accountsStore = FakeAccountsStore();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountsStoreProvider.overrideWithValue(accountsStore),
        blobCacheProvider.overrideWithValue(FakeBlobCache()),
        secretStoreProvider.overrideWithValue(FakeSecretStore()),
        coreGatewayProvider.overrideWithValue(gateway),
      ],
      child: const StackMobileApp(),
    ),
  );
  await tester.pumpAndSettle();

  // Navigate to the add-account form (app bar action exists from empty state).
  await tester.tap(find.byTooltip('Add account').first);
  await tester.pumpAndSettle();
  expect(find.text('Connect'), findsOneWidget);
  return accountsStore;
}

/// Fills label + the three credential fields and taps Connect.
Future<void> _fillAndSubmit(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  // Field 0 = Label, 1 = Key ID, 2 = Issuer ID, 3 = Private key.
  await tester.enterText(fields.at(0), 'My Company');
  await tester.enterText(fields.at(1), 'KEY123');
  await tester.enterText(fields.at(2), 'ISSUER123');
  await tester.enterText(fields.at(3), 'PRIVATE-KEY');
  await tester.tap(find.text('Connect'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'pending-agreements validation error is shown and nothing is persisted',
    (tester) async {
      final gateway = ConfigurableFakeCoreGateway(
        validateError:
            const StackError.pendingAgreements(message: 'agreements pending'),
      );
      final store = await _pumpAddAccount(tester, gateway: gateway);

      await _fillAndSubmit(tester);

      // Mapped, user-facing message (not the raw error) is surfaced.
      expect(
        find.textContaining('Accept the App Store Connect agreements'),
        findsOneWidget,
      );
      // Form stayed put (still on the add-account screen) and no account
      // was committed.
      expect(find.text('Connect'), findsOneWidget);
      expect(await store.all(), isEmpty);
    },
  );

  testWidgets(
    'generic auth error is mapped and nothing is persisted',
    (tester) async {
      final gateway = ConfigurableFakeCoreGateway(
        connectError: const StackError.auth(message: 'bad token'),
      );
      final store = await _pumpAddAccount(tester, gateway: gateway);

      await _fillAndSubmit(tester);

      expect(
        find.textContaining('Authentication failed: bad token'),
        findsOneWidget,
      );
      expect(find.text('Connect'), findsOneWidget);
      expect(await store.all(), isEmpty);
    },
  );

  testWidgets(
    'successful connect persists the account and returns to the list',
    (tester) async {
      final gateway = ConfigurableFakeCoreGateway();
      final store = await _pumpAddAccount(tester, gateway: gateway);

      await _fillAndSubmit(tester);

      // Back on the accounts list, the new account row is shown.
      expect(find.text('My Company'), findsOneWidget);
      // And it was persisted.
      final records = await store.all();
      expect(records, hasLength(1));
      expect(records.single.label, 'My Company');
      expect(records.single.kind, ServiceKind.appStoreConnect);
    },
  );
}
