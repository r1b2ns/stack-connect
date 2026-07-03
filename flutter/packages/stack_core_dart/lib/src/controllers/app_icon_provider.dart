import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gateway/core_gateway.dart';
import '../stores/blob_cache.dart';
import '../stores/store_providers.dart';
import 'connected_provider.dart';

/// The [BlobCache] `typeName` the host persists resolved app-icon URLs under.
///
/// Keyed by the bare app id, with JSON `{appId, iconUrl}`. This is a HOST-ONLY
/// derivation — the Rust core never reads or writes it — so, like the
/// favorite/archive flags, it survives the apps sync (which only writes the
/// `'app'` blob).
const String kAppIconBlobType = 'app_icon';

/// Identifies an app's icon within an account.
typedef AppIconKey = ({String accountId, String appId});

/// Resolves an App Store Connect app's icon URL, lazily and offline-first.
///
/// There is no app-icon endpoint in the core's API; iOS derives the icon from
/// the app's most recent build (the build's `iconAssetToken`, surfaced as
/// [BuildInfo.iconUrl]). This provider mirrors that, purely in Dart:
///
///   1. Cache-first: it reads the `'app_icon'` blob and, when it decodes to a
///      NON-null, non-empty `iconUrl`, returns it without hitting the network.
///      This matches iOS, which only short-circuits when the cached icon is
///      present.
///   2. Otherwise it resolves live: it connects the account's provider, asks
///      the gateway for the builds handle (`gateway.builds`) and the build list
///      (`gateway.fetchBuilds`, newest-first), and takes the first non-null,
///      non-empty `iconUrl`.
///   3. It persists the result (even `null`) so the lookup is cheap next time.
///      A `null` result is intentionally NOT short-circuited in step 1, so a
///      later read re-resolves — once a build with an icon is uploaded, the
///      icon then appears without any cache bust.
///
/// Returns `null` when the provider exposes no builds, the list is empty, or no
/// build carries an icon URL; callers render a placeholder in that case.
/// Malformed cached JSON is tolerated (skipped, falling through to a live
/// resolve).
final appIconProvider =
    FutureProvider.family<String?, AppIconKey>((ref, key) async {
  final cache = ref.read(blobCacheProvider);

  // 1. Cache-first: only a present icon short-circuits (iOS parity).
  final cached = await cache.fetch(kAppIconBlobType, key.appId);
  if (cached != null) {
    final url = _decodeIconBlob(cached);
    if (url != null && url.isNotEmpty) return url;
  }

  // 2. Resolve live from the most recent build's icon URL.
  final gateway = ref.read(coreGatewayProvider);
  final provider =
      await ref.read(connectedProviderProvider(key.accountId).future);
  final builds = gateway.builds(provider);
  String? resolved;
  if (builds != null) {
    final list = await gateway.fetchBuilds(builds, key.appId);
    for (final build in list) {
      final url = build.iconUrl;
      if (url != null && url.isNotEmpty) {
        resolved = url;
        break;
      }
    }
  }

  // 3. Persist (even null) so the next read is cheap; null is still re-resolved
  // because step 1 only short-circuits on a present icon.
  await cache.save(
    kAppIconBlobType,
    key.appId,
    jsonEncode({'appId': key.appId, 'iconUrl': resolved}),
  );
  return resolved;
});

/// Decodes a cached `'app_icon'` blob to its `iconUrl`, or `null` when the JSON
/// is malformed, not an object, or carries no string URL.
String? _decodeIconBlob(String json) {
  final dynamic raw;
  try {
    raw = jsonDecode(json);
  } catch (_) {
    return null;
  }
  if (raw is! Map<String, dynamic>) return null;
  final url = raw['iconUrl'];
  return url is String ? url : null;
}
