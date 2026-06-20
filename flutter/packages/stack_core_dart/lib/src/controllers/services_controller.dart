import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rust/frb_api.dart';
import '../rust/service/kind.dart';

/// Shared controller layer consumed by every host app.
///
/// Crosses the flutter_rust_bridge boundary via [availableServices] and exposes
/// the result as a Riverpod [FutureProvider]. `RustLib.init` must have completed
/// before this provider is first read.
final availableServicesProvider = FutureProvider<List<ServiceKind>>(
  (ref) async => availableServices(),
);
