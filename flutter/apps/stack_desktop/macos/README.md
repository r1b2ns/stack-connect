# macOS desktop runner

The `macos/` runner was added for **local-dev convenience** on Apple-Silicon
Macs. Windows and Linux remain the primary desktop targets; macOS exists so the
app can be built and run locally (`flutter run -d macos`) without a Windows/Linux
machine or VM.

## Building the Rust core first

The app loads the `stack_core` Rust core via flutter_rust_bridge (FRB). Build the
native library in the sibling core repo before building the macOS app:

```bash
# In stack-connect-core/
cargo build --release -p stack_core --features frb
# produces target/release/libstack_core.dylib
```

or, via the build helper (emits target/aarch64-apple-darwin/release/):

```bash
# In stack-connect-core/
build/build-desktop.sh macos
```

Then build the app:

```bash
# In flutter/apps/stack_desktop/
flutter build macos --debug      # or: flutter run -d macos
```

## How the Rust core is bundled

Unlike Windows (CMake `install(FILES ...)`), macOS uses CocoaPods + Xcode, so a
**Run Script build phase** ("Bundle stack_core dylib") handles bundling. It runs
`macos/scripts/bundle_stack_core.sh`, which:

1. Locates `libstack_core.dylib` (default: the sibling core repo's
   `target/release/`; override with the `STACK_CORE_DYLIB` env var when the two
   repos are not checked out as siblings).
2. Repackages it as a **`stack_core.framework`** inside `Contents/Frameworks/`.
   FRB 2.12.0's macOS loader opens `stack_core.framework/stack_core` (a framework
   bundle), **not** a bare `libstack_core.dylib` — see the script header for the
   loader details.
3. Rewrites the install name to `@rpath/stack_core.framework/stack_core` and
   re-signs the framework. The app already carries
   `@executable_path/../Frameworks` on its rpath, so the framework resolves at
   runtime.

If the dylib is missing the build fails with a clear error (mirroring the Windows
CMake warning).

### Overriding the dylib location

```bash
STACK_CORE_DYLIB=/abs/path/libstack_core.dylib flutter build macos --debug
```

## Distribution notes (out of scope for local dev)

- The bundled framework is **arm64-only**. For an Intel-compatible build, produce
  an `x86_64-apple-darwin` slice and `lipo` it into a universal binary before
  bundling.
- Local builds sign the framework **ad-hoc**. For notarized distribution, build
  with a Developer ID identity so the framework is signed with the app's team and
  the bundle can be notarized.
- The app runs under the **App Sandbox** with `com.apple.security.network.client`
  enabled (required for the Rust core's outbound App Store Connect / Firebase
  API calls).
