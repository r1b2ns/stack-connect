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
  late MockFrbBuilds builds;

  setUpAll(() {
    registerFallbackValue(MockFrbProvider());
    registerFallbackValue(MockFrbBuilds());
    registerFallbackValue(ServiceKind.appStoreConnect);
  });

  setUp(() async {
    gateway = MockCoreGateway();
    accounts = FakeAccountsStore();
    secrets = FakeSecretStore();
    blobs = FakeBlobCache();
    provider = MockFrbProvider();
    builds = MockFrbBuilds();

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
    when(() => gateway.builds(any())).thenReturn(builds);
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

  test('build loads builds via the connected provider', () async {
    when(() => gateway.fetchBuilds(any(), any())).thenAnswer(
      (_) async => const [
        BuildInfo(id: 'b1', appId: appId, version: '45'),
      ],
    );

    final container = makeContainer();
    final result =
        await container.read(buildsControllerProvider(key).future);

    expect(result, hasLength(1));
    expect(result.single.id, 'b1');
    verify(() => gateway.fetchBuilds(builds, appId)).called(1);
  });

  test('build returns empty when the provider exposes no builds', () async {
    when(() => gateway.builds(any())).thenReturn(null);

    final container = makeContainer();
    final result =
        await container.read(buildsControllerProvider(key).future);

    expect(result, isEmpty);
    verifyNever(() => gateway.fetchBuilds(any(), any()));
  });
}
