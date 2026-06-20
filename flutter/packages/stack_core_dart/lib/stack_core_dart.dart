/// Dart binding for the `stack_core` Rust crate, via flutter_rust_bridge.
///
/// Initialize the runtime once with `RustLib.init` before calling any binding
/// function. On host (macOS) for tests this loads the dylib by path; on device
/// the default loader resolves the bundled library.
library;

export 'package:flutter_riverpod/flutter_riverpod.dart';

export 'src/controllers/services_controller.dart';
export 'src/rust/frb_generated.dart' show RustLib;
export 'src/rust/frb_api.dart';
export 'src/rust/service/kind.dart';
