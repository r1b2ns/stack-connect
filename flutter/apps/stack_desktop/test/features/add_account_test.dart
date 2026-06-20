import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_desktop/features/accounts/add_account_pane.dart';
import 'package:stack_desktop/features/shell/selection.dart';
import 'package:stack_desktop/theme/app_theme.dart';

import '../support/fakes.dart';

/// Pumps the add-account pane directly inside a [FluentApp] (the pane is a
/// `ScaffoldPage` and uses fluent widgets that require that ancestor), with the
/// host stores + gateway overridden. Returns the [FakeAccountsStore] and the
/// [ProviderContainer] so tests can assert on persistence and selection state.
///
/// The pane is pumped directly rather than through the `HomeShell`'s
/// `NavigationView` so the test exercises the form behaviour without coupling to
/// the shell's footer-index math.
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

  // Selecting the add-account view mirrors the shell driving the pane.
  container.read(selectionControllerProvider.notifier).openAddAccount();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: FluentApp(
        theme: AppTheme.light(),
        home: const AddAccountPane(),
      ),
    ),
  );
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

      // The mapped message is surfaced in the InfoBar; the form stays put.
      expect(
        find.textContaining('Accept the App Store Connect agreements'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
      expect(await store.all(), isEmpty);
      // Still on the add-account view (the form did not clear).
      expect(
        container.read(selectionControllerProvider).view,
        DetailView.addAccount,
      );
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
    'successful connect persists the account and clears the selection',
    (tester) async {
      final gateway = ConfigurableFakeCoreGateway();
      final (:store, :container) =
          await _pumpAddAccount(tester, gateway: gateway);

      await _fillAndSubmit(tester);

      // On success the pane clears the selection back to the placeholder and the
      // account is persisted.
      final records = await store.all();
      expect(records, hasLength(1));
      expect(records.single.label, 'My Company');
      expect(records.single.kind, ServiceKind.appStoreConnect);
      expect(
        container.read(selectionControllerProvider).view,
        DetailView.none,
      );
    },
  );
}
