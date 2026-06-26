import 'package:stack_core_rust/stack_core_rust.dart';

/// Local, client-side presentation flags for an App Store Connect app.
///
/// These are a HOST-ONLY concept: they never touch the Rust core or the App
/// Store Connect API. They are persisted in their own blob type so the apps
/// sync (which overwrites the `'app'` blob) leaves them untouched. See
/// `AppFlagsController` for persistence and `appListProvider` for how they are
/// zipped onto the synced [AppInfo] list.
class AppFlags {
  const AppFlags({
    this.isFavorite = false,
    this.isArchived = false,
  });

  /// Whether the user pinned this app to the top of the active list.
  final bool isFavorite;

  /// Whether the user moved this app out of the active list into the archive.
  final bool isArchived;

  /// Returns a copy with the given fields replaced.
  AppFlags copyWith({bool? isFavorite, bool? isArchived}) => AppFlags(
        isFavorite: isFavorite ?? this.isFavorite,
        isArchived: isArchived ?? this.isArchived,
      );

  @override
  int get hashCode => isFavorite.hashCode ^ isArchived.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppFlags &&
          runtimeType == other.runtimeType &&
          isFavorite == other.isFavorite &&
          isArchived == other.isArchived;
}

/// A synced [AppInfo] zipped with its local [AppFlags].
///
/// This is the view the desktop UI consumes: it carries the immutable,
/// core-owned app metadata plus the host-only favorite/archive flags. The
/// convenience getters delegate to [info] so callers never need to reach
/// through it for the common fields.
class AppView {
  const AppView({
    required this.info,
    this.isFavorite = false,
    this.isArchived = false,
  });

  /// The core-owned app metadata (never mutated by the host).
  final AppInfo info;

  /// Whether this app is pinned to the top of the active list.
  final bool isFavorite;

  /// Whether this app lives in the archive rather than the active list.
  final bool isArchived;

  /// The app's stable id.
  String get id => info.id;

  /// The app's display name.
  String get name => info.name;

  /// The app's bundle identifier.
  String get bundleId => info.bundleId;

  /// The app's platform, when the core reported one.
  String? get platform => info.platform;

  @override
  int get hashCode =>
      info.hashCode ^ isFavorite.hashCode ^ isArchived.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppView &&
          runtimeType == other.runtimeType &&
          info == other.info &&
          isFavorite == other.isFavorite &&
          isArchived == other.isArchived;
}
