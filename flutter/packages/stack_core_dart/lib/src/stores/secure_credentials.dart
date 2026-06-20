import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Per-account credential secret store, backed by [FlutterSecureStorage].
///
/// The Rust core does not own secrets: the FRB `connect` facade takes the
/// already-resolved `(key, value)` pairs as plain data. The host therefore owns
/// secret persistence and reads it back at connect time to build the
/// `List<FrbCredential>`.
///
/// Secrets are namespaced per account so several connected accounts never
/// collide. The on-disk key is `cred/<accountId>/<key>`.
abstract interface class SecretStore {
  /// Persists [value] for ([accountId], [key]).
  Future<void> setSecret(String accountId, String key, String value);

  /// Reads the secret for ([accountId], [key]), or `null` when absent.
  Future<String?> secret(String accountId, String key);

  /// Removes every secret stored for [accountId].
  Future<void> deleteAccount(String accountId);
}

/// [SecretStore] over `flutter_secure_storage` (Keychain / Keystore).
class SecureCredentialStore implements SecretStore {
  /// Creates a store; inject a custom [storage] in tests.
  const SecureCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _key(String accountId, String key) => 'cred/$accountId/$key';

  static String _prefix(String accountId) => 'cred/$accountId/';

  @override
  Future<void> setSecret(String accountId, String key, String value) =>
      _storage.write(key: _key(accountId, key), value: value);

  @override
  Future<String?> secret(String accountId, String key) =>
      _storage.read(key: _key(accountId, key));

  @override
  Future<void> deleteAccount(String accountId) async {
    final all = await _storage.readAll();
    final prefix = _prefix(accountId);
    final stale = all.keys.where((k) => k.startsWith(prefix));
    for (final key in stale) {
      await _storage.delete(key: key);
    }
  }
}
