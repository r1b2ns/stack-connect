import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'support/fakes.dart';

String _appBlob({
  required String id,
  required String name,
  required String bundleId,
  required String accountId,
  String? platform,
}) =>
    jsonEncode({
      'id': id,
      'name': name,
      'bundleId': bundleId,
      'platform': platform,
      'accountId': accountId,
    });

String _flagsBlob({
  required String accountId,
  required String appId,
  bool isFavorite = false,
  bool isArchived = false,
}) =>
    jsonEncode({
      'accountId': accountId,
      'appId': appId,
      'isFavorite': isFavorite,
      'isArchived': isArchived,
    });

void main() {
  const accountId = 'acct-1';

  late MockCoreGateway gateway;
  late FakeAccountsStore accounts;
  late FakeSecretStore secrets;
  late FakeBlobCache blobs;
  late MockFrbProvider provider;
  late MockFrbSyncService syncService;

  setUpAll(() {
    registerFallbackValue(MockFrbProvider());
    registerFallbackValue(MockFrbSyncService());
    registerFallbackValue(ServiceKind.appStoreConnect);
  });

  setUp(() async {
    gateway = MockCoreGateway();
    accounts = FakeAccountsStore();
    secrets = FakeSecretStore();
    blobs = FakeBlobCache();
    provider = MockFrbProvider();
    syncService = MockFrbSyncService();

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
    when(() => gateway.makeSyncService(any(), any())).thenReturn(syncService);
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

  /// Seeds three apps in the cache and stubs `syncApps` to re-persist them so
  /// the background refresh re-emits the same stable, ordered list.
  Future<void> seedApps() async {
    final apps = [
      ('1', 'Alpha', 'com.alpha'),
      ('2', 'Bravo', 'com.bravo'),
      ('3', 'Charlie', 'com.charlie'),
    ];
    for (final (id, name, bundleId) in apps) {
      await blobs.save(
        kAppBlobType,
        id,
        _appBlob(
            id: id, name: name, bundleId: bundleId, accountId: accountId),
      );
    }
    when(() => gateway.syncApps(any(), persist: any(named: 'persist')))
        .thenAnswer((invocation) async {
      final persist = invocation.namedArguments[#persist] as Function;
      for (final (id, name, bundleId) in apps) {
        await persist(
          kAppBlobType,
          id,
          _appBlob(
              id: id, name: name, bundleId: bundleId, accountId: accountId),
        );
      }
      return [
        for (final (id, name, bundleId) in apps)
          AppInfo(id: id, name: name, bundleId: bundleId),
      ];
    });
  }

  /// Reads the apps + flags providers to completion and drains the background
  /// sync so [appListProvider] settles into data.
  Future<void> settle(ProviderContainer container) async {
    await container.read(appsControllerProvider(accountId).future);
    await container.read(appFlagsControllerProvider(accountId).future);
    await Future<void>.delayed(Duration.zero);
    await container.pump();
  }

  test('zips apps with flags (defaults to all-false)', () async {
    await seedApps();
    final container = makeContainer();
    await settle(container);

    final views = container.read(appListProvider(accountId)).value!;
    expect(views.map((v) => v.id), ['1', '2', '3']);
    expect(views.every((v) => !v.isFavorite && !v.isArchived), isTrue);
    expect(views.first.name, 'Alpha');
    expect(views.first.bundleId, 'com.alpha');
  });

  test('favorites are listed first, preserving order within groups', () async {
    await seedApps();
    // Favorite the 3rd app only.
    await blobs.save(
      kAppFlagsBlobType,
      '$accountId.3',
      _flagsBlob(accountId: accountId, appId: '3', isFavorite: true),
    );
    final container = makeContainer();
    await settle(container);

    final views = container.read(appListProvider(accountId)).value!;
    // Charlie (favorite) first, then Alpha, Bravo in synced order.
    expect(views.map((v) => v.id), ['3', '1', '2']);
    expect(views.first.isFavorite, isTrue);
  });

  test('activeAppListProvider excludes archived, archived list isolates them',
      () async {
    await seedApps();
    await blobs.save(
      kAppFlagsBlobType,
      '$accountId.2',
      _flagsBlob(accountId: accountId, appId: '2', isArchived: true),
    );
    await blobs.save(
      kAppFlagsBlobType,
      '$accountId.1',
      _flagsBlob(accountId: accountId, appId: '1', isFavorite: true),
    );
    final container = makeContainer();
    await settle(container);

    final active = container.read(activeAppListProvider(accountId)).value!;
    final archived = container.read(archivedAppListProvider(accountId)).value!;

    // Active: favorite Alpha first, then Charlie; Bravo is archived out.
    expect(active.map((v) => v.id), ['1', '3']);
    expect(archived.map((v) => v.id), ['2']);
    expect(archived.single.isArchived, isTrue);
  });

  test('propagates apps error', () async {
    when(() => gateway.syncApps(any(), persist: any(named: 'persist')))
        .thenThrow(const StackError.network(message: 'offline'));
    final container = makeContainer();
    await container.read(appsControllerProvider(accountId).future);
    await container.read(appFlagsControllerProvider(accountId).future);
    await Future<void>.delayed(Duration.zero);
    await container.pump();

    final result = container.read(appListProvider(accountId));
    expect(result.hasError, isTrue);
    expect(result.error, isA<StackError_Network>());
  });
}
