# Plan: Shared Rust Core (native iOS + Flutter)

> **Status: this is no longer a proposal — the core exists and ships.** The shared crate
> `stack_core` lives in the separate repo
> [`stack-connect-core`](https://github.com/rubensmachion/stack-connect-core); App Store Connect is
> fully implemented and the native iOS app already runs on it via UniFFI. This document records the
> shared-core architecture and how the **Flutter (Android + Desktop)** apps plug into the same core
> via a **new Dart binding**. The authoritative core roadmap is
> `../stack-connect-core/RUST_CORE_PLAN.md` — defer to it for core internals/phases.

## Central Idea

A single **Rust** crate `stack_core` holds **all the logic** — the App Store Connect client (and,
later, Firebase / Google Play), JWT signing (ES256; RS256 later), OAuth token cache (later),
persistence via a host `BlobStore` callback, sync, domain models, and error translation. That crate
is consumed **natively** by two worlds through two *language-binding* generators:

```
                ┌──────────────── stack_core (Rust) ────────────────┐
                │  api · auth(JWT) · ports(BlobStore/CredentialStore)│
                │  sync · domain models · StackError                 │
                └───────┬───────────────────────────────┬───────────┘
                        │                                 │
                  UniFFI (Swift) — DONE          flutter_rust_bridge (Dart) — NEW
                        │                                 │
                  StackCoreRust.xcframework        stack_core_dart (.so/.dll)
                        │                                 │
              native iOS: wrap in            Flutter: wrap in Riverpod
              @Observable → SwiftUI          AsyncNotifier → Material / Fluent
```

> ✅ **The "iOS untouched" premise already changed — and the migration is done for Apple.** The iOS
> app no longer uses its Swift `appstoreconnect-swift-sdk`; it consumes the Rust core via the
> `StackCoreRust` XCFramework (local-path SwiftPM package `Packages/StackCoreRust`). The
> Firebase/Play providers are not in the core yet, so those parts of the app remain native until
> they are ported (see the core roadmap).

## What's in the Core (Rust) vs. What Stays Native

**Inside the core (shared):**
- `providers/appstore` — App Store Connect client (**implemented**): typed HTTP, `links.next`
  pagination, JSON:API envelopes, 14 capability objects.
- `auth::es256` — ES256 signer (`.p8` Apple) (**implemented**). RS256 + OAuth = **pending**
  (Firebase/Play).
- `ports` — host callbacks `CredentialStore`, `BlobStore` (the `SwiftDataStorable` equivalent),
  `DebugLogger` (**implemented**, `#[uniffi::export(with_foreign)]`).
- `service::sync::SyncService` — sync over `BlobStore` (**implemented**).
- `domain` — 31 `serde` record types (**implemented**).
- `error::StackError` — typed errors incl. `PendingAgreements` (Apple 403) (**implemented**).
- `routing/` — `stackconnect://` deep-link parser — **pending** (not in the core today).

**Stays native per platform (NOT in the core):**
- State management / controllers (Riverpod in Flutter, `@Observable`/`ObservableObject` on iOS).
- Widgets / Views; concrete navigation (`go_router` / `NavigationStack`). **Each Flutter platform
  has its own UI** (Material on Android, Fluent on desktop) — see `FLUTTER_PLAN.md`.
- **Secure storage** — via the `CredentialStore` callback: Keychain (iOS), `flutter_secure_storage`
  (Flutter).
- UI strings / l10n (`.xcstrings` on iOS, `.arb` on Flutter).
- Background scheduling (BGTask iOS / `workmanager` Android) and local notifications. *(No charts/
  analytics and no home-screen widgets — out of scope for the Flutter apps; see `FLUTTER_PLAN.md`.)*

## Tools / Crates

**Logic (Rust) — as actually used in `stack-connect-core`:**
- HTTP: `reqwest` 0.12 (TLS via `rustls`). JWT: `jsonwebtoken` 9 (ES256; RS256 when Google lands).
- JSON/models: `serde` + `serde_json`. Async: `tokio`. Errors: `thiserror`. Utils: `base64`,
  `async-trait`. Tests: `wiremock`.
- Persistence is **not** in the crate — it is delegated to the host via the `BlobStore` callback.

**Bindings:**
- **UniFFI** (`uniffi` 0.31, `tokio` feature) → Swift — **done**. `#[uniffi::export]` facade,
  `#[uniffi::Object]` provider + capabilities, `#[uniffi::Record]` domain, `#[uniffi::Error]`,
  foreign-trait callbacks. Built as static libs → **XCFramework** → consumed via SPM `binaryTarget`.
- **flutter_rust_bridge v2** → Dart — **the active next step**. A *separate* generator (not a
  `uniffi.toml` backend): it reads a designated Rust `api` module and generates idiomatic Dart +
  C-ABI glue. Build via `cargo-ndk` (Android `.so`) and cdylib (Windows `.dll` / Linux `.so`). See
  the *Dart binding* section of `FLUTTER_PLAN.md` for the facade + callback-adaptation details.

**Facade pattern:** a binding-agnostic core + a UniFFI facade (`facade.rs` / `bindings/swift`) +
(new) an FRB facade (`frb_api.rs` / `bindings/dart`). Each facade adapts types to its generator;
the core never depends on UniFFI/FRB.

## Build Matrix (Rust targets)

- **Apple (iOS) — done:** `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios` →
  merged into `StackCoreRust.xcframework` (`build/build-xcframework.sh`).
- **Android (Flutter) — new:** `aarch64-linux-android`, `armv7-linux-androideabi`,
  `x86_64-linux-android` (via `cargo-ndk`).
- **Desktop (Flutter) — new:** `x86_64-pc-windows-msvc`, `x86_64-unknown-linux-gnu` (+ `aarch64`).

The crate already declares `crate-type = ["staticlib", "cdylib", "lib"]`, so the `cdylib` the Dart
binding needs is present; only the Android/desktop build scripts are new.

## Repository Topology

The core, the iOS app, and the Android exploration are **separate repos** — not one monorepo:

```
stack-connect-core/         (the stack_core Rust crate — its OWN repo)
├── crates/stack_core/      src/{domain,ports,error,facade,auth,service,providers}
├── bindings/swift/         Package.swift + StackCoreRust.xcframework (generated, gitignored)
│                           └─ (new) bindings/dart/  + FRB facade + generated Dart
├── build/                  build-xcframework.sh  (+ new: build-android.sh, build-desktop.sh)
└── RUST_CORE_PLAN.md       (authoritative core roadmap)

stack-connect/              (the iOS app — THIS repo)
├── StackConnect/  StackConnectWidget/  Packages/
├── Packages/StackCoreRust/ (local-path copy of the core's Swift binding)
└── flutter/                (the Flutter monorepo — see FLUTTER_PLAN.md)
    └── core/               GIT SUBMODULE → stack-connect-core
```

iOS links the core via the local-path package `Packages/StackCoreRust` (xcframework rebuilt + copied
from the core). Flutter links it via a git submodule under `flutter/core`.

## Layers per Platform

| Layer | Native iOS | Flutter |
|---|---|---|
| Core (logic) | `stack_core` Rust (same crate) | `stack_core` Rust (same crate) |
| Binding | UniFFI → `StackCoreRust.xcframework` (done) | FRB → `stack_core_dart` (new) |
| State | `@Observable`/ViewModel | Riverpod `AsyncNotifier` (controllers, shared by both apps) |
| UI | SwiftUI | Material (`stack_mobile`) / Fluent (`stack_desktop`) — **distinct per platform** |
| Secure storage | Keychain (`CredentialStore` impl) | `flutter_secure_storage` (`CredentialStore` impl) |
| Strings | `Localizable.xcstrings` | `.arb` / `AppLocalizations` |

## iOS Migration Status (strangler — done for Apple)

1. ✅ Built `stack_core` + XCFramework and added it to `project.yml`.
2. ✅ Implemented `CredentialStore`/`BlobStore` in Swift over the existing Keychain/SwiftData.
3. ✅ Swapped App Store Connect to call the core; dropped `appstoreconnect-swift-sdk`.
4. ⏳ Firebase/Play remain native until ported to `providers/firebase` / `providers/googleplay` in
   the core (then swapped in the app, same pattern).

## Verification / Tests

- **Rust (bulk of coverage) — exists:** unit tests for `providers/appstore` with `wiremock` + JSON
  fixtures (URL/method/headers, DTO→domain, pagination, `PendingAgreements`); golden ES256;
  `registry` (kind→provider/schema); `sync` with an in-memory fake `BlobStore`. ~228+ tests.
- **Bindings (smoke):** UniFFI — XCTest crossing the boundary (host + simulator), **done**. FRB —
  a Dart test crossing the boundary, **to add** with the Dart binding.
- **Per platform:** iOS ViewModels and Flutter Riverpod controllers tested with the core mocked
  behind the binding.

## CI (GitHub Actions)

- **Core:** `cargo test` + `cargo clippy` + `cargo fmt --check`; XCFramework build; (new) Android
  `.so` via `cargo-ndk` + desktop cdylib; FRB-codegen-up-to-date check.
- **Apps:** after the core, per-platform builds (iOS; `assembleDebug` Android; desktop Linux).

## Trade-offs / Risks

- **Third language** (Rust) — team learning curve (already absorbed for iOS).
- **Two binding generators** to keep aligned (mitigated by the facade pattern; the core stays
  binding-agnostic).
- **Async bridging** and the **build matrix** add CI/tooling complexity.
- Upside, already realized for Apple: the critical logic (auth, API, persistence, sync) is written
  and **tested once** and runs identically on native iOS and the Flutter targets.
