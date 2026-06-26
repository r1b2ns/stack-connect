import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_mobile/features/versions/versions_screen.dart';
import 'package:stack_mobile/theme/app_theme.dart';

import '../support/fakes.dart';

const _accountId = 'acc-1';
const _appId = 'app-1';

const _versions = [
  AppStoreVersionInfo(
    id: 'version-1',
    appId: _appId,
    platform: 'IOS',
    appStoreState: 'READY_FOR_SALE',
    appVersionState: 'COMPLETE',
    versionString: '1.2.0',
    releaseType: 'MANUAL',
    createdDate: '2026-06-20',
  ),
];

/// Pumps just the versions screen for a pre-seeded account, with the host stores
/// + gateway overridden. A minimal router is used so any `context.go` calls in
/// the screen resolve.
Future<void> _pumpVersions(
  WidgetTester tester, {
  Map<String, List<AppStoreVersionInfo>> versionsByApp = const {
    _appId: _versions,
  },
  bool exposesVersions = true,
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

  final gateway = ConfigurableFakeCoreGateway(
    versionsByApp: versionsByApp,
    exposesVersions: exposesVersions,
  );

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const VersionsScreen(
          accountId: _accountId,
          appId: _appId,
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountsStoreProvider.overrideWithValue(accountsStore),
        blobCacheProvider.overrideWithValue(FakeBlobCache()),
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
  testWidgets('renders a version (string, states) after load', (tester) async {
    await _pumpVersions(tester);
    await tester.pumpAndSettle();

    expect(find.text('1.2.0'), findsOneWidget);
    expect(find.text('READY_FOR_SALE'), findsOneWidget);
    expect(find.text('IOS'), findsOneWidget);
    expect(find.text('COMPLETE'), findsOneWidget);
    expect(find.text('No versions yet.'), findsNothing);
  });

  testWidgets('shows the empty state when there are no versions',
      (tester) async {
    await _pumpVersions(tester, versionsByApp: const {});
    await tester.pumpAndSettle();

    expect(find.text('No versions yet.'), findsOneWidget);
  });
}
