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
  late MockFrbBetaGroups groups;

  setUpAll(() {
    registerFallbackValue(MockFrbProvider());
    registerFallbackValue(MockFrbBetaGroups());
    registerFallbackValue(ServiceKind.appStoreConnect);
  });

  setUp(() async {
    gateway = MockCoreGateway();
    accounts = FakeAccountsStore();
    secrets = FakeSecretStore();
    blobs = FakeBlobCache();
    provider = MockFrbProvider();
    groups = MockFrbBetaGroups();

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
    when(() => gateway.betaGroups(any())).thenReturn(groups);
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

  test('build loads beta groups via the connected provider', () async {
    when(() => gateway.fetchBetaGroups(any(), any())).thenAnswer(
      (_) async => const [
        BetaGroupInfo(id: 'g1', appId: appId, name: 'Internal Testers'),
      ],
    );

    final container = makeContainer();
    final result =
        await container.read(betaGroupsControllerProvider(key).future);

    expect(result, hasLength(1));
    expect(result.single.id, 'g1');
    verify(() => gateway.fetchBetaGroups(groups, appId)).called(1);
  });

  test('build returns empty when the provider exposes no beta groups',
      () async {
    when(() => gateway.betaGroups(any())).thenReturn(null);

    final container = makeContainer();
    final result =
        await container.read(betaGroupsControllerProvider(key).future);

    expect(result, isEmpty);
    verifyNever(() => gateway.fetchBetaGroups(any(), any()));
  });
}
