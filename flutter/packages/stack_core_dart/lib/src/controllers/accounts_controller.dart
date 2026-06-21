import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gateway/core_gateway.dart';
import 'package:stack_core_rust/stack_core_rust.dart';
import '../stores/accounts_store.dart';
import '../stores/store_providers.dart';
import 'connected_provider.dart';

/// Owns the host's list of connected accounts.
///
/// Adding an account verifies the supplied secrets against the live service
/// BEFORE anything is persisted: on failure the underlying `StackError` is
/// surfaced through [AsyncValue.error] and neither the secrets nor the account
/// record are committed. This keeps the persisted state free of un-connectable
/// accounts.
class AccountsController extends AsyncNotifier<List<AccountRecord>> {
  @override
  Future<List<AccountRecord>> build() async {
    final store = ref.watch(accountsStoreProvider);
    return store.all();
  }

  /// Connects [kind] with [secrets], and only on success persists the secrets
  /// and a new [AccountRecord].
  ///
  /// Verification runs through `validate()`. Any error (notably
  /// `StackError.pendingAgreements`) propagates as an [AsyncError] without
  /// mutating persisted state.
  Future<void> addAccount({
    required ServiceKind kind,
    required String label,
    required Map<String, String> secrets,
    String? accountId,
  }) async {
    final gateway = ref.read(coreGatewayProvider);
    final store = ref.read(accountsStoreProvider);
    final secretStore = ref.read(secretStoreProvider);

    final id = accountId ?? _generateId();

    // Verify first — do not touch persisted state until the credentials prove
    // valid against the live service. A failure here propagates to the caller
    // (and is reflected as AsyncError below) with persisted state untouched.
    final next = await AsyncValue.guard(() async {
      final provider = await connectWithSecrets(
        gateway: gateway,
        kind: kind,
        accountId: id,
        secrets: secrets,
      );
      await gateway.validate(provider);

      // Verified: persist secrets, then the account record.
      for (final entry in secrets.entries) {
        await secretStore.setSecret(id, entry.key, entry.value);
      }
      await store.upsert(AccountRecord(id: id, kind: kind, label: label));

      return store.all();
    });

    state = next;
    if (next case AsyncError(:final error, :final stackTrace)) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Removes [id]: drops its secrets, its account record, and invalidates the
  /// cached connected provider so a stale handle is never reused.
  Future<void> removeAccount(String id) async {
    final store = ref.read(accountsStoreProvider);
    final secretStore = ref.read(secretStoreProvider);

    state = await AsyncValue.guard(() async {
      await secretStore.deleteAccount(id);
      await store.remove(id);
      ref.invalidate(connectedProviderProvider(id));
      return store.all();
    });
  }

  static String _generateId() =>
      DateTime.now().microsecondsSinceEpoch.toString();
}

/// The accounts controller the UI slice consumes.
final accountsControllerProvider =
    AsyncNotifierProvider<AccountsController, List<AccountRecord>>(
  AccountsController.new,
);
