#!/usr/bin/env bash
#
# Bundles the stack_core Rust cdylib (flutter_rust_bridge) into the macOS app
# bundle so FRB resolves it at runtime.
#
# This mirrors the Windows runner, which installs stack_core.dll next to the
# executable via CMake (see apps/stack_desktop/windows/CMakeLists.txt). macOS
# uses CocoaPods + Xcode instead of CMake, so the equivalent is this Run Script
# build phase.
#
# IMPORTANT — why a framework, not a bare dylib:
# flutter_rust_bridge 2.12.0's macOS/iOS loader (see flutter_rust_bridge
# lib/src/loader/_io.dart) does NOT dlopen "libstack_core.dylib" by stem inside
# the bundle. After its non-packaged probe fails (Directory.current is "/" for a
# bundled .app), it falls back to ExternalLibrary.open("$stem.framework/$stem"),
# i.e. "stack_core.framework/stack_core". So the Rust core must be packaged as a
# proper macOS framework bundle named stack_core.framework whose binary is named
# "stack_core". The app's @executable_path/../Frameworks rpath then resolves it.
#
# This script builds that framework from the plain dylib: it lays out
# Contents/Frameworks/stack_core.framework/ (versioned bundle), copies the dylib
# in as the "stack_core" binary, rewrites its install name to
# @rpath/stack_core.framework/stack_core, writes a minimal Info.plist, and
# re-signs it.
#
# Source path resolution (first match wins):
#   1. $STACK_CORE_DYLIB                       (explicit override, absolute path)
#   2. sibling core repo's target/release dir  (default when repos are siblings)
#
# Override example (when the two repos are NOT checked out as siblings):
#   STACK_CORE_DYLIB=/abs/path/libstack_core.dylib flutter build macos
#
# This script is invoked from the Runner target's "Bundle stack_core dylib"
# Run Script build phase and relies on Xcode-provided environment variables
# (BUILT_PRODUCTS_DIR, FRAMEWORKS_FOLDER_PATH, EXPANDED_CODE_SIGN_IDENTITY, ...).
set -euo pipefail

DYLIB_NAME="libstack_core.dylib"
FRAMEWORK_NAME="stack_core"        # FRB stem; framework + binary share this name
BINARY_NAME="stack_core"

# --- Resolve the source dylib ------------------------------------------------

if [[ -n "${STACK_CORE_DYLIB:-}" ]]; then
  SOURCE_DYLIB="${STACK_CORE_DYLIB}"
else
  # SRCROOT == apps/stack_desktop/macos. The core repo is a sibling of the
  # stack-connect repo: macos -> stack_desktop -> apps -> flutter ->
  # stack-connect -> (parent) -> stack-connect-core (five levels up).
  SOURCE_DYLIB="${SRCROOT}/../../../../../stack-connect-core/target/release/${DYLIB_NAME}"
fi

if [[ ! -f "${SOURCE_DYLIB}" ]]; then
  echo "error: ${DYLIB_NAME} not found at: ${SOURCE_DYLIB}" >&2
  echo "error: build it in the core repo with" >&2
  echo "error:   cargo build --release -p stack_core --features frb" >&2
  echo "error: (or build/build-desktop.sh aarch64-apple-darwin), or set" >&2
  echo "error:   STACK_CORE_DYLIB=<abs path> when the repos are not siblings." >&2
  exit 1
fi

# --- Lay out the framework bundle --------------------------------------------

FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
FRAMEWORK_DIR="${FRAMEWORKS_DIR}/${FRAMEWORK_NAME}.framework"
VERSIONS_DIR="${FRAMEWORK_DIR}/Versions/A"
DEST_BINARY="${VERSIONS_DIR}/${BINARY_NAME}"

echo "==> Bundling ${FRAMEWORK_NAME}.framework"
echo "    from: ${SOURCE_DYLIB}"
echo "    to:   ${FRAMEWORK_DIR}"

# Rebuild from scratch so stale layouts never linger between builds.
rm -rf "${FRAMEWORK_DIR}"
mkdir -p "${VERSIONS_DIR}/Resources"

cp -f "${SOURCE_DYLIB}" "${DEST_BINARY}"
chmod u+w "${DEST_BINARY}"

# Standard versioned-framework symlinks (Current -> A, top-level -> Versions/A).
ln -sfh A "${FRAMEWORK_DIR}/Versions/Current"
ln -sfh "Versions/Current/${BINARY_NAME}" "${FRAMEWORK_DIR}/${BINARY_NAME}"
ln -sfh "Versions/Current/Resources" "${FRAMEWORK_DIR}/Resources"

# --- Minimal Info.plist ------------------------------------------------------

cat > "${VERSIONS_DIR}/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${BINARY_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>zeroSixteen.stackconnect.stack-core</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${FRAMEWORK_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
</dict>
</plist>
PLIST

# --- Fix the install name so @rpath resolution works -------------------------

install_name_tool -id "@rpath/${FRAMEWORK_NAME}.framework/${BINARY_NAME}" "${DEST_BINARY}"

# --- Re-sign the framework ---------------------------------------------------
#
# The implicit final CodeSign of the .app seals whatever is already inside
# Contents/Frameworks. We re-sign here (after rewriting the load command, which
# invalidates any prior signature) so the bundle signature stays consistent.
# Fall back to ad-hoc signing ("-") when no identity is configured (e.g. local
# debug builds with CODE_SIGNING_ALLOWED=NO).

if [[ "${CODE_SIGNING_ALLOWED:-YES}" == "YES" ]]; then
  SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
  echo "==> Code signing ${FRAMEWORK_NAME}.framework with identity: ${SIGN_IDENTITY}"
  codesign --force --sign "${SIGN_IDENTITY}" \
    ${OTHER_CODE_SIGN_FLAGS:-} \
    --timestamp=none \
    "${FRAMEWORK_DIR}"
else
  echo "==> Code signing disabled (CODE_SIGNING_ALLOWED=NO); skipping framework sign"
fi

echo "==> ${FRAMEWORK_NAME}.framework bundled successfully"
