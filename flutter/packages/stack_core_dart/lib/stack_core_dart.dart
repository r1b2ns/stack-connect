/// Dart binding for the `stack_core` Rust crate, via flutter_rust_bridge.
///
/// Initialize the runtime once with `RustLib.init` before calling any binding
/// function. On host (macOS) for tests this loads the dylib by path; on device
/// the default loader resolves the bundled library.
library;

export 'package:flutter_riverpod/flutter_riverpod.dart';

// Generated Rust binding surface (treated as read-only API).
export 'src/rust/frb_generated.dart' show RustLib;
export 'src/rust/frb_api.dart';
export 'src/rust/domain.dart';
export 'src/rust/error.dart';
export 'src/rust/service/kind.dart';
export 'src/rust/service/provider.dart';

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
export 'src/controllers/reviews_controller.dart';
export 'src/controllers/builds_controller.dart';
export 'src/controllers/versions_controller.dart';
export 'src/controllers/beta_groups_controller.dart';
