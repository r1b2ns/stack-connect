# Feature Flags

This document tracks every feature flag in the StackConnect iOS app.

Flags are defined in `FeatureFlag` and resolved through `FeatureFlags`
(`StackConnect/Infra/FeatureFlags/FeatureFlags.swift`). They are backed by
`UserDefaults` (keys are namespaced under `featureFlag.`), so a flag can be toggled
at runtime — e.g. via a debug menu or a launch argument — without rebuilding. Every
new flag ships **OFF** by default (the safe, fully-reversible value) unless noted.

**Total feature flags: 1**

## Flags

| Flag (`FeatureFlag` case) | UserDefaults key | Default | Description |
| --- | --- | --- | --- |
| `useRustCoreDebugLogging` | `featureFlag.useRustCoreDebugLogging` | OFF | Debug-only tracer. (1) HTTP: logs every Rust-core App Store Connect request/response as a runnable cURL command (with pretty-printed JSON) to the Xcode console. (2) Import: also prints the FULL decrypted `.scexport` JSON payload to the Xcode console on account import. Intended purely for diagnosing the Rust-core ASC integration during development. No effect when OFF (zero overhead). Both are additionally gated by `#if DEBUG`, so the credential-bearing payload can never be printed in a release build. |

## Usage sites

### `useRustCoreDebugLogging`

- **Definition:** `StackConnect/Infra/FeatureFlags/FeatureFlags.swift` — `FeatureFlag.useRustCoreDebugLogging`.
- **Read at:** `StackConnect/Infra/Providers/Apple/AppleAccountConnection.swift`
  - `rustCoreProvider()` — when ON, passes a `RustCoreDebugLogger()` as the `debugLogger:` argument to the Rust core's `connect(...)`, so the core logs every App Store Connect HTTP call it makes as a runnable cURL (pretty JSON request/response) to the Xcode console. When OFF, passes `nil` (no logging, zero overhead).
- **Read at:** `StackConnect/Infra/Crypto/AccountCrypto.swift`
  - `decrypt(data:password:)` — when ON, prints the FULL decrypted `.scexport` JSON payload to the Xcode console right before returning it (covers all four call sites that import an account: `SettingsAccountsViewModel`, `SettingsAccountsView`, `AccountsListView`, `AccountsListViewModel`). Uses `print` (not `Log.print`) so the whole payload is visible, and is additionally wrapped in `#if DEBUG` because the payload carries credentials (issuerID / privateKeyID / the `.p8` private key / serviceAccountJSON) that must never be printable in a release build. When OFF, nothing is logged (zero overhead).
- **Supporting types:**
  - `StackConnect/Infra/Providers/Apple/RustCoreDebugLogger.swift` — a stateless `DebugLogger` that forwards the core's traces straight to the Xcode console via `print` (not `Log.print`, which truncates long messages).
- **Runtime usage:** enable at launch via the launch argument `-featureFlag.useRustCoreDebugLogging YES` (Xcode scheme → Run → Arguments → *Arguments Passed On Launch*), or programmatically with `FeatureFlags.shared.setEnabled(true, for: .useRustCoreDebugLogging)`.

## How to toggle (debug / testing)

The flag reads from `UserDefaults.standard`, so it can be flipped without a rebuild:

```swift
// Turn ON
FeatureFlags.shared.setEnabled(true, for: .useRustCoreDebugLogging)

// Turn OFF
FeatureFlags.shared.setEnabled(false, for: .useRustCoreDebugLogging)
```

Or via a launch argument / scheme environment override on the `featureFlag.useRustCoreDebugLogging` key.

In tests, inject a custom `UserDefaults` into `FeatureFlags(defaults:)` and then into
`AppleAccountConnection(credentials:featureFlags:)` to exercise the flag state.
