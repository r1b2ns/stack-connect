import 'package:fluent_ui/fluent_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'app.dart';

/// Initializes the Rust runtime and the host SQLite stores, then runs the app
/// under a [ProviderScope] with the host overrides wired in.
///
/// On desktop the SQLite backend is FFI, so the loader is initialized here
/// before any store opens. `accountsStoreProvider`/`blobCacheProvider` throw
/// until overridden, so both MUST be supplied to the root scope.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop uses the FFI SQLite backend; initialize its loader once up front.
  sqfliteFfiInit();

  final dir = await getApplicationDocumentsDirectory();
  final accountsStore = await SqliteAccountsStore.open(
    databasePath: p.join(dir.path, 'accounts.db'),
  );
  final blobCache = await SqliteBlobCache.open(
    databasePath: p.join(dir.path, 'blobs.db'),
  );

  await RustLib.init();

  runApp(
    ProviderScope(
      overrides: [
        accountsStoreProvider.overrideWithValue(accountsStore),
        blobCacheProvider.overrideWithValue(blobCache),
      ],
      child: const StackDesktopApp(),
    ),
  );
}
