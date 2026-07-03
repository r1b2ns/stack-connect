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

  test('cache-empty: loading then synced data', () async {
    when(() => gateway.syncApps(any(), persist: any(named: 'persist')))
        .thenAnswer((_) async => const [
              AppInfo(id: '1', name: 'One', bundleId: 'com.one'),
            ]);

    final container = makeContainer();
    final controller = appsControllerProvider(accountId);

    // Initial build returns the empty cache.
    final initial = await container.read(controller.future);
    expect(initial, isEmpty);

    // The background sync refreshes; wait for it to land.
    await Future<void>.delayed(Duration.zero);
    await container.pump();

    final refreshed = container.read(controller);
    expect(refreshed.value, hasLength(1));
    expect(refreshed.value!.single.id, '1');
  });

  test('cache-then-sync: emits cached first, then refreshed', () async {
    await blobs.save(
      kAppBlobType,
      '1',
      _appBlob(
        id: '1',
        name: 'Cached',
        bundleId: 'com.cached',
        accountId: accountId,
      ),
    );
    when(() => gateway.syncApps(any(), persist: any(named: 'persist')))
        .thenAnswer((invocation) async {
      // Mimic the core: persist the refreshed blob through the callback.
      final persist = invocation.namedArguments[#persist] as Function;
      await persist(
        kAppBlobType,
        '1',
        _appBlob(
          id: '1',
          name: 'Refreshed',
          bundleId: 'com.cached',
          accountId: accountId,
        ),
      );
      return const [
        AppInfo(id: '1', name: 'Refreshed', bundleId: 'com.cached'),
      ];
    });

    final container = makeContainer();
    final controller = appsControllerProvider(accountId);

    final emitted = <List<AppInfo>?>[];
    container.listen(controller, (_, next) => emitted.add(next.value),
        fireImmediately: true);

    // First value: the cached list.
    final cached = await container.read(controller.future);
    expect(cached.single.name, 'Cached');

    await Future<void>.delayed(Duration.zero);
    await container.pump();

    // Latest value: the refreshed list.
    final refreshed = container.read(controller).value!;
    expect(refreshed.single.name, 'Refreshed');

    // Sanity: the cached name appeared before the refreshed one.
    final names =
        emitted.whereType<List<AppInfo>>().expand((l) => l).map((a) => a.name);
    expect(names, containsAllInOrder(['Cached', 'Refreshed']));
  });

  test('sync error surfaces as AsyncError', () async {
    when(() => gateway.syncApps(any(), persist: any(named: 'persist')))
        .thenThrow(const StackError.network(message: 'offline'));

    final container = makeContainer();
    final controller = appsControllerProvider(accountId);

    await container.read(controller.future); // empty cache, data state
    await Future<void>.delayed(Duration.zero);
    await container.pump();

    final state = container.read(controller);
    expect(state.hasError, isTrue);
    expect(state.error, isA<StackError_Network>());
  });

  test('refresh() re-syncs and re-emits', () async {
    var calls = 0;
    when(() => gateway.syncApps(any(), persist: any(named: 'persist')))
        .thenAnswer((_) async {
      calls++;
      return [AppInfo(id: '$calls', name: 'App$calls', bundleId: 'com.$calls')];
    });

    final container = makeContainer();
    final controller = appsControllerProvider(accountId);

    await container.read(controller.future);
    await Future<void>.delayed(Duration.zero);
    await container.pump();

    await container.read(controller.notifier).refresh();
    final state = container.read(controller);
    expect(state.value, isNotEmpty);
    expect(calls, greaterThanOrEqualTo(2));
  });
}
