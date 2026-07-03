import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'app.dart';

/// Initializes the Rust runtime and the host SQLite stores, then runs the app
/// under a [ProviderScope] with the host overrides wired in.
///
/// `accountsStoreProvider` and `blobCacheProvider` have no default (they throw
/// until overridden), so they MUST be supplied here before [runApp]. The
/// `secretStoreProvider` works out of the box (Keychain/Keystore-backed).
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // On Android the platform `sqflite` plugin provides the database factory, so
  // no FFI init is needed here (the stores pick the platform factory).
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
      child: const StackMobileApp(),
    ),
  );
}
