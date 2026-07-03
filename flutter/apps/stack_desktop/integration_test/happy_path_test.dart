import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'package:stack_desktop/app.dart';

import '../test/support/fakes.dart';

/// End-to-end happy path driven through the real Fluent master-detail shell:
/// add account → apps list → app detail → reviews → reply.
///
/// The gateway is the scripted in-memory fake (the "stubbed network") and the
/// host stores are in-memory, so no dylib is loaded and no network is hit. It
/// runs on the host under `flutter test integration_test/` and on a device with
/// no host-only paths.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('add account → apps → reviews → reply', (tester) async {
    final gateway = ConfigurableFakeCoreGateway(
      appsToSync: const [
        AppInfo(id: 'app-1', name: 'Aurora', bundleId: 'com.example.aurora'),
      ],
      reviewsByApp: const {
        'app-1': [
          CustomerReview(
            id: 'rev-1',
            rating: 5,
            title: 'Fantastic',
            body: 'Daily driver',
            reviewerNickname: 'Sam',
          ),
        ],
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsStoreProvider.overrideWithValue(FakeAccountsStore()),
          blobCacheProvider.overrideWithValue(FakeBlobCache()),
          secretStoreProvider.overrideWithValue(FakeSecretStore()),
          coreGatewayProvider.overrideWithValue(gateway),
        ],
        child: const StackDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 1) Empty placeholder → open the add-account form via the footer command.
    expect(
      find.textContaining('No accounts yet'),
      findsOneWidget,
    );
    await tester.tap(find.text('Add account').last);
    await tester.pumpAndSettle();

    // 2) Fill the form and connect.
    final boxes = find.byType(TextBox);
    await tester.enterText(boxes.at(0), 'My Company');
    await tester.enterText(boxes.at(1), 'KEY123');
    await tester.enterText(boxes.at(2), 'ISSUER123');
    await tester.enterText(boxes.at(3), 'PRIVATE-KEY');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();

    // 3) The account now appears as a nav item → select it to view its apps.
    expect(find.text('My Company'), findsOneWidget);
    await tester.tap(find.text('My Company'));
    await tester.pumpAndSettle();

    // 4) Apps list shows the synced app → open its detail.
    expect(find.text('Aurora'), findsOneWidget);
    await tester.tap(find.text('Aurora'));
    await tester.pumpAndSettle();

    // 5) App detail → open Ratings & Reviews.
    expect(find.text('Ratings & Reviews'), findsOneWidget);
    await tester.tap(find.text('Ratings & Reviews'));
    await tester.pumpAndSettle();

    // 6) Reviews list shows the seeded review without a response yet.
    expect(find.text('Fantastic'), findsOneWidget);
    expect(find.text('Developer response'), findsNothing);

    // 7) Reply to the review through the Fluent ContentDialog.
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox), 'Thank you!');
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    // 8) The reply was sent and the developer response now shows.
    expect(gateway.replyCalls, hasLength(1));
    expect(gateway.replyCalls.single.reviewId, 'rev-1');
    expect(gateway.replyCalls.single.body, 'Thank you!');
    expect(find.text('Developer response'), findsOneWidget);
    expect(find.text('Thank you!'), findsOneWidget);

    // The success InfoBar auto-dismisses on a Timer; flush it before teardown.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
