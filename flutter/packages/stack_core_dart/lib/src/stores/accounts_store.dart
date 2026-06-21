import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// See blob_cache.dart: the platform plugin's initialized `databaseFactory` is
// needed on mobile even though `sqflite_ffi` re-exports the same symbols.
// ignore: unnecessary_import
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:stack_core_rust/stack_core_rust.dart';

/// A connected-account record the host owns.
///
/// The Rust core has no notion of "the list of accounts"; it only connects a
/// single account on demand. The host persists which accounts exist, their
/// service [kind] and a user-facing [label]. Secrets live in the secure store,
/// not here (see `SecureCredentialStore`).
class AccountRecord {
  const AccountRecord({
    required this.id,
    required this.kind,
    required this.label,
  });

  final String id;
  final ServiceKind kind;
  final String label;

  @override
  int get hashCode => Object.hash(id, kind, label);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountRecord &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kind == other.kind &&
          label == other.label;
}

/// Persists the host-owned list of connected accounts.
abstract interface class AccountsStore {
  /// All connected accounts, in insertion order.
  Future<List<AccountRecord>> all();

  /// Inserts or replaces [account] (keyed by [AccountRecord.id]).
  Future<void> upsert(AccountRecord account);

  /// Removes the account with [id], if present.
  Future<void> remove(String id);
}

/// SQLite-backed [AccountsStore].
///
/// Mirrors [SqliteBlobCache]'s platform handling: FFI on desktop/host/tests,
/// the platform plugin on mobile.
class SqliteAccountsStore implements AccountsStore {
  SqliteAccountsStore._(this._db);

  final Database _db;

  static const _table = 'accounts';

  /// Opens (or creates) the accounts database. Pass [databasePath] (`:memory:`
  /// in tests) to override the location.
  static Future<SqliteAccountsStore> open({String? databasePath}) async {
    final factory = _factoryForPlatform();
    final path = databasePath ?? await _defaultPath();
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE $_table (
            id    TEXT PRIMARY KEY,
            kind  TEXT NOT NULL,
            label TEXT NOT NULL,
            seq   INTEGER
          )
        '''),
      ),
    );
    return SqliteAccountsStore._(db);
  }

  static DatabaseFactory _factoryForPlatform() {
    if (Platform.isAndroid || Platform.isIOS) return databaseFactory;
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }

  static Future<String> _defaultPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'accounts.db');
  }

  @override
  Future<List<AccountRecord>> all() async {
    final rows = await _db.query(_table, orderBy: 'seq ASC, rowid ASC');
    return rows
        .map(
          (r) => AccountRecord(
            id: r['id'] as String,
            kind: _kindFromName(r['kind'] as String),
            label: r['label'] as String,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> upsert(AccountRecord account) async {
    await _db.insert(
      _table,
      {
        'id': account.id,
        'kind': account.kind.name,
        'label': account.label,
        'seq': DateTime.now().microsecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> remove(String id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  /// Closes the underlying database.
  Future<void> close() => _db.close();

  static ServiceKind _kindFromName(String name) => ServiceKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => ServiceKind.appStoreConnect,
      );
}
