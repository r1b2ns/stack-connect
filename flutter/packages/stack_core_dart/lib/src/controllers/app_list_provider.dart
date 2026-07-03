import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stack_core_rust/stack_core_rust.dart';

import '../models/app_view.dart';
import 'app_flags_controller.dart';
import 'apps_controller.dart';

/// All of an account's apps as [AppView]s, zipping the synced [AppInfo] list
/// (from [appsControllerProvider]) onto the local [AppFlags] (from
/// [appFlagsControllerProvider]).
///
/// Ordering: favorites first (in their synced order), then the rest (in their
/// synced order). Archived apps are NOT removed here — both the active and
/// archived derived providers below filter this single source so the zip + sort
/// logic lives in one place.
///
/// Loading/error propagation: while EITHER upstream is loading the result is
/// [AsyncValue.loading]; if either has errored the error (and stack trace) is
/// forwarded. Only when both hold data is a value produced.
final appListProvider =
    Provider.family<AsyncValue<List<AppView>>, String>((ref, accountId) {
  final apps = ref.watch(appsControllerProvider(accountId));
  final flags = ref.watch(appFlagsControllerProvider(accountId));

  // Forward errors first (an error is more actionable than a stale loading).
  if (apps case AsyncError(:final error, :final stackTrace)) {
    return AsyncError(error, stackTrace);
  }
  if (flags case AsyncError(:final error, :final stackTrace)) {
    return AsyncError(error, stackTrace);
  }

  final appList = apps.value;
  final flagMap = flags.value;
  if (appList == null || flagMap == null) {
    return const AsyncLoading();
  }

  final views = [
    for (final app in appList)
      AppView(
        info: app,
        isFavorite: flagMap[app.id]?.isFavorite ?? false,
        isArchived: flagMap[app.id]?.isArchived ?? false,
      ),
  ];

  // Stable partition: favorites keep their relative order, then non-favorites.
  final favorites = <AppView>[];
  final rest = <AppView>[];
  for (final view in views) {
    (view.isFavorite ? favorites : rest).add(view);
  }
  return AsyncData([...favorites, ...rest]);
});

/// The active apps for [accountId]: everything NOT archived, favorites first.
///
/// This is the desktop sidebar's primary list. Derived from [appListProvider],
/// so it shares its loading/error semantics.
final activeAppListProvider =
    Provider.family<AsyncValue<List<AppView>>, String>((ref, accountId) {
  return ref
      .watch(appListProvider(accountId))
      .whenData((views) => views.where((v) => !v.isArchived).toList());
});

/// The archived apps for [accountId], in favorites-first then synced order.
///
/// Backs the dedicated "Archived" list. Derived from [appListProvider], so it
/// shares its loading/error semantics.
final archivedAppListProvider =
    Provider.family<AsyncValue<List<AppView>>, String>((ref, accountId) {
  return ref
      .watch(appListProvider(accountId))
      .whenData((views) => views.where((v) => v.isArchived).toList());
});
