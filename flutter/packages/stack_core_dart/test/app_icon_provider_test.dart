import 'dart:convert';

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

  test('resolves the newest build icon URL and persists an app_icon blob',
      () async {
    when(() => gateway.fetchBuilds(any(), any())).thenAnswer(
      (_) async => const [
        BuildInfo(id: 'b2', appId: appId, iconUrl: 'https://cdn/icon-new.png'),
        BuildInfo(id: 'b1', appId: appId, iconUrl: 'https://cdn/icon-old.png'),
      ],
    );

    final container = makeContainer();
    final url = await container.read(appIconProvider(key).future);

    expect(url, 'https://cdn/icon-new.png');
    final persisted = await blobs.fetch(kAppIconBlobType, appId);
    expect(persisted, isNotNull);
    expect(jsonDecode(persisted!),
        {'appId': appId, 'iconUrl': 'https://cdn/icon-new.png'});
    verify(() => gateway.fetchBuilds(builds, appId)).called(1);
  });

  test('skips builds without an icon and takes the first one that has it',
      () async {
    when(() => gateway.fetchBuilds(any(), any())).thenAnswer(
      (_) async => const [
        BuildInfo(id: 'b3', appId: appId),
        BuildInfo(id: 'b2', appId: appId, iconUrl: ''),
        BuildInfo(id: 'b1', appId: appId, iconUrl: 'https://cdn/icon.png'),
      ],
    );

    final container = makeContainer();
    final url = await container.read(appIconProvider(key).future);

    expect(url, 'https://cdn/icon.png');
  });

  test('cache-first: a present cached icon short-circuits fetchBuilds',
      () async {
    await blobs.save(
      kAppIconBlobType,
      appId,
      jsonEncode({'appId': appId, 'iconUrl': 'https://cdn/cached.png'}),
    );

    final container = makeContainer();
    final url = await container.read(appIconProvider(key).future);

    expect(url, 'https://cdn/cached.png');
    verifyNever(() => gateway.fetchBuilds(any(), any()));
  });

  test('returns null when the provider exposes no builds', () async {
    when(() => gateway.builds(any())).thenReturn(null);

    final container = makeContainer();
    final url = await container.read(appIconProvider(key).future);

    expect(url, isNull);
    verifyNever(() => gateway.fetchBuilds(any(), any()));
  });

  test('returns null when the build list is empty', () async {
    when(() => gateway.fetchBuilds(any(), any()))
        .thenAnswer((_) async => const []);

    final container = makeContainer();
    final url = await container.read(appIconProvider(key).future);

    expect(url, isNull);
  });

  test('returns null when no build carries an icon URL', () async {
    when(() => gateway.fetchBuilds(any(), any())).thenAnswer(
      (_) async => const [
        BuildInfo(id: 'b1', appId: appId),
        BuildInfo(id: 'b2', appId: appId, iconUrl: ''),
      ],
    );

    final container = makeContainer();
    final url = await container.read(appIconProvider(key).future);

    expect(url, isNull);
  });

  test('a null cached result is re-resolved on the next read', () async {
    // First read: no icon anywhere → persists a null icon blob.
    when(() => gateway.fetchBuilds(any(), any()))
        .thenAnswer((_) async => const [BuildInfo(id: 'b1', appId: appId)]);

    final first = makeContainer();
    expect(await first.read(appIconProvider(key).future), isNull);
    // The null was persisted...
    final persisted = await blobs.fetch(kAppIconBlobType, appId);
    expect(jsonDecode(persisted!), {'appId': appId, 'iconUrl': null});

    // A newer build now has an icon. A fresh read must re-resolve (not
    // short-circuit on the cached null) and pick it up.
    when(() => gateway.fetchBuilds(any(), any())).thenAnswer(
      (_) async =>
          const [BuildInfo(id: 'b2', appId: appId, iconUrl: 'https://cdn/x.png')],
    );

    final second = makeContainer();
    expect(await second.read(appIconProvider(key).future), 'https://cdn/x.png');
  });

  test('tolerates malformed cached JSON by resolving live', () async {
    await blobs.save(kAppIconBlobType, appId, 'not json {');
    when(() => gateway.fetchBuilds(any(), any())).thenAnswer(
      (_) async =>
          const [BuildInfo(id: 'b1', appId: appId, iconUrl: 'https://cdn/ok.png')],
    );

    final container = makeContainer();
    final url = await container.read(appIconProvider(key).future);

    expect(url, 'https://cdn/ok.png');
  });
}
