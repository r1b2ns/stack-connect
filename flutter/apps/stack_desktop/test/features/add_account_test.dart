import 'dart:typed_data';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_desktop/features/accounts/add_account_pane.dart';
import 'package:stack_desktop/theme/app_theme.dart';

import '../support/fakes.dart';

/// A [FileSelectorPlatform] that returns canned bytes for `openFile`, so the
/// `.scexport` pick → decrypt → persist path is drivable in a widget test
/// (the real picker shows an OS dialog that can't be exercised headlessly).
class _FakeFileSelector extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  _FakeFileSelector(this._bytes, this._name);

  final Uint8List _bytes;
  final String _name;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async =>
      XFile.fromData(_bytes, name: _name);
}

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

/// Finds the Form tab's TextBoxes only.
///
/// The dialog now hosts both tabs in a [TabView]; its body is a lazily-built
/// `PageView`, so the Import tab's password box may also be in the tree. Scoping
/// to the descendants of the [InfoLabel] whose `label` is `'Label'` is overkill,
/// so instead we resolve the form boxes by their owning [InfoLabel] labels,
/// which are unique to the Form tab.
Finder _formBoxFor(String infoLabel) => find.descendant(
      of: find.widgetWithText(InfoLabel, infoLabel),
      matching: find.byType(TextBox),
    );

/// Fills label + the three credential fields and taps Connect.
Future<void> _fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(_formBoxFor('Label'), 'My Company');
  await tester.enterText(_formBoxFor('Key ID'), 'KEY123');
  await tester.enterText(_formBoxFor('Issuer ID'), 'ISSUER123');
  await tester.enterText(_formBoxFor('Private key (.p8)'), 'PRIVATE-KEY');
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

  testWidgets(
    'Import tab renders its controls and Import is disabled until ready',
    (tester) async {
      final gateway = ConfigurableFakeCoreGateway();
      await _pumpAddAccount(tester, gateway: gateway);

      // Switch to the Import tab via its tab-strip label.
      await tester.tap(find.text('Import .scexport'));
      await tester.pumpAndSettle();

      // Controls: the file-picker button, the Password field, and Import.
      expect(
        find.widgetWithText(Button, 'Select .scexport file'),
        findsOneWidget,
      );
      expect(find.widgetWithText(InfoLabel, 'Password'), findsOneWidget);

      final importButton = find.widgetWithText(FilledButton, 'Import');
      expect(importButton, findsOneWidget);
      // With no file picked and no password, Import is disabled.
      expect(
        tester.widget<FilledButton>(importButton).onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'wrong .scexport password surfaces the auth error and persists nothing',
    (tester) async {
      // Decrypt throws StackError.auth, mirroring a wrong export password.
      final gateway = ConfigurableFakeCoreGateway(
        decryptError: const StackError.auth(message: 'bad password'),
      );
      FileSelectorPlatform.instance = _FakeFileSelector(
        Uint8List.fromList(const [1, 2, 3]),
        'export.scexport',
      );
      final (:store, :container) =
          await _pumpAddAccount(tester, gateway: gateway);

      await tester.tap(find.text('Import .scexport'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(Button, 'Select .scexport file'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.widgetWithText(InfoLabel, 'Password'),
          matching: find.byType(TextBox),
        ),
        'wrong-password',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Authentication failed: bad password'),
        findsOneWidget,
      );
      // The modal stays open and nothing was persisted.
      expect(find.widgetWithText(FilledButton, 'Import'), findsOneWidget);
      expect(await store.all(), isEmpty);
    },
  );

  testWidgets(
    'successful .scexport import decrypts then persists the account',
    (tester) async {
      // The decrypt yields an Apple export whose credentials are already keyed
      // to the App Store Connect schema, so they flow straight to addAccount.
      final gateway = ConfigurableFakeCoreGateway(
        decryptResult: const AccountExport(
          name: 'Imported Co',
          providerType: 'apple',
          credentials: {
            'keyId': 'KEY123',
            'issuerId': 'ISSUER123',
            'privateKeyP8': 'PRIVATE-KEY',
          },
        ),
      );
      FileSelectorPlatform.instance = _FakeFileSelector(
        Uint8List.fromList(const [1, 2, 3]),
        'export.scexport',
      );
      final (:store, :container) =
          await _pumpAddAccount(tester, gateway: gateway);

      await tester.tap(find.text('Import .scexport'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(Button, 'Select .scexport file'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.widgetWithText(InfoLabel, 'Password'),
          matching: find.byType(TextBox),
        ),
        'correct-password',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      // The account is persisted under the export's name and the modal pops.
      final records = await store.all();
      expect(records, hasLength(1));
      expect(records.single.label, 'Imported Co');
      expect(records.single.kind, ServiceKind.appStoreConnect);
      expect(find.widgetWithText(FilledButton, 'Import'), findsNothing);
    },
  );

  testWidgets(
    'non-Apple .scexport is rejected and persists nothing',
    (tester) async {
      final gateway = ConfigurableFakeCoreGateway(
        decryptResult: const AccountExport(
          name: 'A Firebase Project',
          providerType: 'firebase',
          credentials: {'serviceAccount': '{}'},
        ),
      );
      FileSelectorPlatform.instance = _FakeFileSelector(
        Uint8List.fromList(const [1, 2, 3]),
        'export.scexport',
      );
      final (:store, :container) =
          await _pumpAddAccount(tester, gateway: gateway);

      await tester.tap(find.text('Import .scexport'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(Button, 'Select .scexport file'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.widgetWithText(InfoLabel, 'Password'),
          matching: find.byType(TextBox),
        ),
        'correct-password',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Only App Store Connect accounts can be imported.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Import'), findsOneWidget);
      expect(await store.all(), isEmpty);
    },
  );
}
