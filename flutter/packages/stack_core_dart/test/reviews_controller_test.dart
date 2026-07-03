import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'support/fakes.dart';

void main() {
  const accountId = 'acct-1';
  const appId = 'app-1';
  const key = (accountId: accountId, appId: appId);

  late MockCoreGateway gateway;
  late FakeAccountsStore accounts;
  late FakeSecretStore secrets;
  late FakeBlobCache blobs;
  late MockFrbProvider provider;
  late MockFrbReviews reviews;

  setUpAll(() {
    registerFallbackValue(MockFrbProvider());
    registerFallbackValue(MockFrbReviews());
    registerFallbackValue(ServiceKind.appStoreConnect);
  });

  setUp(() async {
    gateway = MockCoreGateway();
    accounts = FakeAccountsStore();
    secrets = FakeSecretStore();
    blobs = FakeBlobCache();
    provider = MockFrbProvider();
    reviews = MockFrbReviews();

    await accounts.upsert(
      const AccountRecord(
        id: accountId,
        kind: ServiceKind.appStoreConnect,
        label: 'Acme',
      ),
    );

    when(() => gateway.credentialSchema(any())).thenReturn(const []);
    when(() => gateway.connect(
          kind: any(named: 'kind'),
          accountId: any(named: 'accountId'),
          credentials: any(named: 'credentials'),
        )).thenAnswer((_) async => provider);
    when(() => gateway.reviews(any())).thenReturn(reviews);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        coreGatewayProvider.overrideWithValue(gateway),
        accountsStoreProvider.overrideWithValue(accounts),
        secretStoreProvider.overrideWithValue(secrets),
        blobCacheProvider.overrideWithValue(blobs),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('build loads reviews via the connected provider', () async {
    when(() => gateway.fetchCustomerReviews(any(), any())).thenAnswer(
      (_) async => const [
        CustomerReview(id: 'r1', rating: 5, title: 'Great'),
      ],
    );

    final container = makeContainer();
    final result =
        await container.read(reviewsControllerProvider(key).future);

    expect(result, hasLength(1));
    expect(result.single.id, 'r1');
    verify(() => gateway.fetchCustomerReviews(reviews, appId)).called(1);
  });

  test('reply calls the gateway and invalidates so it re-fetches', () async {
    var fetchCount = 0;
    when(() => gateway.fetchCustomerReviews(any(), any())).thenAnswer((_) async {
      fetchCount++;
      // First load: no response. After reply+invalidate: has a response.
      return [
        CustomerReview(
          id: 'r1',
          rating: 5,
          response: fetchCount >= 2
              ? const ReviewResponse(id: 'resp-1', body: 'thanks')
              : null,
        ),
      ];
    });
    when(() => gateway.replyToReview(
          any(),
          reviewId: any(named: 'reviewId'),
          body: any(named: 'body'),
        )).thenAnswer(
      (_) async => const ReviewResponse(id: 'resp-1', body: 'thanks'),
    );

    final container = makeContainer();
    final notifier = reviewsControllerProvider(key);

    final first = await container.read(notifier.future);
    expect(first.single.response, isNull);
    expect(fetchCount, 1);

    final response = await container
        .read(notifier.notifier)
        .reply(reviewId: 'r1', body: 'thanks');
    expect(response.id, 'resp-1');
    verify(() => gateway.replyToReview(reviews,
        reviewId: 'r1', body: 'thanks')).called(1);

    // invalidateSelf triggers a re-fetch on the next read.
    final refreshed = await container.read(notifier.future);
    expect(fetchCount, 2, reason: 'reply should invalidate and re-fetch');
    expect(refreshed.single.response?.id, 'resp-1');
  });

  test('build returns empty when the provider exposes no reviews', () async {
    when(() => gateway.reviews(any())).thenReturn(null);

    final container = makeContainer();
    final result =
        await container.read(reviewsControllerProvider(key).future);

    expect(result, isEmpty);
    verifyNever(() => gateway.fetchCustomerReviews(any(), any()));
  });
}
