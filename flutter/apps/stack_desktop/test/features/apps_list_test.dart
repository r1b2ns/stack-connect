import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_desktop/features/apps/apps_pane.dart';
import 'package:stack_desktop/features/apps/widgets/app_icon.dart';
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
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          FluentLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
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

  testWidgets('each row renders an AppIcon for its app', (tester) async {
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
    );
    await tester.pumpAndSettle();

    // One AppIcon (resolver + placeholder/network) per app row.
    expect(find.byType(AppIcon), findsNWidgets(_apps.length));
    // With no build seeded, the icon resolves to null → the cube placeholder.
    expect(find.byIcon(FluentIcons.cube_shape), findsNWidgets(_apps.length));
  });

  testWidgets('each row shows always-visible star + archive trailing buttons',
      (tester) async {
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
    );
    await tester.pumpAndSettle();

    // No favorites yet: every row carries the outline star and an archive
    // glyph. Scope to the rows so the toolbar's "Archived" command bar button
    // (also an archive glyph) does not inflate the count.
    for (final name in ['Aurora', 'Borealis']) {
      final row = find.widgetWithText(ListTile, name);
      expect(
        find.descendant(of: row, matching: find.byIcon(FluentIcons.favorite_star)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.byIcon(FluentIcons.archive)),
        findsOneWidget,
      );
    }
  });

  testWidgets('tapping the star favorites the app and promotes it to the top',
      (tester) async {
    final blobCache = FakeBlobCache();
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
      blobCache: blobCache,
    );
    await tester.pumpAndSettle();

    // Favorite the second app (Borealis) via its star button.
    final borealisStar = find.descendant(
      of: find.widgetWithText(ListTile, 'Borealis'),
      matching: find.byIcon(FluentIcons.favorite_star),
    );
    await tester.tap(borealisStar);
    await tester.pump(); // apply the optimistic state + show the toast

    // A "Favorites" section header appears and the row now shows the filled
    // star.
    expect(find.text('Favorites'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Borealis'),
        matching: find.byIcon(FluentIcons.favorite_star_fill),
      ),
      findsOneWidget,
    );

    // The flag was persisted to the app_flags blob (NOT the app blob).
    final flagBlob =
        await blobCache.fetch(kAppFlagsBlobType, '$_accountId.app-2');
    expect(flagBlob, isNotNull);

    // Drain the auto-dismiss InfoBar timer so no timer outlives the test.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('tapping archive removes the app from the active list',
      (tester) async {
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
    );
    await tester.pumpAndSettle();

    final auroraArchive = find.descendant(
      of: find.widgetWithText(ListTile, 'Aurora'),
      matching: find.byIcon(FluentIcons.archive),
    );
    await tester.tap(auroraArchive);
    await tester.pump(); // apply the optimistic state + show the toast

    // Aurora left the active list; Borealis remains.
    expect(find.widgetWithText(ListTile, 'Aurora'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Borealis'), findsOneWidget);

    // Drain the auto-dismiss InfoBar timer so no timer outlives the test.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('renders Portuguese copy when the locale is forced to pt',
      (tester) async {
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
      locale: const Locale('pt'),
    );
    await tester.pumpAndSettle();

    // "Archived" -> "Arquivado" (the toolbar command label) is a real pt-BR
    // value from the iOS catalog, so it proves pt resolution end-to-end.
    expect(find.text('Arquivado'), findsOneWidget);
    expect(find.text('Archived'), findsNothing);
  });

  testWidgets('renders Spanish copy when the locale is forced to es',
      (tester) async {
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
      locale: const Locale('es'),
    );
    await tester.pumpAndSettle();

    // "Archived" -> "Archivada" is a real es value from the iOS catalog.
    expect(find.text('Archivada'), findsOneWidget);
    expect(find.text('Archived'), findsNothing);
  });

  testWidgets('renders Japanese copy when the locale is forced to ja',
      (tester) async {
    await _pumpApps(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
      locale: const Locale('ja'),
    );
    await tester.pumpAndSettle();

    // "Apps" -> "アプリ" and "Archived" -> "アーカイブ済み" are real ja catalog
    // values, proving ja resolution end-to-end.
    expect(find.text('アプリ'), findsOneWidget);
    expect(find.text('アーカイブ済み'), findsOneWidget);
  });

  testWidgets(
      'pumps the pane under every supported locale without a '
      'FluentLocalizations assert', (tester) async {
    // Guards the desktop Fluent gotcha: a supportedLocale whose language Fluent
    // cannot resolve would throw. Building under each proves none do.
    for (final locale in AppLocalizations.supportedLocales) {
      await _pumpApps(
        tester,
        gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
        locale: locale,
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'building the pane under $locale should not throw',
      );
      // Both app rows always render regardless of locale.
      expect(find.text('Aurora'), findsOneWidget);
    }
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
