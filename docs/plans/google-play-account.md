# Implementation Plan — Google Play account type (backed by the Rust core)

> Branch: `feat/play-store-account` (iOS) — pairs with `feat/play-store-account` in `stack-connect-core`.
> Core reference commits: `c5e7acc` feat(googleplay): connect Google Play accounts and list their apps · `f85e93c` docs.

## 0. Starting point

### What the core delivers (first Play slice)

The core exposes Google Play through the **same generic UniFFI facade** used by App Store Connect — no Play-specific functions, records or errors:

| Item | Detail |
|---|---|
| Service | `ServiceKind.googlePlay` (appended; `availableServices()` returns `[.appStoreConnect, .googlePlay]`) |
| Construction | `connect(kind: .googlePlay, accountId:, store: CredentialStore, debugLogger:)` — synchronous, no network. The RSA key is parsed **eagerly**: a bad key throws `StackError.InvalidCredentials` from `connect`. |
| Credentials | Three `CredentialStore` keys (not a JSON blob): `clientEmail`, `privateKeyId`, `privateKey` (PEM, PKCS#8 or PKCS#1, raw or JSON-escaped). Passing the whole JSON file as `privateKey` is rejected. |
| Capabilities | `capabilities() == [.apps]`; every capability accessor returns `nil`. |
| `validate()` | Token exchange + `apps:search?pageSize=1` on the **Play Developer Reporting API**. `Ok` = key works and the Reporting API is enabled; it does **not** guarantee any app is visible yet (Play Console access can take hours to propagate). |
| `fetchApps()` | Pages `apps:search` (1000/page), dedupes by package name. `AppInfo.id == bundleId == packageName`, `name = displayName` (fallback package name), `platform == "ANDROID"`. |
| Errors | Existing `StackError` cases. `.Auth` carries actionable English text (API disabled + activation URL, SA not invited in Play Console, missing scope, `invalid_grant` hints). `.Http(status:message:)` for 400/404/429/5xx. `.Network` for transport. |
| Debug | Same `DebugLogger` foreign trait; logs the token exchange and every call (bearer tokens + JWT assertion appear verbatim — DEBUG only). |

Google-side setup the user must do: enable the **Google Play Developer Reporting API** in the service account's Cloud project and invite the service-account e-mail in **Play Console › Users and permissions** with at least "View app information (read-only)".

### What the iOS app already has

- `ProviderType.googlePlay` (name, `play.fill`, green) and `GooglePlayCredentials { serviceAccountJSON }` stored in the Keychain under `credentials.{accountId}` and carried in `.scexport` as `serviceAccountJSON`.
- A legacy, **native** scaffold built on `Packages/APIProviderPlay`: `GooglePlayAppList` module (Reporting `apps:search` + manual add by package name, checked with an `edits.insert`/`delete` round-trip; cache under `googleplay-apps.{accountId}`).
- Google Play is **hidden**: `HomeViewModel.swift:27` filters it out and the Settings provider picker (`SettingsAccountsView.swift:555`) only offers Apple/Firebase.
- `AddAccount` Play section has no file importer / tutorial and validates **offline only** (`PlayConfiguration` parse).
- Gaps: export is Apple-only; cascade delete leaves `googleplay-apps.{id}` behind; no Play-friendly error messages.

## 1. Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Play connectivity goes through the **Rust core** (`StackCoreRust`), mirroring `AppleAccountConnection` + `AppleCredentialStore`. | Single source of truth shared with Flutter; RUST_CORE_PLAN names Play as the 2nd core service. Firebase stays native. |
| D2 | **Keychain / `.scexport` format unchanged**: keep `GooglePlayCredentials { serviceAccountJSON }`. The app parses the JSON (`client_email`, `private_key_id`, `private_key`, `project_id`) into the three core fields at connection time. | Zero migration; existing accounts and export files keep working. The core lists the JSON↔fields conversion as a host concern. |
| D3 | `accountId` passed to `connect` = the service account's `client_email`. | Mirrors Apple (credential-derived `issuerID`); the read-only store ignores it. |
| D4 | Duplicate detection for Play = same `client_email` (instead of raw JSON string equality). | Re-formatted / re-downloaded JSON of the same key must still be caught. |
| D5 | `APIProviderPlay` is **kept only** for the manual "add app by package name" access check (androidpublisher `edits`) until the core gains an androidpublisher capability; then it is removed (Phase 3). | Avoids regressing manual add; the core has no androidpublisher capability yet. |
| D6 | Play apps are **not** written into `AppModel` / `SyncService` in Phase 1; they stay in the `googleplay-apps.{accountId}` cache. | `AppModel`, widgets, AllReviews and SyncService are App Store–centric; mixing Android apps there needs its own phase (Phase 4). |
| D7 | No feature flag: the feature branch is the gate. | The type was already modelled; the branch only merges when Phase 1 is complete. (If incremental merges to `master` are wanted, add `FeatureFlag.googlePlayAccounts` OFF and update `docs/FEATURE_FLAGS.md`.) |

## 2. Phases

### Phase 1 — Connect + list apps on the core (this branch) — implemented, pending manual UI check

> T2–T4 implemented; `xcodebuild test` 591/591 green (62 new tests). Not yet validated against a real Google service account.

- **T1 — Vendor the core** ✅: rebuilt `stack-connect-core` (`build/build-xcframework.sh`) and copied `StackCoreRust.xcframework` + `StackCoreRust.swift` into `Packages/StackCoreRust`. Binding diff is additive (`ServiceKind.googlePlay` + docs).
- **T2 — Provider infra** (`StackConnect/Infra/Providers/GooglePlay/`):
  - `GooglePlayServiceAccount` — parses the service-account JSON (`type == "service_account"`, `client_email`, `private_key_id`, `private_key`, `project_id`), typed errors, never logs key material.
  - `GooglePlayCredentialStore: CredentialStore` — read-only, answers `clientEmail` / `privateKeyId` / `privateKey`.
  - `GooglePlayAccountConnection: AccountConnectionProtocol` — `connect(kind: .googlePlay, …)`, cached provider, `validateCredentials()`, `fetchApps()`, `requireOnline()` guard, `RustCoreDebugLogger` behind `useRustCoreDebugLogging`.
  - `GooglePlayErrorTranslator` (`Infra/Errors/`) — `StackError` → localized, user-friendly message (invalid key, API disabled / not invited — surfacing the core's actionable detail, offline, rate limit, server error).
  - Tests: parser, store keys == `credentialSchema(kind: .googlePlay)`, translator, connection offline guard.
- **T3 — Add Account + reachability**:
  - Real network validation via `GooglePlayAccountConnection.validateCredentials()` behind an injectable factory.
  - `.json` file importer + setup tutorial (mirroring Firebase), updated footer copy.
  - Duplicate detection by `client_email`.
  - Remove the Home filter; add Google Play to the Settings provider picker.
  - Tests: AddAccountViewModel Play paths (empty, malformed JSON, duplicate, validation failure, success).
- **T4 — App list on the core**:
  - `GooglePlayAppListViewModel` fetches via the connection (injectable), **offline-first** (cache → sync with toast), merges manual apps, maps `StackError` through the translator.
  - Manual add keeps the `APIProviderPlay` access check (D5).
  - `AccountCascadeDeleter` also deletes `googleplay-apps.{accountId}`.
  - Tests: VM load/cache/merge/error paths, cascade delete.

### Phase 2 — Export / import parity
- Export Play accounts (`serviceAccountJSON`) from Settings and AccountSettings (today Apple-only), import option in AccountsList for Play.
- `.scexport` import duplicate check for Play by `client_email` (D4) in `AccountsListViewModel` and `SettingsAccountsViewModel` (still raw-JSON equality).
- Account-level settings that make sense for Play (rename, delete); hide the ASC-specific role picker for Play.
- Native-speaker review of the new Google Cloud / Play Console strings (menu names were translated best-effort).

### Phase 3 — App detail on the core (needs new core capabilities)
- Core: androidpublisher capabilities — app details/listings, tracks/releases, reviews (list + reply).
- iOS: `GooglePlayAppDetail` module (menu like `FirebaseProjectDetail`): Listings, Tracks/Releases, Reviews (+ reply templates reuse). App rows in `GooglePlayAppList` already show a chevron but have no destination yet.
- Move the manual-add access check to the core and **remove `APIProviderPlay`**.

### Phase 4 — Home / sync integration
- Android apps in the Home dashboard and widgets (`AppPlatform.android`), background sync of Play accounts through the core `SyncService`, Play reviews in AllReviews.

## 3. Verification (every task)

```bash
xcodegen generate --spec project.yml
xcodebuild build -project StackConnect.xcodeproj -scheme "StackConnect Development" -destination 'platform=iOS Simulator,id=<sim>'
xcodebuild test  -project StackConnect.xcodeproj -scheme "StackConnect Development" -destination 'platform=iOS Simulator,id=<sim>'
```

Re-vendoring the core: run `build/build-xcframework.sh` in `stack-connect-core`, then copy `bindings/swift/StackCoreRust.xcframework` and `bindings/swift/Sources/StackCoreRust/StackCoreRust.swift` into `Packages/StackCoreRust/` (the xcframework is gitignored here; the wrapper is tracked).
