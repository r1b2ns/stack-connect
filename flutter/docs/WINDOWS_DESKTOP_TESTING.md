# Windows Desktop Testing — Handoff (Flutter `stack_desktop`)

## Goal & Status

**Repository:** `stack-connect/flutter`, branch `experiment/flutter`  
**Sibling repo:** `stack-connect-core` provides the Rust core (`crates/stack_core`) consumed via flutter_rust_bridge (FRB).

**Phase 1 (Apple core MVP)** is DONE and green on macOS/Android. The one outstanding Phase 1 DoD item is: the desktop app (`apps/stack_desktop`, fluent_ui, Windows target) building and running on Windows, plus its `integration_test` passing on a Windows build. This could not be done on the macOS dev machine (`flutter build windows` requires Windows).

Desktop was retargeted Linux→Windows (see `../FLUTTER_PLAN.md`). The leftover `apps/stack_desktop/linux/` folder is unused.

---

## Two Test Tiers (READ FIRST)

There are two distinct tiers of validation for the Windows desktop build. **Read this carefully** — they have very different prerequisites and scopes.

### Tier A — Tests that need NO native library

Widget tests and `integration_test` use a **FAKE `CoreGateway`** (no real Rust core, no `.dll`). These should pass on Windows as soon as Flutter and the Visual Studio C++ toolchain are installed — **they do not require building `stack_core.dll`**.

These tests run on the host VM and validate the widget tree, navigation, and UI logic end-to-end without any dependency on the native library.

### Tier B — Running the real app

Running `flutter run -d windows` or `flutter build windows` **DOES require** the native `stack_core.dll` to be built and bundled+loaded. The wiring to do this automatically does NOT exist yet (see Outstanding Work section).

Only use Tier B if you want to manually smoke-test the app with the live Rust core. For Phase 1 DoD, Tier A (tests on a fake gateway) is sufficient and faster to validate.

---

## Prerequisites (Windows Machine)

- **Flutter SDK** stable (macOS dev used 3.44.2; match or newer). Run `flutter doctor` and ensure "Visual Studio - develop Windows apps" is a checkmark.
- **Visual Studio 2022** with the "Desktop development with C++" workload installed (MSVC compiler, CMake, Windows SDK). Required for any Windows desktop Flutter build.
- **Rust toolchain** (rustup) with the MSVC target: `rustup target add x86_64-pc-windows-msvc`.
- For regenerating bindings only (usually NOT needed — generated Dart is committed): `cargo install flutter_rust_bridge_codegen` pinned to 2.12.0.
- Both repos checked out as siblings: `stack-connect/` and `stack-connect-core/`.

---

## Tier A — Run the no-native tests (should pass immediately)

These commands run on the host VM and do not require the native library or Windows build toolchain. Run from `stack-connect/flutter`:

```powershell
flutter pub get
flutter analyze apps/stack_desktop
flutter test apps/stack_desktop
flutter test apps/stack_desktop/integration_test
```

**What to expect:**
- `flutter test apps/stack_desktop` runs widget tests using the fake `CoreGateway`.
- `flutter test apps/stack_desktop/integration_test` runs integration tests with a fake backend, validating the full widget tree and navigation flow end-to-end.
- Both should pass without any native library or DLL present.

**Success criteria:** All tests green, no library loading errors.

---

## Tier B — Build & run the real Windows app

### Step 1 — Build the native cdylib

The Rust core must be compiled to a Windows native library.

**Verified facts:**
- `crates/stack_core/Cargo.toml` already declares `crate-type = ["staticlib","cdylib","lib"]` and a `frb` feature (`frb = ["dep:flutter_rust_bridge"]`).
- The feature must be enabled during the build.

**Command** (from `stack-connect-core`):

```powershell
cargo build -p stack_core --features frb --release --target x86_64-pc-windows-msvc
```

**Output:** `target\x86_64-pc-windows-msvc\release\stack_core.dll`

Store or note the absolute path to this DLL for Step 2.

### Step 2 — Bundle + load the DLL (NOT WIRED YET)

