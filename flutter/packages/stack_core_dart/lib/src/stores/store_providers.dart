import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'accounts_store.dart';
import 'blob_cache.dart';
import 'secure_credentials.dart';

/// The host's secret store.
///
/// Defaults to the Keychain/Keystore-backed [SecureCredentialStore]. Tests and
/// alternative hosts override this provider with a fake.
final secretStoreProvider = Provider<SecretStore>(
  (ref) => const SecureCredentialStore(),
);

/// The host's blob cache (offline reads + the `syncApps` persist sink).
///
/// Has no default: opening SQLite is async and host-specific, so the host app
/// MUST override this provider with an opened [SqliteBlobCache] (or a fake in
/// tests). Reading it un-overridden throws, by design.
final blobCacheProvider = Provider<BlobCache>(
  (ref) => throw UnimplementedError(
    'blobCacheProvider must be overridden by the host',
  ),
);

/// The host's accounts store.
///
/// Has no default for the same reason as [blobCacheProvider]: the host
/// overrides it with an opened [SqliteAccountsStore] (or a fake in tests).
final accountsStoreProvider = Provider<AccountsStore>(
  (ref) => throw UnimplementedError(
    'accountsStoreProvider must be overridden by the host',
  ),
);
