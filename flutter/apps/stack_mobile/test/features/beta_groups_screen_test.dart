import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_mobile/features/beta_groups/beta_groups_screen.dart';
import 'package:stack_mobile/theme/app_theme.dart';

import '../support/fakes.dart';

const _accountId = 'acc-1';
const _appId = 'app-1';

const _betaGroups = [
  BetaGroupInfo(
    id: 'group-1',
    appId: _appId,
    name: 'Internal Testers',
    createdDate: '2026-06-20',
    isInternalGroup: true,
    hasAccessToAllBuilds: true,
    publicLinkEnabled: false,
    feedbackEnabled: true,
  ),
];

/// Pumps just the beta groups screen for a pre-seeded account, with the host
/// stores + gateway overridden. A minimal router is used so any `context.go`
/// calls in the screen resolve.
Future<void> _pumpBetaGroups(
  WidgetTester tester, {
  Map<String, List<BetaGroupInfo>> betaGroupsByApp = const {
    _appId: _betaGroups,
  },
  bool exposesBetaGroups = true,
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
    betaGroupsByApp: betaGroupsByApp,
    exposesBetaGroups: exposesBetaGroups,
  );

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const BetaGroupsScreen(
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
  testWidgets('renders a beta group (name, kind, flags) after load',
      (tester) async {
    await _pumpBetaGroups(tester);
    await tester.pumpAndSettle();

    expect(find.text('Internal Testers'), findsOneWidget);
    expect(find.text('Internal'), findsOneWidget);
    expect(find.text('No beta groups yet.'), findsNothing);
  });

  testWidgets('shows the empty state when there are no beta groups',
      (tester) async {
    await _pumpBetaGroups(tester, betaGroupsByApp: const {});
    await tester.pumpAndSettle();

    expect(find.text('No beta groups yet.'), findsOneWidget);
  });
}
