# StackConnect — Windows logic PoC (phase 3)

Headless proof-of-concept that proves the migrated, platform-agnostic logic
compiles **and runs** on Windows — before any UI work. No SwiftUI, no UIKit.

It links only the shared packages:
`StackProtocols`, `StackCrypto`, `StackStorageSQLite`, `APIProviderFirebase`,
`APIProviderPlay` (+ `swift-crypto`).

## Prerequisites (Windows)

1. Install the **Swift toolchain for Windows**: <https://www.swift.org/install/windows/>
   (includes the required Visual Studio Build Tools / Windows SDK).
2. Open a terminal where `swift --version` works.

## Run

```powershell
cd WindowsPoC

# Core gate: SQLite CRUD + AES-GCM/PBKDF2 crypto + RS256 sign/verify + PEM parse
swift run StackConnectWindowsPoC

# Secrets gate: Windows Credential Manager write / read / delete round-trip
swift run WindowsSecretsProbe
```

Expected core output (the important line is the last one):

```
StackConnect — shared logic PoC  (platform: Windows)

  ✅ SQLite CRUD round-trip (SQLitePersistentStorable)
  ✅ AccountCrypto AES-GCM + PBKDF2 round-trip (StackCrypto)
  ✅ RS256 sign + verify (_RSA.Signing)
  ✅ RSA PEM round-trip (_RSA.Signing.PrivateKey pemRepresentation)
  ⏭️  FirebaseConfiguration — set FIREBASE_SA_JSON ...
  ⏭️  PlayConfiguration — set PLAY_SA_JSON ...

All checks passed ✅
```

The process exits non-zero if any check fails.

### Optional: validate real service-account keys

Point the env vars at real `.json` service-account files to also exercise PEM
parsing on real RSA keys (no network call):

```powershell
$env:FIREBASE_SA_JSON = "C:\path\to\firebase-sa.json"
$env:PLAY_SA_JSON     = "C:\path\to\play-sa.json"
swift run StackConnectWindowsPoC
```

## App Store Connect SDK gate

The `appstoreconnect-swift-sdk` Windows-compatibility check lives in the sibling
[`../ASCBuildProbe`](../ASCBuildProbe) package (isolated so its result is
independent of this PoC):

```powershell
cd ../ASCBuildProbe
swift build      # success == the SDK compiles for the Windows toolchain
swift run        # also link-checks it
```

If it fails to build on Windows, that's the signal to patch/fork the SDK or
reimplement the ASC client on top of `swift-crypto` (same ES256 approach).

## Status of each check

| Check | Validated on macOS | Needs Windows to confirm |
|-------|:---:|:---:|
| SQLite CRUD | ✅ | runs identically |
| AES-GCM + PBKDF2 | ✅ | runs identically |
| RS256 sign/verify | ✅ | runs identically |
| PEM round-trip | ✅ | runs identically |
| Credential Manager | n/a (stub) | ⚠️ **first real run is on Windows** |
| ASC SDK build | ✅ | ⚠️ **the actual gate is on Windows** |

The Windows Credential Manager code (`WindowsSecretsProbe`) has been written
against the Win32 API but not yet executed on Windows — this probe is how you
confirm it.
