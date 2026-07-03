import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gateway/core_gateway.dart';
import 'package:stack_core_rust/stack_core_rust.dart';
import '../stores/accounts_store.dart';
import '../stores/store_providers.dart';

/// Builds and caches one live [FrbProvider] per connected account.
///
/// The apps and reviews controllers reuse this single connected handle instead
/// of re-connecting per call. The same `Future<FrbProvider>` is returned for a
/// given `accountId` until the provider is invalidated (e.g. on a credentials
/// change or account removal), at which point the next read reconnects.
///
/// Secrets are read from [secretStoreProvider] using the service's credential
/// schema as the key list, then handed to [CoreGateway.connect] as plain
/// `FrbCredential` data (the core never sees the secret store).
final connectedProviderProvider =
    FutureProvider.family<FrbProvider, String>((ref, accountId) async {
  final gateway = ref.watch(coreGatewayProvider);
  final accounts = ref.watch(accountsStoreProvider);
  final secrets = ref.watch(secretStoreProvider);

  final account = await _requireAccount(accounts, accountId);

  final schema = gateway.credentialSchema(account.kind);
  final credentials = <FrbCredential>[];
  for (final field in schema) {
    final value = await secrets.secret(accountId, field.key);
    if (value == null) continue;
    credentials.add(FrbCredential(key: field.key, value: value));
  }

  return gateway.connect(
    kind: account.kind,
    accountId: accountId,
    credentials: credentials,
  );
});

Future<AccountRecord> _requireAccount(
  AccountsStore store,
  String accountId,
) async {
  final all = await store.all();
  for (final account in all) {
    if (account.id == accountId) return account;
  }
  throw StateError('No connected account with id "$accountId"');
}

/// Connects an account directly from supplied [secrets], without persisting
/// anything.
///
/// Used by [AccountsController.addAccount] to verify credentials BEFORE the
/// account record is committed: the account is not yet in the accounts store,
/// so [connectedProviderProvider] (which looks the account up) cannot be used.
/// Returns the live provider so the caller can `validate()`/`fetchApps()` on it.
Future<FrbProvider> connectWithSecrets({
  required CoreGateway gateway,
  required ServiceKind kind,
  required String accountId,
  required Map<String, String> secrets,
}) {
  final credentials = secrets.entries
      .map((e) => FrbCredential(key: e.key, value: e.value))
      .toList(growable: false);
  return gateway.connect(
    kind: kind,
    accountId: accountId,
    credentials: credentials,
  );
}
