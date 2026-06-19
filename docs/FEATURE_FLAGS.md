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
| `useRustCoreForAppleApps` | `featureFlag.useRustCoreForAppleApps` | OFF | Routes **only** the Apple connection's `validateCredentials()` and `fetchApps()` through the shared Rust core (UniFFI `Provider`) instead of the Swift App Store Connect SDK. All other Apple methods stay on the Swift SDK. Fully reversible — turning it OFF restores the original Swift-SDK behaviour. |
| `useRustCoreDebugLogging` | `featureFlag.useRustCoreDebugLogging` | OFF | Debug-only HTTP tracer: logs every Rust-core App Store Connect request/response as a runnable cURL command (with pretty-printed JSON) to the Xcode console. Intended purely for diagnosing the Rust-core ASC integration during development. No effect when OFF (zero overhead). |

## Usage sites

### `useRustCoreForAppleApps`

- **Definition:** `StackConnect/Infra/FeatureFlags/FeatureFlags.swift` — `FeatureFlag.useRustCoreForAppleApps` (default `false`).
- **Read at:** `StackConnect/Infra/Providers/Apple/AppleAccountConnection.swift`
  - `validateCredentials()` — when ON, calls the Rust core `Provider.validate()`.
  - `fetchApps()` — when ON, calls the Rust core `Provider.fetchApps()` and maps `StackCoreRust.AppInfo` → `StackProtocols.AppInfo`.
  - `fetchBuilds(appId:limit:)` — when ON, calls the Rust core `Builds.fetchBuilds(appId:limit:)` and maps `StackCoreRust.BuildInfo` → `BuildModel` via `mapBuildInfo`. Eager list. Full fidelity: the core now enriches builds from the `included` relationships (preReleaseVersion / buildBetaDetail / betaAppReviewSubmission) and computes `iconUrl`, so `mapBuildInfo` maps every `BuildModel` field 1:1.
  - `fetchBuildsPage(appId:platform:processingStates:limit:pageAfterResponse:)` — when ON, calls the Rust core `Builds.fetchBuildsPage(appId:platform:processingStates:limit:pageToken:)` and maps `StackCoreRust.BuildInfo` → `BuildModel` via `mapBuildInfo`. Paginated list with platform/processingState filtering. The opaque `pageAfterResponse` token is the core's `nextToken` (a `String`); `hasNextPage` is `nextToken != nil`.
  - `fetchBuildsForGroup(groupId:)` — when ON, calls the Rust core `Builds.fetchBuildsForGroup(groupId:limit:200)` and maps `StackCoreRust.BuildInfo` → `BuildModel` via `mapBuildInfo`. Read only.
  - `fetchBuildDetail(buildId:)` — when ON, calls the Rust core `Builds.fetchBuildDetail(buildId:)` and maps `StackCoreRust.BuildDetailInfo` → `BuildDetailData` (`build` via `mapBuildInfo`, `betaGroups` via `mapBetaGroupInfo`, `localizations` via `mapBetaBuildLocalizationInfo`). Read only.
  - `fetchCurrentBuild(versionId:)` — when ON, calls the Rust core `Builds.fetchCurrentBuild(versionId:)` and maps the optional `StackCoreRust.BuildInfo?` → `BuildModel?` via `mapBuildInfo`. The capability guard runs before the graceful do/catch, so an attached-build lookup failure is swallowed to `nil` while a misconfigured provider still throws. Read only.
  - `fetchBetaGroups(appId:)` — when ON, calls the Rust core `BetaGroups.fetchBetaGroups(appId:limit:50)` and maps `StackCoreRust.BetaGroupInfo` → `BetaGroupModel` via `mapBetaGroupInfo`. Read only. Known degradation: `publicLinkId`, `publicLinkLimit`, `isPublicLinkLimitEnabled`, `testerCount` and `buildCount` are not provided by the core and come back `nil`/`false` on the Rust path.
  - `fetchBetaTestersForGroup(groupId:)` — when ON, calls the Rust core `BetaGroups.fetchBetaTesters(groupId:limit:200)` and maps `StackCoreRust.BetaTesterInfo` → `BetaTesterModel` via `mapBetaTesterInfo` (full fidelity, all fields map 1:1). Read only.
  - `createBetaGroup(appId:name:isInternal:isPublicLinkEnabled:hasAccessToAllBuilds:)` — when ON, calls the Rust core `BetaGroups.createBetaGroup(appId:name:isInternal:publicLinkEnabled:hasAccessToAllBuilds:)` and maps the returned `StackCoreRust.BetaGroupInfo` → `BetaGroupModel` via `mapBetaGroupInfo`. Same degraded fields as the read path (`publicLinkId`, `publicLinkLimit`, `isPublicLinkLimitEnabled`, `testerCount`, `buildCount` come back `nil`/`false`).
  - `updateBetaGroup(id:name:isPublicLinkEnabled:publicLinkLimit:isFeedbackEnabled:)` — when ON, calls the Rust core `BetaGroups.updateBetaGroup(groupId:name:publicLinkEnabled:publicLinkLimit:feedbackEnabled:)` (`publicLinkLimit` bridged `Int?` → `Int32?`); the returned `BetaGroupInfo` is discarded (method is `Void`).
  - `deleteBetaGroup(id:)` — when ON, calls the Rust core `BetaGroups.deleteBetaGroup(groupId:)`.
  - `addTesterToGroup(email:firstName:lastName:groupId:)` — when ON, calls the Rust core `BetaGroups.addBetaTester(groupId:email:firstName:lastName:)`; the returned `BetaTesterInfo` is discarded (method is `Void`).
  - `removeTesterFromGroup(testerId:groupId:)` — when ON, calls the Rust core `BetaGroups.removeBetaTester(groupId:testerId:)`.
  - `fetchTesterCount(groupId:)` — when ON, calls the Rust core `BetaGroups.fetchTesterCount(groupId:)` (returns `UInt32`, bridged to `Int` for the Swift signature). Read only.
  - `resendInvite(testerId:appId:)` — when ON, calls the Rust core `BetaGroups.resendInvite(testerId:appId:)` (method is `Void`).
  - `fetchBetaBuildLocalizations(buildId:)` — when ON, calls the Rust core `BetaBuildLocalizations.fetchBetaBuildLocalizations(buildId:limit:50)` and maps `StackCoreRust.BetaBuildLocalizationInfo` → `BetaBuildLocalizationModel` via `mapBetaBuildLocalizationInfo` (full fidelity, all fields map 1:1). Read only.
  - `createBetaBuildLocalization(buildId:locale:whatsNew:)` — when ON, calls the Rust core `BetaBuildLocalizations.createBetaBuildLocalization(buildId:locale:whatsNew:)`; the returned `BetaBuildLocalizationInfo` is discarded (method is `Void`).
  - `updateBetaBuildLocalization(id:whatsNew:)` — when ON, calls the Rust core `BetaBuildLocalizations.updateBetaBuildLocalization(id:whatsNew:)`; the returned `BetaBuildLocalizationInfo` is discarded (method is `Void`).
  - `fetchBetaAppLocalizations(appId:)` — when ON, calls the Rust core `BetaAppLocalizations.fetchBetaAppLocalizations(appId:limit:50)` and maps `StackCoreRust.BetaAppLocalizationInfo` → `BetaAppLocalizationModel` via `mapBetaAppLocalizationInfo` (full fidelity, all fields map 1:1). Read only.
  - `createBetaAppLocalization(appId:locale:feedbackEmail:description:)` — when ON, calls the Rust core `BetaAppLocalizations.createBetaAppLocalization(appId:locale:feedbackEmail:description:)` and maps the returned `BetaAppLocalizationInfo` → `BetaAppLocalizationModel` (the method returns the created model).
  - `updateBetaAppLocalization(id:feedbackEmail:description:)` — when ON, calls the Rust core `BetaAppLocalizations.updateBetaAppLocalization(id:feedbackEmail:description:)`; the returned `BetaAppLocalizationInfo` is discarded (method is `Void`).
  - `fetchAppInfoLocalizations(appInfoId:)` — when ON, calls the Rust core `AppMetadata.fetchAppInfoLocalizations(appInfoId:)` and maps `StackCoreRust.AppInfoLocalizationInfo` → `AppInfoLocalizationModel` via `mapAppInfoLocalizationInfo` (full fidelity, all 7 fields map 1:1). Read only.
  - `updateAppInfoLocalization(id:name:subtitle:)` — when ON, calls the Rust core `AppMetadata.updateAppInfoLocalization(id:name:subtitle:)`; the returned `AppInfoLocalizationInfo` is discarded (method is `Void`).
  - `updateAppInfoLocalizationPrivacy(id:privacyPolicyUrl:privacyChoicesUrl:privacyPolicyText:)` — when ON, calls the Rust core `AppMetadata.updateAppInfoLocalizationPrivacy(...)`; the returned `AppInfoLocalizationInfo` is discarded (method is `Void`).
  - `createAppInfoLocalization(appInfoId:locale:name:subtitle:)` — when ON, calls the Rust core `AppMetadata.createAppInfoLocalization(appInfoId:locale:name:subtitle:)` and maps the returned `AppInfoLocalizationInfo` → `AppInfoLocalizationModel` (the method returns the created model).
  - `deleteAppInfoLocalization(id:)` — when ON, calls the Rust core `AppMetadata.deleteAppInfoLocalization(id:)` (method is `Void`).
  - `AppleAccountConnection.fetchBetaAppReviewDetail(appId:)` — routes the TestFlight beta app review detail (Test Information) read through the Rust core when ON.
  - `AppleAccountConnection.updateBetaAppReviewDetail(model:)` — routes the beta app review detail update through the Rust core when ON.
  - `AppleAccountConnection.fetchAppReviewDetail(versionId:)` — routes the App Store version review detail (App Review Information) read through the Rust core when ON; maps the optional `StackCoreRust.AppReviewDetailInfo?` → `AppReviewDetailModel?` via `mapAppReviewDetailInfo`. The capability guard runs before the graceful do/catch, so a missing-detail lookup failure is swallowed to `nil` while a misconfigured provider still throws.
  - `AppleAccountConnection.updateAppReviewDetail(model:)` — routes the App Store version review detail update through the Rust core when ON.
  - `expireBuild(buildId:)` — when ON, calls the Rust core `Builds.expireBuild(buildId:)` (method is `Void`).
  - `attachBuild(versionId:buildId:)` — when ON, calls the Rust core `Builds.attachBuild(versionId:buildId:)` (method is `Void`).
  - `submitBuildForBetaReview(buildId:)` — when ON, calls the Rust core `Builds.submitBuildForBetaReview(buildId:)` (method is `Void`).
  - `removeBuildFromGroup(buildId:groupId:)` — when ON, calls the Rust core `Builds.removeBuildFromGroup(buildId:groupId:)` (method is `Void`).
  - `addBuildToGroups(buildId:groupIds:)` — when ON, calls the Rust core `Builds.addBuildToGroups(buildId:groupIds:)` (`[String]` bridged to the core; method is `Void`).
  - `fetchAppInfo(appId:)` — when ON, calls the Rust core `AppMetadata.fetchAppInfo(appId:)` and maps `StackCoreRust.AppInfoDetails` → `AppInfoModel` (via `mapAppInfoDetails`, computing category/subcategory display names from IDs) plus its `AgeRatingDeclarationInfo` → `AgeRatingDeclarationModel` (via `mapAgeRatingDeclarationInfo`). Read only.
  - `fetchAppCategories()` — when ON, calls the Rust core `AppMetadata.fetchAppCategories()` and maps each `StackCoreRust.AppCategoryInfo` → `AppCategoryModel` via `mapAppCategoryInfo` (subcategory IDs nested as leaf models). Read only.
  - `updateAppInfoCategory(appInfoId:primaryCategoryId:subcategoryOneId:secondaryCategoryId:secondarySubcategoryOneId:)` — when ON, calls the Rust core `AppMetadata.updateAppInfoCategory(...)` (method is `Void`).
  - `updateApp(id:contentRightsDeclaration:primaryLocale:)` — when ON, calls the Rust core `AppMetadata.updateApp(id:contentRightsDeclaration:primaryLocale:)` (method is `Void`).
  - `updateAgeRating(id:...)` — when ON, calls the Rust core `AppMetadata.updateAgeRating(id:...)` (all 18 declaration params bridged 1:1; method is `Void`).
  - `fetchIconUrl(appId:)` — when ON, calls the Rust core `AppMetadata.fetchIconUrl(appId:)`; NON-throwing best-effort: any Rust-core failure is swallowed to `nil` inside the branch's `do/catch`.
  - `submitForReview(appId:versionId:platform:)` — when ON, calls the Rust core `AppStoreVersions.submitForReview(appId:versionId:platform:)` (the Swift `AppPlatform?` is bridged via `platform?.rawValue` → the core's `String?`; method is `Void`).
  - `cancelReview(appId:)` — when ON, calls the Rust core `AppStoreVersions.cancelReview(appId:)` (method is `Void`).
  - `releaseVersion(versionId:)` — when ON, calls the Rust core `AppStoreVersions.releaseVersion(versionId:)` (method is `Void`).
  - `rejectVersion(appId:)` — when ON, calls the Rust core `AppStoreVersions.rejectVersion(appId:)` (method is `Void`).
  - `fetchPhasedRelease(versionId:)` — when ON, calls the Rust core `AppStoreVersions.fetchPhasedRelease(versionId:)` and maps the optional `StackCoreRust.PhasedReleaseInfo?` → `PhasedReleaseModel?` via `mapPhasedReleaseInfo`. The capability guard runs before the graceful do/catch, so a missing phased release is swallowed to `nil` while a misconfigured provider still throws. Read only.
  - `createPhasedRelease(versionId:state:)` — when ON, calls the Rust core `AppStoreVersions.createPhasedRelease(versionId:state:)` (the SDK `PhasedReleaseState` is bridged via `state.rawValue` → the core's `String`) and maps the returned `StackCoreRust.PhasedReleaseInfo` → `PhasedReleaseModel` via `mapPhasedReleaseInfo`.
  - `deletePhasedRelease(id:)` — when ON, calls the Rust core `AppStoreVersions.deletePhasedRelease(id:)` (method is `Void`).
  - `updatePhasedReleaseState(id:state:)` — when ON, calls the Rust core `AppStoreVersions.updatePhasedReleaseState(id:state:)` (`PhasedReleaseState` bridged via `state.rawValue` → the core's `String`) and maps the returned `StackCoreRust.PhasedReleaseInfo` → `PhasedReleaseModel` via `mapPhasedReleaseInfo`.
  - `fetchLocalizations(versionId:)` — when ON, calls the Rust core `AppStoreVersions.fetchLocalizations(versionId:)` and maps `StackCoreRust.AppStoreLocalizationInfo` → `AppStoreLocalizationModel` via `mapAppStoreLocalizationInfo`. Read only.
  - `updateLocalization(id:description:keywords:promotionalText:supportUrl:marketingUrl:whatsNew:)` — when ON, calls the Rust core `AppStoreVersions.updateLocalization(id:description:keywords:promotionalText:supportUrl:marketingUrl:whatsNew:)` (method is `Void`).
  - `fetchScreenshotSets(localizationId:)` — when ON, calls the Rust core `AppStoreVersions.fetchScreenshotSets(localizationId:)` and maps `StackCoreRust.ScreenshotSetInfo` → `ScreenshotSetModel` via `mapScreenshotSetInfo` (each nested `ScreenshotInfo` mapped via `mapScreenshotInfo`, widening `Int32?` dimensions to `Int?`). Read only.
  - `fetchTeamMembers()` — when ON, calls the Rust core `Users.fetchTeamMembers()` and maps `StackCoreRust.TeamMemberInfo` → `TeamMemberModel` via `mapTeamMemberInfo` (full fidelity, all fields map 1:1). Read only.
  - `fetchUsers()` — when ON, calls the Rust core `Users.fetchUsers()` and maps `StackCoreRust.UserInfo` → `UserModel` via `mapUserInfo` (the core unifies active members + pending invitations into one list; the raw ISO8601 `expirationDate` is parsed via `parseISO8601Date`). Read only.
  - `inviteUser(email:firstName:lastName:roles:allAppsVisible:provisioningAllowed:)` — when ON, calls the Rust core `Users.inviteUser(...)` (`roles` passed straight through as `[String]`; method is `Void`).
  - `deleteUser(id:isPending:)` — when ON, calls the Rust core `Users.deleteUser(id:isPending:)` (`isPending` selects the invitation-cancel vs user-delete path inside the core; method is `Void`).
  - `fetchAccessibilityDeclarations(appId:)` — when ON, calls the Rust core `AccessibilityDeclarations.fetchAccessibilityDeclarations(appId:limit:20)` and maps `StackCoreRust.AccessibilityDeclarationInfo` → `AccessibilityDeclarationModel` via `mapAccessibilityDeclarationInfo` (full fidelity, all 11 fields map 1:1). Read only.
  - `createAccessibilityDeclaration(appId:deviceFamily:)` — when ON, validates `deviceFamily` up front (shared by both paths), then calls the Rust core `AccessibilityDeclarations.createAccessibilityDeclaration(appId:deviceFamily:)` and maps the returned `AccessibilityDeclarationInfo` → `AccessibilityDeclarationModel` (the method returns the created model).
  - `updateAccessibilityDeclaration(_:publish:)` — when ON, calls the Rust core `AccessibilityDeclarations.updateAccessibilityDeclaration(id:publish:supports…)` passing the 9 support booleans; the returned `AccessibilityDeclarationInfo` is discarded (method is `Void`).
  - `deleteAccessibilityDeclaration(id:)` — when ON, calls the Rust core `AccessibilityDeclarations.deleteAccessibilityDeclaration(id:)` (method is `Void`).
  - `fetchDevices()` — when ON, calls the Rust core `Devices.fetchDevices()` and maps `StackCoreRust.DeviceInfo` → `DeviceModel` via `mapDeviceInfo` (every field maps 1:1; the raw ISO8601 `addedDate` is parsed via `parseISO8601Date`). Read only.
  - `createDevice(name:platformRaw:udid:)` — when ON, validates `platformRaw` (`BundleIDPlatform`) up front (shared by both paths), then calls the Rust core `Devices.createDevice(name:platform:udid:)` and maps the returned `DeviceInfo` → `DeviceModel` (the method returns the created model).
  - `updateDevice(id:name:status:)` — when ON, calls the Rust core `Devices.updateDevice(id:name:status:)`; the call is `Void` so any core return is discarded.
  - `fetchBundleIds()` — when ON, calls the Rust core `BundleIds.fetchBundleIds()` and maps `StackCoreRust.BundleIdInfo` → `BundleIdentifierModel` via `mapBundleIdInfo` (every field maps 1:1; `seedId` is optional and passes straight through). Read only.
  - `createBundleId(identifier:name:platformRaw:)` — when ON, validates `platformRaw` (`BundleIDPlatform`) up front (shared by both paths), then calls the Rust core `BundleIds.createBundleId(identifier:name:platform:)` and maps the returned `BundleIdInfo` → `BundleIdentifierModel` (the method returns the created model).
  - `updateBundleId(id:name:)` — when ON, calls the Rust core `BundleIds.updateBundleId(id:name:)`; the call is `Void` so any core return is discarded.
  - `deleteBundleId(id:)` — when ON, calls the Rust core `BundleIds.deleteBundleId(id:)` (method is `Void`).
  - `fetchBundleIdCapabilities(bundleId:)` — when ON, calls the Rust core `BundleIds.fetchBundleIdCapabilities(bundleId:)` and maps `StackCoreRust.BundleIdCapabilityInfo` → `BundleIdentifierCapabilityModel` via `mapBundleIdCapabilityInfo` (both fields map 1:1). Read only.
  - `enableCapability(bundleId:capabilityTypeRaw:)` — when ON, passes `capabilityTypeRaw` STRAIGHT to the Rust core `BundleIds.enableCapability(bundleId:capabilityType:)` WITHOUT the SDK path's `CapabilityType` enum validation (the core accepts any raw string, so newer types such as `FONT_INSTALLATION` work — a deliberate improvement over the SDK path), and maps the returned `BundleIdCapabilityInfo` → `BundleIdentifierCapabilityModel` (the method returns the created model).
  - `disableCapability(capabilityId:)` — when ON, calls the Rust core `BundleIds.disableCapability(capabilityId:)` (method is `Void`).
  - `fetchCertificates()` — when ON, calls the Rust core `Certificates.fetchCertificates()` and maps `StackCoreRust.CertificateInfo` → `CertificateModel` via `mapCertificateInfo` (the core already applies the `displayName` fallback; the raw ISO8601 `expirationDate` is parsed via `parseISO8601Date`). Read only.
  - `fetchCertificateContent(id:)` — when ON, calls the Rust core `Certificates.fetchCertificateContent(id:)` and returns the optional `String?` content straight through. Read only.
  - `createCertificate(csrContent:certificateTypeRaw:passTypeId:merchantId:)` — when ON, passes `certificateTypeRaw` STRAIGHT to the Rust core `Certificates.createCertificate(csrContent:certificateType:passTypeId:merchantId:)` WITHOUT the SDK path's `CertificateType(rawValue:)` validation (the core accepts any raw string, so newer types work — a deliberate improvement over the SDK path, which keeps the enum validation), and maps the returned `CertificateInfo` → `CertificateModel` via `mapCertificateInfo` (the method returns a `CreatedCertificate` wrapping the model plus the optional `certificateContent`).
  - `revokeCertificate(id:)` — when ON, calls the Rust core `Certificates.revokeCertificate(id:)` (method is `Void`).
- **Supporting types:**
  - `StackConnect/Infra/Providers/Apple/AppleCredentialStore.swift` — bridges `AppleCredentials` to the Rust core's `CredentialStore` (`issuerId` / `keyId` / `privateKeyP8`).
  - Package: `Packages/StackCoreRust` (vendored `StackCoreRust.xcframework` + generated UniFFI wrapper).

### `useRustCoreDebugLogging`

- **Definition:** `StackConnect/Infra/FeatureFlags/FeatureFlags.swift` — `FeatureFlag.useRustCoreDebugLogging` (default `false`).
- **Read at:** `StackConnect/Infra/Providers/Apple/AppleAccountConnection.swift`
  - `rustCoreProvider()` — when ON, passes a `RustCoreDebugLogger()` as the `debugLogger:` argument to the Rust core's `connect(...)`, so the core logs every App Store Connect HTTP call it makes as a runnable cURL (pretty JSON request/response) to the Xcode console. When OFF, passes `nil` (no logging, zero overhead).
- **Supporting types:**
  - `StackConnect/Infra/Providers/Apple/RustCoreDebugLogger.swift` — a stateless `DebugLogger` that forwards the core's traces straight to the Xcode console via `print` (not `Log.print`, which truncates long messages).
- **Runtime usage:** enable at launch via the launch argument `-featureFlag.useRustCoreDebugLogging YES` (Xcode scheme → Run → Arguments → *Arguments Passed On Launch*), or programmatically with `FeatureFlags.shared.setEnabled(true, for: .useRustCoreDebugLogging)`.

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
