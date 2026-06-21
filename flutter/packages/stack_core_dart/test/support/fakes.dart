import 'package:mocktail/mocktail.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

/// Mock of the binding seam. Controllers depend only on [CoreGateway], so
/// mocking this fully isolates them from the dylib and the network.
class MockCoreGateway extends Mock implements CoreGateway {}

/// Opaque FRB handles the controllers pass around but never introspect in
/// tests; mocktail mocks stand in for the real Rust-opaque objects.
class MockFrbProvider extends Mock implements FrbProvider {}

class MockFrbReviews extends Mock implements FrbReviews {}

class MockFrbBuilds extends Mock implements FrbBuilds {}

class MockFrbAppStoreVersions extends Mock implements FrbAppStoreVersions {}

class MockFrbBetaGroups extends Mock implements FrbBetaGroups {}

class MockFrbSyncService extends Mock implements FrbSyncService {}

/// In-memory [SecretStore]: namespaced `accountId -> key -> value`.
class FakeSecretStore implements SecretStore {
  final Map<String, Map<String, String>> _store = {};

  @override
  Future<void> setSecret(String accountId, String key, String value) async {
    (_store[accountId] ??= {})[key] = value;
  }

  @override
  Future<String?> secret(String accountId, String key) async =>
      _store[accountId]?[key];

  @override
  Future<void> deleteAccount(String accountId) async {
    _store.remove(accountId);
  }
}

/// In-memory [AccountsStore] preserving insertion order.
class FakeAccountsStore implements AccountsStore {
  final List<AccountRecord> _records = [];

  @override
  Future<List<AccountRecord>> all() async => List.unmodifiable(_records);

  @override
  Future<void> upsert(AccountRecord account) async {
    _records.removeWhere((r) => r.id == account.id);
    _records.add(account);
  }

  @override
  Future<void> remove(String id) async {
    _records.removeWhere((r) => r.id == id);
  }
}

/// In-memory [BlobCache] keyed by (typeName, id), insertion-ordered.
class FakeBlobCache implements BlobCache {
  final List<CachedBlob> _blobs = [];

  @override
  Future<void> save(String typeName, String id, String json) async {
    _blobs.removeWhere((b) => b.typeName == typeName && b.id == id);
    _blobs.add(CachedBlob(typeName: typeName, id: id, json: json));
  }

  @override
  Future<String?> fetch(String typeName, String id) async {
    for (final b in _blobs) {
      if (b.typeName == typeName && b.id == id) return b.json;
    }
    return null;
  }

  @override
  Future<List<CachedBlob>> fetchAll(String typeName) async =>
      _blobs.where((b) => b.typeName == typeName).toList(growable: false);

  @override
  Future<void> delete(String typeName, String id) async {
    _blobs.removeWhere((b) => b.typeName == typeName && b.id == id);
  }
}
