import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_mobile/features/apps/apps_screen.dart';
import 'package:stack_mobile/features/apps/widgets/app_icon.dart';
import 'package:stack_mobile/theme/app_theme.dart';

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

/// Pumps just the apps screen for a pre-seeded account, with the host stores +
/// gateway overridden. A minimal router is used so any `context.go` calls in the
/// screen resolve.
Future<void> _pumpApps(
  WidgetTester tester, {
  required CoreGateway gateway,
  BlobCache? blobCache,
  Locale? locale,
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
  // Seed credentials so connectedProviderProvider can build the handle.
  await secretStore.setSecret(_accountId, 'keyId', 'k');
  await secretStore.setSecret(_accountId, 'issuerId', 'i');
  await secretStore.setSecret(_accountId, 'privateKey', 'p');

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const AppsScreen(accountId: _accountId),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountsStoreProvider.overrideWithValue(accountsStore),
        blobCacheProvider.overrideWithValue(blobCache ?? FakeBlobCache()),
        secretStoreProvider.overrideWithValue(secretStore),
        coreGatewayProvider.overrideWithValue(gateway),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
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
    // platform is appended to the subtitle when present.
    expect(find.text('com.example.borealis · IOS'), findsOneWidget);
  });

  testWidgets('shows a spinner while the initial load is in flight',
      (tester) async {
    // The slow cache keeps AppsController.build pending, so the controller stays
    // in AsyncLoading and the screen paints the spinner.
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
      blobCache: _SlowBlobCache(),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Let the cache read + background sync resolve; the list then renders.
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

    expect(
      find.textContaining('Network error'),
      findsOneWidget,
    );
  });

  testWidgets('each row renders an AppIcon for its app', (tester) async {
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
    );
    await tester.pumpAndSettle();

    // One AppIcon per app row; with no build seeded the icon resolves to null
    // and the placeholder Icons.apps glyph is shown.
    expect(find.byType(AppIcon), findsNWidgets(_apps.length));
    expect(find.byIcon(Icons.apps), findsNWidgets(_apps.length));
  });

  testWidgets('favoriting via the row menu surfaces the Favorites header '
      'and persists a flag blob', (tester) async {
    final blobCache = FakeBlobCache();
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
      blobCache: blobCache,
    );
    await tester.pumpAndSettle();

    // Open the Borealis row's ⋮ menu and tap "Add to favorites".
    final borealisMenu = find.descendant(
      of: find.widgetWithText(ListTile, 'Borealis'),
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.tap(borealisMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to favorites').last);
    await tester.pumpAndSettle();

    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Added to favorites'), findsOneWidget); // SnackBar

    final flagBlob =
        await blobCache.fetch(kAppFlagsBlobType, '$_accountId.app-2');
    expect(flagBlob, isNotNull);
  });

  testWidgets('archiving via the row menu drops the app from the active list',
      (tester) async {
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
    );
    await tester.pumpAndSettle();

    final auroraMenu = find.descendant(
      of: find.widgetWithText(ListTile, 'Aurora'),
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.tap(auroraMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive').last);
    await tester.pumpAndSettle();

    // Aurora left the active list; Borealis remains.
    expect(find.widgetWithText(ListTile, 'Aurora'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Borealis'), findsOneWidget);
  });

  testWidgets('renders Portuguese empty-state copy when locale is forced to pt',
      (tester) async {
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: const []),
      locale: const Locale('pt'),
    );
    await tester.pumpAndSettle();

    // "No apps found for this account." -> the pt-BR value from the iOS
    // catalog, proving pt resolution end-to-end on mobile.
    expect(
      find.text('Nenhum app encontrado para esta conta.'),
      findsOneWidget,
    );
    expect(find.text('No apps found for this account.'), findsNothing);
  });

  testWidgets('renders Spanish copy when the locale is forced to es',
      (tester) async {
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: const []),
      locale: const Locale('es'),
    );
    await tester.pumpAndSettle();

    // Real es catalog values, proving es resolution end-to-end on mobile.
    expect(find.text('Apps'), findsOneWidget); // app bar title (es == "Apps")
    expect(
      find.text('No se encontraron apps para esta cuenta.'),
      findsOneWidget,
    );
  });

  testWidgets('renders Japanese copy when the locale is forced to ja',
      (tester) async {
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: const []),
      locale: const Locale('ja'),
    );
    await tester.pumpAndSettle();

    // "Apps" -> "アプリ" (app bar) and the empty state are real ja catalog
    // values, proving ja resolution end-to-end on mobile.
    expect(find.text('アプリ'), findsOneWidget);
    expect(find.text('このアカウントのアプリが見つかりません。'), findsOneWidget);
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
