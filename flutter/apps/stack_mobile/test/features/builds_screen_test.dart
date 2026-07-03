import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_mobile/features/builds/builds_screen.dart';
import 'package:stack_mobile/theme/app_theme.dart';

import '../support/fakes.dart';

const _accountId = 'acc-1';
const _appId = 'app-1';

const _builds = [
  BuildInfo(
    id: 'build-1',
    appId: _appId,
    version: '45',
    marketingVersion: '1.2.0',
    processingState: 'VALID',
    externalBuildState: 'READY_FOR_BETA_SUBMISSION',
    internalBuildState: 'IN_BETA_TESTING',
    expired: false,
  ),
];

/// Pumps just the builds screen for a pre-seeded account, with the host stores +
/// gateway overridden. A minimal router is used so any `context.go` calls in the
/// screen resolve.
Future<void> _pumpBuilds(
  WidgetTester tester, {
  Map<String, List<BuildInfo>> buildsByApp = const {_appId: _builds},
  bool exposesBuilds = true,
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
    buildsByApp: buildsByApp,
    exposesBuilds: exposesBuilds,
  );

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const BuildsScreen(
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
  testWidgets('renders a build (version, states) after load', (tester) async {
    await _pumpBuilds(tester);
    await tester.pumpAndSettle();

    expect(find.text('1.2.0 (45)'), findsOneWidget);
    expect(find.text('VALID'), findsOneWidget);
    expect(find.text('READY_FOR_BETA_SUBMISSION'), findsOneWidget);
    expect(find.text('IN_BETA_TESTING'), findsOneWidget);
    expect(find.text('No builds yet.'), findsNothing);
  });

  testWidgets('shows the empty state when there are no builds', (tester) async {
    await _pumpBuilds(tester, buildsByApp: const {});
    await tester.pumpAndSettle();

    expect(find.text('No builds yet.'), findsOneWidget);
  });
}
