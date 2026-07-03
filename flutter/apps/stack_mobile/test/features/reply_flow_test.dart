import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_mobile/features/reviews/reviews_screen.dart';
import 'package:stack_mobile/theme/app_theme.dart';

import '../support/fakes.dart';

const _accountId = 'acc-1';
const _appId = 'app-1';

const _reviews = [
  CustomerReview(
    id: 'rev-1',
    rating: 4,
    title: 'Great app',
    body: 'Love it',
    reviewerNickname: 'Sam',
  ),
];

Future<ConfigurableFakeCoreGateway> _pumpReviews(WidgetTester tester) async {
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
    reviewsByApp: const {_appId: _reviews},
  );

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const ReviewsScreen(
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
  await tester.pumpAndSettle();
  return gateway;
}

void main() {
  testWidgets(
    'replying calls the gateway and the developer response then shows',
    (tester) async {
      final gateway = await _pumpReviews(tester);

      // The review renders without a developer response yet.
      expect(find.text('Great app'), findsOneWidget);
      expect(find.text('Developer response'), findsNothing);
      expect(find.text('Reply'), findsOneWidget);

      // Open the reply dialog.
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(find.text('Reply to review'), findsOneWidget);

      // Enter the response body and submit.
      await tester.enterText(
        find.byType(TextField),
        'Thanks for the feedback!',
      );
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      // The gateway received the reply with the right args.
      expect(gateway.replyCalls, hasLength(1));
      expect(gateway.replyCalls.single.reviewId, 'rev-1');
      expect(gateway.replyCalls.single.body, 'Thanks for the feedback!');

      // The list re-fetched and the developer response is now shown.
      expect(find.text('Developer response'), findsOneWidget);
      expect(find.text('Thanks for the feedback!'), findsOneWidget);
      // The action label flips to "Edit reply" once a response exists.
      expect(find.text('Edit reply'), findsOneWidget);
    },
  );
}
