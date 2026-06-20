import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_desktop/features/apps/apps_pane.dart';
import 'package:stack_desktop/theme/app_theme.dart';

import '../support/fakes.dart';

const _accountId = 'acc-1';

const _apps = [
  AppInfo(id: 'app-1', name: 'Aurora', bundleId: 'com.example.aurora'),
  AppInfo(
    id: 'app-2',
    name: 'Borealis',
    bundleId: 'com.example.borealis',
    platform: 'IOS',
  ),
];

/// Pumps the apps pane for a pre-seeded account inside a [FluentApp] ancestor
/// (ScaffoldPage / InfoBar require it), with the host stores + gateway
/// overridden.
Future<void> _pumpApps(
  WidgetTester tester, {
  required CoreGateway gateway,
  BlobCache? blobCache,
}) async {
  final accountsStore = FakeAccountsStore()
    ..upsert(
      const AccountRecord(
        id: _accountId,
        kind: ServiceKind.appStoreConnect,
        label: 'My Company',
      ),
    );
  final secretStore = FakeSecretStore();
  await secretStore.setSecret(_accountId, 'keyId', 'k');
  await secretStore.setSecret(_accountId, 'issuerId', 'i');
  await secretStore.setSecret(_accountId, 'privateKey', 'p');

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountsStoreProvider.overrideWithValue(accountsStore),
        blobCacheProvider.overrideWithValue(blobCache ?? FakeBlobCache()),
        secretStoreProvider.overrideWithValue(secretStore),
        coreGatewayProvider.overrideWithValue(gateway),
      ],
      child: FluentApp(
        theme: AppTheme.light(),
        home: const AppsPane(accountId: _accountId),
      ),
    ),
  );
}

void main() {
  testWidgets('renders both apps (name + bundleId) after sync', (tester) async {
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aurora'), findsOneWidget);
    expect(find.text('com.example.aurora'), findsOneWidget);
    expect(find.text('Borealis'), findsOneWidget);
    expect(find.text('com.example.borealis · IOS'), findsOneWidget);
  });

  testWidgets('shows a progress ring while the initial load is in flight',
      (tester) async {
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
      blobCache: _SlowBlobCache(),
    );
    await tester.pump();
    expect(find.byType(ProgressRing), findsOneWidget);

    await tester.pumpAndSettle(const Duration(milliseconds: 80));
    expect(find.text('Aurora'), findsOneWidget);
  });

  testWidgets('shows the mapped error when the sync fails', (tester) async {
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(
        connectError: const StackError.network(message: 'offline'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Network error'), findsOneWidget);
  });
}

/// A blob cache whose reads resolve only after a delay, so the controller's
/// initial AsyncLoading state is observable for a frame.
class _SlowBlobCache extends FakeBlobCache {
  @override
  Future<List<CachedBlob>> fetchAll(String typeName) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return super.fetchAll(typeName);
  }
}
