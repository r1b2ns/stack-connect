/// Dart binding for the `stack_core` Rust crate, via flutter_rust_bridge.
///
/// Initialize the runtime once with `RustLib.init` before calling any binding
/// function. On host (macOS) for tests this loads the dylib by path; on device
/// the default loader resolves the bundled library.
library;

export 'package:flutter_riverpod/flutter_riverpod.dart';

// Generated Rust binding surface (treated as read-only API), now sourced from
// the standalone `stack_core_rust` package in the core repo. Re-exported here so
// downstream apps keep getting `RustLib`, `FrbProvider`, domain/error/kind/
// provider types via a single `package:stack_core_dart/...` import.
export 'package:stack_core_rust/stack_core_rust.dart';

// Generated localizations (from the ARB files, themselves generated from the
// iOS String Catalog). Apps wire `AppLocalizations.delegate` /
// `AppLocalizations.supportedLocales` and read copy via
// `AppLocalizations.of(context)`.
export 'src/l10n/app_localizations.dart';

// Host-only view models (favorite/archive flags zipped onto AppInfo).
export 'src/models/app_view.dart';

// Host stores (the core's ports, Dart side).
export 'src/stores/accounts_store.dart';
export 'src/stores/blob_cache.dart';
export 'src/stores/secure_credentials.dart';
export 'src/stores/store_providers.dart';

// The testable seam over the binding.
export 'src/gateway/core_gateway.dart';

// Controllers + providers the UI slice consumes.
export 'src/controllers/services_controller.dart';
export 'src/controllers/connected_provider.dart';
export 'src/controllers/accounts_controller.dart';
export 'src/controllers/apps_controller.dart';
export 'src/controllers/app_flags_controller.dart';
export 'src/controllers/app_list_provider.dart';
export 'src/controllers/app_icon_provider.dart';
export 'src/controllers/reviews_controller.dart';
export 'src/controllers/builds_controller.dart';
export 'src/controllers/versions_controller.dart';
export 'src/controllers/beta_groups_controller.dart';
