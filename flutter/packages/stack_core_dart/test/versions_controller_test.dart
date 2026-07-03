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
  late MockFrbAppStoreVersions versions;

  setUpAll(() {
    registerFallbackValue(MockFrbProvider());
    registerFallbackValue(MockFrbAppStoreVersions());
    registerFallbackValue(ServiceKind.appStoreConnect);
  });

  setUp(() async {
    gateway = MockCoreGateway();
    accounts = FakeAccountsStore();
    secrets = FakeSecretStore();
    blobs = FakeBlobCache();
    provider = MockFrbProvider();
    versions = MockFrbAppStoreVersions();

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
    when(() => gateway.appStoreVersions(any())).thenReturn(versions);
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

  test('build loads versions via the connected provider', () async {
    when(() => gateway.fetchVersions(any(), any())).thenAnswer(
      (_) async => const [
        AppStoreVersionInfo(id: 'v1', appId: appId, versionString: '1.2.0'),
      ],
    );

    final container = makeContainer();
    final result =
        await container.read(versionsControllerProvider(key).future);

    expect(result, hasLength(1));
    expect(result.single.id, 'v1');
    verify(() => gateway.fetchVersions(versions, appId)).called(1);
  });

  test('build returns empty when the provider exposes no versions', () async {
    when(() => gateway.appStoreVersions(any())).thenReturn(null);

    final container = makeContainer();
    final result =
        await container.read(versionsControllerProvider(key).future);

    expect(result, isEmpty);
    verifyNever(() => gateway.fetchVersions(any(), any()));
  });
}
