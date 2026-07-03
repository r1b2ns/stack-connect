import 'package:flutter_test/flutter_test.dart';

// `ExternalLibrary` (host-path dylib loader), `RustLib`, `availableServices`
// and `ServiceKind` all come from the barrel, which re-exports the generated
// `stack_core_rust` binding surface.
import 'package:stack_core_dart/stack_core_dart.dart';

/// Absolute path to the host (macOS) dylib built with:
///   cargo build -p stack_core --features frb
/// Phase 0 host slice: tests load the artifact directly by path. A device/
/// desktop build matrix (bundling the library) comes later.
const _hostDylibPath =
    '/Users/rubensmachion/repos/Open/stack-connect-core/target/debug/libstack_core.dylib';

void main() {
  // FRB's RustLib is a singleton; initialize it once for the whole suite.
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(_hostDylibPath),
    );
  });

  tearDownAll(() {
    RustLib.dispose();
  });

  test('availableServices crosses the FRB boundary and returns the real value',
      () {
    final services = availableServices();

    // The real core (registry::available_services) returns exactly App Store
    // Connect today; assert the value made it across the boundary unchanged.
    expect(services, equals([ServiceKind.appStoreConnect]));
  });
}
