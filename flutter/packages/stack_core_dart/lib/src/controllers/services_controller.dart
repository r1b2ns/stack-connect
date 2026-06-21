import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stack_core_rust/stack_core_rust.dart';

/// Shared controller layer consumed by every host app.
///
/// Crosses the flutter_rust_bridge boundary via [availableServices] and exposes
/// the result as a Riverpod [FutureProvider]. `RustLib.init` must have completed
/// before this provider is first read.
final availableServicesProvider = FutureProvider<List<ServiceKind>>(
  (ref) async => availableServices(),
);
