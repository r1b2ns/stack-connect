import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_view.dart';
import '../stores/blob_cache.dart';
import '../stores/store_providers.dart';

/// The [BlobCache] `typeName` the host persists per-app local flags under.
///
/// Distinct from `kAppBlobType` (`'app'`) on purpose: the apps sync overwrites
/// the `'app'` blob wholesale, so flags MUST live in their own type to survive
/// a refresh. Flag blobs are keyed `'$accountId.$appId'`, with JSON
/// `{accountId,appId,isFavorite,isArchived}`.
const String kAppFlagsBlobType = 'app_flags';

/// Owns the local favorite/archive flags for one account's apps.
///
/// This is a purely HOST-SIDE concept — it never calls the Rust core or the
/// App Store Connect API. `build` reads every `'app_flags'` blob, decodes it,
/// filters to [arg] (the `accountId`), and returns a `Map<appId, AppFlags>`.
///
/// [toggleFavorite]/[toggleArchive] apply an OPTIMISTIC update — the new map is
/// emitted immediately so the UI reacts without waiting on disk — then persist.
/// If the persist throws, the state is REVERTED to the previous map and the
/// error is rethrown, mirroring the iOS implementation.
class AppFlagsController extends FamilyAsyncNotifier<Map<String, AppFlags>, String> {
  @override
  Future<Map<String, AppFlags>> build(String accountId) async {
    final cache = ref.read(blobCacheProvider);
    final blobs = await cache.fetchAll(kAppFlagsBlobType);
    final flags = <String, AppFlags>{};
    for (final blob in blobs) {
      final decoded = _decodeFlagsBlob(blob.json);
      if (decoded == null) continue;
      if (decoded.accountId != accountId) continue;
      flags[decoded.appId] = decoded.flags;
    }
    return flags;
  }

  /// Toggles the favorite flag for [appId], persisting the result.
  Future<void> toggleFavorite(String appId) async {
    final current = _current(appId);
    await _persist(appId, current.copyWith(isFavorite: !current.isFavorite));
  }

  /// Toggles the archive flag for [appId], persisting the result.
  Future<void> toggleArchive(String appId) async {
    final current = _current(appId);
    await _persist(appId, current.copyWith(isArchived: !current.isArchived));
  }

  /// The flags currently known for [appId], or the default (all-false).
  AppFlags _current(String appId) =>
      state.value?[appId] ?? const AppFlags();

  /// Optimistically emits [next] for [appId], then writes it through to the
  /// cache. On a write failure, reverts to the pre-toggle state and rethrows.
  Future<void> _persist(String appId, AppFlags next) async {
    final previous = state.value ?? const <String, AppFlags>{};
    final updated = {...previous, appId: next};
    state = AsyncData(updated);
    try {
      final cache = ref.read(blobCacheProvider);
      await cache.save(
        kAppFlagsBlobType,
        '$arg.$appId',
        _encodeFlagsBlob(accountId: arg, appId: appId, flags: next),
      );
    } catch (_) {
      // Revert the optimistic update so the UI reflects persisted truth.
      state = AsyncData(previous);
      rethrow;
    }
  }
}

/// The app-flags controller the UI slice consumes, keyed by `accountId`.
final appFlagsControllerProvider = AsyncNotifierProvider.family<
    AppFlagsController, Map<String, AppFlags>, String>(AppFlagsController.new);

/// A flags blob decoded from the cache: the [AppFlags] plus its keys.
class _DecodedFlags {
  const _DecodedFlags({
    required this.accountId,
    required this.appId,
    required this.flags,
  });

  final String accountId;
  final String appId;
  final AppFlags flags;
}

String _encodeFlagsBlob({
  required String accountId,
  required String appId,
  required AppFlags flags,
}) =>
    jsonEncode({
      'accountId': accountId,
      'appId': appId,
      'isFavorite': flags.isFavorite,
      'isArchived': flags.isArchived,
    });

_DecodedFlags? _decodeFlagsBlob(String json) {
  final dynamic raw;
  try {
    raw = jsonDecode(json);
  } catch (_) {
    // Tolerate malformed JSON — skip the row rather than failing the build.
    return null;
  }
  if (raw is! Map<String, dynamic>) return null;
  final accountId = raw['accountId'];
  final appId = raw['appId'];
  if (accountId is! String || appId is! String) return null;
  final isFavorite = raw['isFavorite'];
  final isArchived = raw['isArchived'];
  return _DecodedFlags(
    accountId: accountId,
    appId: appId,
    flags: AppFlags(
      isFavorite: isFavorite is bool && isFavorite,
      isArchived: isArchived is bool && isArchived,
    ),
  );
}
