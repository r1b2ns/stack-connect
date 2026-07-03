import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The app's version and build number, read from the bundle.
///
/// Surfaced as a [FutureProvider] so the Settings footer can render a
/// loading/error state uniformly while [PackageInfo.fromPlatform] resolves. The
/// footer mirrors the iOS format `StackConnect v<version> (<build>)`, so this
/// provider exposes exactly the two fields that string needs.
final appInfoProvider = FutureProvider<AppInfo>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppInfo(version: info.version, build: info.buildNumber);
});

/// Immutable carrier for the bundle version/build pair shown in Settings.
class AppInfo {
  const AppInfo({required this.version, required this.build});

  /// Marketing version, e.g. `1.0.0` (iOS `CFBundleShortVersionString`).
  final String version;

  /// Build number, e.g. `1` (iOS `CFBundleVersion`).
  final String build;
}
