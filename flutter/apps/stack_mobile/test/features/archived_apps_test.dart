import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_mobile/features/apps/archived_apps_screen.dart';
import 'package:stack_mobile/theme/app_theme.dart';

import '../support/fakes.dart';

const _accountId = 'acc-1';

const _apps = [
  AppInfo(id: 'app-1', name: 'Aurora', bundleId: 'com.example.aurora'),
  AppInfo(id: 'app-2', name: 'Borealis', bundleId: 'com.example.borealis'),
];

String _flagsBlob({
  required String appId,
  bool isFavorite = false,
  bool isArchived = false,
}) =>
    jsonEncode({
      'accountId': _accountId,
      'appId': appId,
      'isFavorite': isFavorite,
      'isArchived': isArchived,
    });

/// Pumps the archived-apps screen for a pre-seeded account.
Future<void> _pumpArchived(
  WidgetTester tester, {
  required CoreGateway gateway,
  required FakeBlobCache blobCache,
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

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const ArchivedAppsScreen(accountId: _accountId),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountsStoreProvider.overrideWithValue(accountsStore),
        blobCacheProvider.overrideWithValue(blobCache),
        secretStoreProvider.overrideWithValue(secretStore),
        coreGatewayProvider.overrideWithValue(gateway),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
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
  testWidgets('lists only archived apps', (tester) async {
    final blobCache = FakeBlobCache();
    // Archive Aurora only.
    await blobCache.save(
      kAppFlagsBlobType,
      '$_accountId.app-1',
      _flagsBlob(appId: 'app-1', isArchived: true),
    );

    await _pumpArchived(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
      blobCache: blobCache,
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Aurora'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Borealis'), findsNothing);
  });

  testWidgets('empty state when nothing is archived', (tester) async {
    await _pumpArchived(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
      blobCache: FakeBlobCache(),
    );
    await tester.pumpAndSettle();

    expect(find.text('No archived apps.'), findsOneWidget);
  });

  testWidgets('unarchive removes the app from the archived list',
      (tester) async {
    final blobCache = FakeBlobCache();
    await blobCache.save(
      kAppFlagsBlobType,
      '$_accountId.app-1',
      _flagsBlob(appId: 'app-1', isArchived: true),
    );

    await _pumpArchived(
      tester,
      gateway: ConfigurableFakeCoreGateway(appsToSync: _apps),
      blobCache: blobCache,
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Aurora'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unarchive').last);
    await tester.pumpAndSettle();

    // Aurora is no longer archived → leaves the archived list.
    expect(find.widgetWithText(ListTile, 'Aurora'), findsNothing);
    expect(find.text('Unarchived'), findsOneWidget); // SnackBar
  });
}
