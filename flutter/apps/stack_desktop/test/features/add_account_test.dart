import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_desktop/features/accounts/add_account_pane.dart';
import 'package:stack_desktop/theme/app_theme.dart';

import '../support/fakes.dart';

/// Pumps a tiny host whose single button opens the add-account modal via
/// [showAddAccountDialog], then taps it so the real `showDialog`/`Navigator.pop`
/// flow is exercised end-to-end. The host stores + gateway are overridden so the
/// modal runs without a dylib or network. Returns the [FakeAccountsStore] and the
/// [ProviderContainer] so tests can assert on persistence.
///
/// The dialog is opened from a host button (rather than pumping the widget
/// directly) so the test covers the same `showDialog` entry point the shell uses
/// and the success-path `Navigator.pop` that dismisses the modal.
Future<({FakeAccountsStore store, ProviderContainer container})> _pumpAddAccount(
  WidgetTester tester, {
  required ConfigurableFakeCoreGateway gateway,
}) async {
  final accountsStore = FakeAccountsStore();
  final container = ProviderContainer(
    overrides: [
      accountsStoreProvider.overrideWithValue(accountsStore),
      blobCacheProvider.overrideWithValue(FakeBlobCache()),
      secretStoreProvider.overrideWithValue(FakeSecretStore()),
      coreGatewayProvider.overrideWithValue(gateway),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: FluentApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Button(
            child: const Text('open'),
            onPressed: () => showAddAccountDialog(context),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
  return (store: accountsStore, container: container);
}

/// Fills label + the three credential fields and taps Connect.
Future<void> _fillAndSubmit(WidgetTester tester) async {
  final boxes = find.byType(TextBox);
  // Box 0 = Label, 1 = Key ID, 2 = Issuer ID, 3 = Private key.
  await tester.enterText(boxes.at(0), 'My Company');
  await tester.enterText(boxes.at(1), 'KEY123');
  await tester.enterText(boxes.at(2), 'ISSUER123');
  await tester.enterText(boxes.at(3), 'PRIVATE-KEY');
  await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
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
      final (:store, :container) =
          await _pumpAddAccount(tester, gateway: gateway);

      await _fillAndSubmit(tester);

      // The mapped message is surfaced in the InfoBar; the modal stays open.
      expect(
        find.textContaining('Accept the App Store Connect agreements'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
      expect(await store.all(), isEmpty);
    },
  );

  testWidgets(
    'generic auth error is mapped and nothing is persisted',
    (tester) async {
      final gateway = ConfigurableFakeCoreGateway(
        connectError: const StackError.auth(message: 'bad token'),
      );
      final (:store, :container) =
          await _pumpAddAccount(tester, gateway: gateway);

      await _fillAndSubmit(tester);

      expect(
        find.textContaining('Authentication failed: bad token'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
      expect(await store.all(), isEmpty);
    },
  );

  testWidgets(
    'successful connect persists the account and closes the modal',
    (tester) async {
      final gateway = ConfigurableFakeCoreGateway();
      final (:store, :container) =
          await _pumpAddAccount(tester, gateway: gateway);

      await _fillAndSubmit(tester);

      // On success the modal pops itself and the account is persisted.
      final records = await store.all();
      expect(records, hasLength(1));
      expect(records.single.label, 'My Company');
      expect(records.single.kind, ServiceKind.appStoreConnect);
      // The ContentDialog popped, so Connect is no longer in the tree.
      expect(find.widgetWithText(FilledButton, 'Connect'), findsNothing);
    },
  );
}