**Status:** The Flutter Windows runner has no CMake wiring to copy `stack_core.dll` into the build output, and `RustLib.init()` will fail to find the library at runtime until it is placed next to the runner `.exe` (e.g. `build\windows\x64\runner\Debug\`) or on `PATH`.

**For a quick manual smoke test** before the CMake wiring exists:

1. Run `flutter build windows --debug` (this will likely fail at runtime due to the missing DLL, but it creates the directory structure).
2. Copy `stack_core.dll` next to the built runner executable:
   ```powershell
   Copy-Item -Path "C:\path\to\stack-connect-core\target\x86_64-pc-windows-msvc\release\stack_core.dll" -Destination "build\windows\x64\runner\Debug\"
   ```
3. Retry running or launching the app.

See Outstanding Work for the permanent CMake solution.

### Step 3 — Run / build

```powershell
flutter run -d windows
flutter build windows --debug
```

**What to expect:**
- `flutter run -d windows` launches the app on the Windows desktop.
- Watch for errors like "Unable to load dynamic library 'stack_core.dll'" (see Troubleshooting).

### Step 4 — Integration test on the Windows build

```powershell
flutter test apps/stack_desktop/integration_test -d windows
```

**Note:** The integration test uses the fake gateway, so it validates the real Windows widget tree/navigation end-to-end without needing the live Rust core. It should pass even if the real app cannot load the DLL at runtime (as long as the test harness can instantiate the fake gateway).

---

## Outstanding Work (What Must Be Built to Finish)

- [ ] **Desktop native build script** — create `build/build-desktop.ps1` (or `.sh`) in `stack-connect-core`, mirroring the existing `build/build-android.sh`, to build `stack_core.dll` for `x86_64-pc-windows-msvc` (release) and place it where the Windows runner can bundle it.

- [ ] **CMake wiring** in `apps/stack_desktop/windows/` (the runner `CMakeLists.txt` currently has NO native-lib wiring) to copy `stack_core.dll` into the runner output dir and the install bundle (alongside `flutter_windows.dll`), so `flutter build windows` self-contains the DLL. This is the desktop equivalent of Android's `jniLibs` + `build-android.sh`. Consider the FRB `rust_builder`/cargokit approach (auto-builds the DLL during the CMake step) as the clean long-term option.

- [ ] **Confirm FRB loader name** — the cdylib is `stack_core.dll`; verify `RustLib.init()`'s default external-library resolution finds it on Windows (adjust the loader/library name if needed).

- [ ] **Path portability for codegen** — `packages/stack_core_dart/flutter_rust_bridge.yaml` currently hardcodes ABSOLUTE macOS paths (`rust_root: /Users/rubensmachion/.../crates/stack_core`, `rust_output: /Users/.../frb_generated.rs`). These break regeneration on Windows. If you need to regenerate bindings on Windows, switch these to repo-relative paths first. (Not needed if you only build/run with the committed generated Dart.)

- [ ] **Remove the unused `apps/stack_desktop/linux/` folder** (desktop is Windows-only now).

- [ ] **CI job** — add a GitHub Actions Windows runner job: `flutter build windows` + `flutter test` (incl. integration) for `stack_desktop`, plus the cdylib build, so this stays green without a local Windows machine.

---

## DoD Checklist for the Windows Residual

- [ ] VS C++ toolchain installed and `flutter doctor` shows Visual Studio checkmark
- [ ] `flutter pub get` completes
- [ ] `flutter analyze apps/stack_desktop` passes
- [ ] `flutter test apps/stack_desktop` (widget tests) green
- [ ] `flutter test apps/stack_desktop/integration_test` (integration tests, no native) green
- [ ] `stack_core.dll` built from `stack-connect-core` with `--features frb --target x86_64-pc-windows-msvc`
- [ ] DLL bundled and loadable (CMake wiring OR manual copy)
- [ ] `flutter build windows` succeeds
- [ ] App launches and the add-account → apps → reviews → reply flow works (manual smoke test)
- [ ] `flutter test apps/stack_desktop/integration_test -d windows` green (integration test on real Windows build)
- [ ] CI Windows job added to GitHub Actions

---

## Troubleshooting

### "Unable to load dynamic library 'stack_core.dll'"

The DLL isn't next to the runner exe or not on PATH. 

**Solution:** Complete the CMake wiring (see Outstanding Work) or manually copy it (Tier B Step 2).

### `flutter doctor` missing Visual Studio

Visual Studio or the "Desktop development with C++" workload is not installed.

**Solution:** Install Visual Studio 2022 with the "Desktop development with C++" workload.

### Linker/target errors building the cdylib

The Rust target or feature flag is wrong.

**Solution:** Ensure `rustup target add x86_64-pc-windows-msvc` and build from `stack-connect-core` root with `cargo build -p stack_core --features frb --release --target x86_64-pc-windows-msvc`.

### `flutter test` fails with "Cannot load Flutter engine"

Flutter is not properly installed or `flutter doctor` shows failures.

**Solution:** Run `flutter doctor -v`, fix any reported issues, and retry.

---

## Next Steps

For the overall roadmap and what remains after this Phase 1 Windows residual, see `../FLUTTER_PLAN.md` (Phases 2–4).
