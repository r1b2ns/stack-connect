import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// The platform `sqflite` plugin provides the mobile `databaseFactory` (the one
// wired to the platform channel). `sqflite_ffi` re-exports the same symbols, so
// the analyzer flags this as redundant — but on Android/iOS we genuinely need
// the plugin's initialized factory, not the FFI one.
// ignore: unnecessary_import
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A single cached blob row: the JSON the core persisted, keyed by
/// (`typeName`, `id`).
class CachedBlob {
  const CachedBlob({
    required this.typeName,
    required this.id,
    required this.json,
  });

  final String typeName;
  final String id;
  final String json;
}

/// Key/value blob cache the host owns on the Dart side.
///
/// This is BOTH:
///   * the `persist` sink for `FrbSyncService.syncApps` — the core hands each
///     buffered `(typeName, id, json)` save here, and
///   * the offline read source — the core never reads the cache, so the host
///     reads its own apps (and other blobs) back from here.
///
/// The JSON is stored verbatim (the iOS-facing camelCase contract the core
/// emits), so callers decode it into their own models.
abstract interface class BlobCache {
  /// Upserts the blob [json] for ([typeName], [id]).
  Future<void> save(String typeName, String id, String json);

  /// Reads the blob for ([typeName], [id]), or `null` when absent.
  Future<String?> fetch(String typeName, String id);

  /// Reads every blob of [typeName], in insertion order.
  Future<List<CachedBlob>> fetchAll(String typeName);

  /// Removes the blob for ([typeName], [id]).
  Future<void> delete(String typeName, String id);
}

/// SQLite-backed [BlobCache].
///
/// Opens via `sqflite_common_ffi` on desktop/host (and in tests) and via the
/// platform `sqflite` plugin on mobile, so the same code path serves device,
/// desktop and host test runs.
class SqliteBlobCache implements BlobCache {
  SqliteBlobCache._(this._db);

  final Database _db;

  static const _table = 'blobs';

  /// Opens (or creates) the cache database.
  ///
  /// Pass [databasePath] to override the location — `:memory:` in tests, or a
  /// fixed file. When omitted, a `blobs.db` under the app documents directory
  /// is used.
  static Future<SqliteBlobCache> open({String? databasePath}) async {
    final factory = _factoryForPlatform();
    final path = databasePath ?? await _defaultPath();
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => db.execute('''
          CREATE TABLE $_table (
            type_name TEXT NOT NULL,
            id        TEXT NOT NULL,
            json      TEXT NOT NULL,
            seq       INTEGER PRIMARY KEY AUTOINCREMENT,
            UNIQUE(type_name, id)
          )
        '''),
      ),
    );
    return SqliteBlobCache._(db);
  }

  static DatabaseFactory _factoryForPlatform() {
    if (Platform.isAndroid || Platform.isIOS) return databaseFactory;
    // Desktop & host test runs: initialize the FFI loader once.
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }

  static Future<String> _defaultPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'blobs.db');
  }

  @override
  Future<void> save(String typeName, String id, String json) async {
    await _db.insert(
      _table,
      {'type_name': typeName, 'id': id, 'json': json},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<String?> fetch(String typeName, String id) async {
    final rows = await _db.query(
      _table,
      columns: ['json'],
      where: 'type_name = ? AND id = ?',
      whereArgs: [typeName, id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['json'] as String;
  }

  @override
  Future<List<CachedBlob>> fetchAll(String typeName) async {
    final rows = await _db.query(
      _table,
      columns: ['type_name', 'id', 'json'],
      where: 'type_name = ?',
      whereArgs: [typeName],
      orderBy: 'seq ASC',
    );
    return rows
        .map(
          (r) => CachedBlob(
            typeName: r['type_name'] as String,
            id: r['id'] as String,
            json: r['json'] as String,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> delete(String typeName, String id) async {
    await _db.delete(
      _table,
      where: 'type_name = ? AND id = ?',
      whereArgs: [typeName, id],
    );
  }

  /// Closes the underlying database. Call on host/desktop shutdown.
  Future<void> close() => _db.close();
}
