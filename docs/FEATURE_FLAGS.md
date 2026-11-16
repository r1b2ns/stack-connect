# Feature Flags

This document tracks every feature flag in the StackConnect iOS app.

Flags are defined in `FeatureFlag` and resolved through `FeatureFlags`
(`StackConnect/Infra/FeatureFlags/FeatureFlags.swift`). They are backed by
`UserDefaults` (keys are namespaced under `featureFlag.`), so a flag can be toggled
at runtime — e.g. via a debug menu or a launch argument — without rebuilding. Every
new flag ships **OFF** by default (the safe, fully-reversible value) unless noted.

**Total feature flags: 2**

## Flags

| Flag (`FeatureFlag` case) | UserDefaults key | Default | Description |
| --- | --- | --- | --- |
| `useRustCoreDebugLogging` | `featureFlag.useRustCoreDebugLogging` | OFF | Debug-only tracer. (1) HTTP: logs every Rust-core App Store Connect request/response as a runnable cURL command (with pretty-printed JSON) to the Xcode console. (2) Import: also prints the FULL decrypted `.scexport` JSON payload to the Xcode console on account import. Intended purely for diagnosing the Rust-core ASC integration during development. No effect when OFF (zero overhead). Both are additionally gated by `#if DEBUG`, so the credential-bearing payload can never be printed in a release build. |
| `googlePlayReleaseWrites` | `featureFlag.googlePlayReleaseWrites` | OFF (ON in fake data mode) | Gates every Google Play release write entry point (plan `google-play-releases.md` R6): release detail bottom bar and editable metadata, swipe actions on release rows, the staged rollout sheet, the review checklist and the New Release / Promote sheet. Read-only release status and detail are not gated. Turned ON for the launch (in memory, never persisted) while the DEBUG fake data mode runs. |

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

### `googlePlayReleaseWrites`

- **Definition:** `StackConnect/Infra/FeatureFlags/FeatureFlags.swift` — `FeatureFlag.googlePlayReleaseWrites`.
- **Read at:** `StackConnect/Infra/Providers/GooglePlay/GooglePlayReleaseWriteAccess.swift`
  - `denialMessage(_:account:app:featureFlags:)` / `isAllowed(...)` — the single policy every write entry point asks (flag ON, app in the account's scope, `canEdit(.version)` to change a release, `canAdd(.version)` to create or promote one). When OFF, every write entry point is hidden and a write is refused before any edit is opened.
- **Entry points gated through it:**
  - `StackConnect/Infra/Providers/GooglePlay/GooglePlayReleaseWriter.swift` — `apply(_:track:options:)` and `fetchBundles()` refuse before any request when denied (defense in depth).
  - `StackConnect/Modules/GooglePlayReleaseWrites/GooglePlayReleaseWriteViewModel.swift` — `canPerform(_:)`, `start(_:release:track:)`, `request(_:)`, `confirm(_:)`, `openNewRelease(track:)`, `openRollout(release:track:)`.
  - `StackConnect/Modules/GooglePlayTracks/GooglePlayReleaseDetailViewModel.swift` — bottom bar actions and editable name / notes / priority (`canEditMetadata`).
  - `StackConnect/Modules/GooglePlayAppDetail/GooglePlayAppDetailViewModel.swift` — `releaseActions(for:in:)` (swipe actions); `GooglePlayAppDetailView` — the "+" New Release button.
  - `StackConnect/Modules/GooglePlayTracks/GooglePlayTracksView.swift` — the "+" on each track header.
- **Session default:** `StackConnect/Infra/FakeData/FakeDataBootstrap.swift` — `install(mode:clock:)` sets `FeatureFlags.sessionDefaults[.googlePlayReleaseWrites] = true`, so the fake data mode runs with writes ON without persisting anything (a stored value still wins).
- **Runtime usage:** `-featureFlag.googlePlayReleaseWrites YES` as a launch argument, or `FeatureFlags.shared.setEnabled(true, for: .googlePlayReleaseWrites)`.

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
