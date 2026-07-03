import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'support/fakes.dart';

void main() {
  late MockCoreGateway gateway;
  late FakeAccountsStore accounts;
  late FakeSecretStore secrets;
  late FakeBlobCache blobs;
  late MockFrbProvider provider;

  setUpAll(() {
    registerFallbackValue(MockFrbProvider());
    registerFallbackValue(ServiceKind.appStoreConnect);
  });

  setUp(() {
    gateway = MockCoreGateway();
    accounts = FakeAccountsStore();
    secrets = FakeSecretStore();
    blobs = FakeBlobCache();
    provider = MockFrbProvider();

    // The credential schema drives which secrets are read back; one key here.
    when(() => gateway.credentialSchema(any())).thenReturn(const [
      CredentialField(
        key: 'issuerId',
        label: 'Issuer ID',
        secret: true,
        multiline: false,
      ),
    ]);
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

  test('initial build emits the persisted (empty) account list', () async {
    final container = makeContainer();

    final result =
        await container.read(accountsControllerProvider.future);

    expect(result, isEmpty);
  });

  test('addAccount success persists the record and emits data', () async {
    when(() => gateway.connect(
          kind: any(named: 'kind'),
          accountId: any(named: 'accountId'),
          credentials: any(named: 'credentials'),
        )).thenAnswer((_) async => provider);
    when(() => gateway.validate(any())).thenAnswer((_) async {});

    final container = makeContainer();
    // Resolve the initial build first.
    await container.read(accountsControllerProvider.future);

    await container.read(accountsControllerProvider.notifier).addAccount(
      kind: ServiceKind.appStoreConnect,
      label: 'Acme',
      secrets: const {'issuerId': 'abc-123'},
      accountId: 'acct-1',
    );

    // Persisted: secret + account record.
    expect(await secrets.secret('acct-1', 'issuerId'), 'abc-123');
    final persisted = await accounts.all();
    expect(persisted, hasLength(1));
    expect(persisted.single.id, 'acct-1');
    expect(persisted.single.label, 'Acme');

    // Controller now emits the new list.
    final state = container.read(accountsControllerProvider);
    expect(state.value, hasLength(1));
    verify(() => gateway.validate(provider)).called(1);
  });

  test('validate failure surfaces the error and does NOT persist', () async {
    when(() => gateway.connect(
          kind: any(named: 'kind'),
          accountId: any(named: 'accountId'),
          credentials: any(named: 'credentials'),
        )).thenAnswer((_) async => provider);
    when(() => gateway.validate(any())).thenThrow(
      const StackError.auth(message: 'rejected'),
    );

    final container = makeContainer();
    await container.read(accountsControllerProvider.future);

    await expectLater(
      container.read(accountsControllerProvider.notifier).addAccount(
            kind: ServiceKind.appStoreConnect,
            label: 'Acme',
            secrets: const {'issuerId': 'abc-123'},
            accountId: 'acct-1',
          ),
      throwsA(isA<StackError>()),
    );

    // Nothing persisted.
    expect(await secrets.secret('acct-1', 'issuerId'), isNull);
    expect(await accounts.all(), isEmpty);

    // Controller state reflects the error.
    expect(container.read(accountsControllerProvider).hasError, isTrue);
  });

  test('StackError.pendingAgreements propagates as AsyncError', () async {
    when(() => gateway.connect(
          kind: any(named: 'kind'),
          accountId: any(named: 'accountId'),
          credentials: any(named: 'credentials'),
        )).thenAnswer((_) async => provider);
    when(() => gateway.validate(any())).thenThrow(
      const StackError.pendingAgreements(message: 'sign the agreements'),
    );

    final container = makeContainer();
    await container.read(accountsControllerProvider.future);

    await expectLater(
      container.read(accountsControllerProvider.notifier).addAccount(
            kind: ServiceKind.appStoreConnect,
            label: 'Acme',
            secrets: const {'issuerId': 'abc-123'},
          ),
      throwsA(isA<StackError_PendingAgreements>()),
    );

    final state = container.read(accountsControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<StackError_PendingAgreements>());
  });

  test('removeAccount drops secrets, record, and re-emits', () async {
    // Seed an account.
    await accounts.upsert(
      const AccountRecord(
        id: 'acct-1',
        kind: ServiceKind.appStoreConnect,
        label: 'Acme',
      ),
    );
    await secrets.setSecret('acct-1', 'issuerId', 'abc-123');

    final container = makeContainer();
    await container.read(accountsControllerProvider.future);

    await container
        .read(accountsControllerProvider.notifier)
        .removeAccount('acct-1');

    expect(await accounts.all(), isEmpty);
    expect(await secrets.secret('acct-1', 'issuerId'), isNull);
    expect(container.read(accountsControllerProvider).value, isEmpty);
  });
}
