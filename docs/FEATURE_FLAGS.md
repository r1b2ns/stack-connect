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
| `useRustCoreForAppleApps` | `featureFlag.useRustCoreForAppleApps` | OFF | Routes **only** the Apple connection's `validateCredentials()` and `fetchApps()` through the shared Rust core (UniFFI `Provider`) instead of the Swift App Store Connect SDK. All other Apple methods stay on the Swift SDK. Fully reversible — turning it OFF restores the original Swift-SDK behaviour. |

## Usage sites

### `useRustCoreForAppleApps`

- **Definition:** `StackConnect/Infra/FeatureFlags/FeatureFlags.swift` — `FeatureFlag.useRustCoreForAppleApps` (default `false`).
- **Read at:** `StackConnect/Infra/Providers/Apple/AppleAccountConnection.swift`
  - `validateCredentials()` — when ON, calls the Rust core `Provider.validate()`.
  - `fetchApps()` — when ON, calls the Rust core `Provider.fetchApps()` and maps `StackCoreRust.AppInfo` → `StackProtocols.AppInfo`.
  - `fetchBuilds(appId:limit:)` — when ON, calls the Rust core `Builds.fetchBuilds(appId:limit:)` and maps `StackCoreRust.BuildInfo` → `BuildModel` via `mapBuildInfo`. Eager list only; `fetchBuildsPage(...)` stays on the Swift SDK (core lacks platform/processingState filtering and page cursors). Known degradation: relationship-sourced fields (`marketingVersion`, `iconUrl`, `platform`, beta/internal states, etc.) come back empty on the Rust path.
  - `fetchBetaGroups(appId:)` — when ON, calls the Rust core `BetaGroups.fetchBetaGroups(appId:limit:50)` and maps `StackCoreRust.BetaGroupInfo` → `BetaGroupModel` via `mapBetaGroupInfo`. Read only. Known degradation: `publicLinkId`, `publicLinkLimit`, `isPublicLinkLimitEnabled`, `testerCount` and `buildCount` are not provided by the core and come back `nil`/`false` on the Rust path.
  - `fetchBetaTestersForGroup(groupId:)` — when ON, calls the Rust core `BetaGroups.fetchBetaTesters(groupId:limit:200)` and maps `StackCoreRust.BetaTesterInfo` → `BetaTesterModel` via `mapBetaTesterInfo` (full fidelity, all fields map 1:1). Read only; `fetchTesterCount(groupId:)` stays on the Swift SDK.
  - `createBetaGroup(appId:name:isInternal:isPublicLinkEnabled:hasAccessToAllBuilds:)` — when ON, calls the Rust core `BetaGroups.createBetaGroup(appId:name:isInternal:publicLinkEnabled:hasAccessToAllBuilds:)` and maps the returned `StackCoreRust.BetaGroupInfo` → `BetaGroupModel` via `mapBetaGroupInfo`. Same degraded fields as the read path (`publicLinkId`, `publicLinkLimit`, `isPublicLinkLimitEnabled`, `testerCount`, `buildCount` come back `nil`/`false`).
  - `updateBetaGroup(id:name:isPublicLinkEnabled:publicLinkLimit:isFeedbackEnabled:)` — when ON, calls the Rust core `BetaGroups.updateBetaGroup(groupId:name:publicLinkEnabled:publicLinkLimit:feedbackEnabled:)` (`publicLinkLimit` bridged `Int?` → `Int32?`); the returned `BetaGroupInfo` is discarded (method is `Void`).
  - `deleteBetaGroup(id:)` — when ON, calls the Rust core `BetaGroups.deleteBetaGroup(groupId:)`.
  - `addTesterToGroup(email:firstName:lastName:groupId:)` — when ON, calls the Rust core `BetaGroups.addBetaTester(groupId:email:firstName:lastName:)`; the returned `BetaTesterInfo` is discarded (method is `Void`).
  - `removeTesterFromGroup(testerId:groupId:)` — when ON, calls the Rust core `BetaGroups.removeBetaTester(groupId:testerId:)`.
- **Supporting types:**
  - `StackConnect/Infra/Providers/Apple/AppleCredentialStore.swift` — bridges `AppleCredentials` to the Rust core's `CredentialStore` (`issuerId` / `keyId` / `privateKeyP8`).
  - Package: `Packages/StackCoreRust` (vendored `StackCoreRust.xcframework` + generated UniFFI wrapper).

## How to toggle (debug / testing)

The flag reads from `UserDefaults.standard`, so it can be flipped without a rebuild:

```swift
// Turn ON
FeatureFlags.shared.setEnabled(true, for: .useRustCoreForAppleApps)

// Turn OFF (restore Swift-SDK behaviour)
FeatureFlags.shared.setEnabled(false, for: .useRustCoreForAppleApps)
```

Or via a launch argument / scheme environment override on the `featureFlag.useRustCoreForAppleApps` key.

In tests, inject a custom `UserDefaults` into `FeatureFlags(defaults:)` and then into
`AppleAccountConnection(credentials:featureFlags:)` to exercise both states.
