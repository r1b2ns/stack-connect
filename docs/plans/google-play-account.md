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

> Starting point before Phase 1 (kept for history). `Packages/APIProviderPlay` was removed in Phase 3 (D5).

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
| D5 | ~~`APIProviderPlay` is kept only for the manual "add app by package name" access check.~~ **Removed in Phase 3**: the check is `GooglePlayCoreAccessChecker`, which calls the core's `AppDetails.fetchAppDetails` (`Ok` = reachable, `Http 404` = unknown package, `Auth` = no access / API disabled). The package, its `project.yml` entries and every import are gone. | The core now has the androidpublisher capabilities; one Play stack instead of two. |
| D6 | Play apps are **not** written into `AppModel` / `SyncService` in Phase 1; they stay in the `googleplay-apps.{accountId}` cache. | `AppModel`, widgets, AllReviews and SyncService are App Store–centric; mixing Android apps there needs its own phase (Phase 4). |
| D7 | No feature flag: the feature branch is the gate. | The type was already modelled; the branch only merges when Phase 1 is complete. (If incremental merges to `master` are wanted, add `FeatureFlag.googlePlayAccounts` OFF and update `docs/FEATURE_FLAGS.md`.) |
| D8 | Export / import live in one shared place (`StackConnect/Infra/AccountTransfer/`): `AccountExporter` (keychain → `AccountExportPayloadBuilder` → `AccountCrypto` → temp file), `AccountTransferCredentials` (the `credentials` payload keys + keychain read), `AccountImporter` (both import paths) and `ExportableAppsLoader` (per-app scope picker). | Both export ViewModels and both import ViewModels were copy-pasted; Play support would have meant a third/fourth copy. One implementation keeps every entry point byte-compatible. |
| D9 | Provider capabilities on `ProviderType`: `supportsExport`, `supportsImport` (Apple + Play), `supportsAccountRole` (Apple + Firebase). `AccountModel.isExportable` = created **and** `supportsExport`; `AccountRuleResource.resources(for:)` = rule resources per provider (Play: `[.apps, .review]` since Phase 3, Firebase: `[]`). | Replaces scattered `== .apple` checks; each UI entry point asks one question. |
| D10 | `.scexport` import of a Play account validates **offline only**: `serviceAccountJSON` must parse with `GooglePlayServiceAccount`, otherwise a friendly error and nothing is stored. Duplicates are detected by `client_email` (D4) in both import paths and Add Account through `GooglePlayDuplicateAccountFinder`. | Same policy as the Apple import (shape check, no network). A re-import that replaces an expired account is never its own duplicate. |
| D11 | Play accounts always keep `AccountRole.unspecified`: the role picker is hidden (Add Account, Account Settings), the role badge is hidden (`AccountModel.displayedRole`) and a `role` in an imported file is ignored. Firebase keeps its picker. | The role is an App Store Connect concept. Firebase behaviour left untouched in a Play-focused phase. |
| D12 | Export refuses (no file) when the keychain has no credentials, and for imported accounts. | Before, a credential-less file was written that no importer accepts; imported accounts were already hidden from the UI — now enforced in the exporter too. |
| D13 | Play app list enforces the imported account's scope like the App Store list: apps outside `appsBundles` are filtered on cache read and on sync (never persisted); manual add needs `canAdd(.apps)` and an in-scope package name; remove needs `canDelete(.apps)`. The View hides the entry points, the ViewModel guards are the source of truth. | Issue #93 scope contract must hold for Play too. |
| D14 | **Edit side-effect mitigation.** App details, store listings and tracks are read through a temporary Play *edit* (insert → read → delete), and Google keeps one open edit per service account + app, so each read cancels an edit the same service account has open elsewhere (e.g. a CI upload). These reads run **only** when the user opens that section (or pulls to refresh it): never on the app detail menu, on a ViewModel's init, in a background path or in `SyncService`. **Once per screen:** SwiftUI cancels a screen's `.task` when a child is pushed and restarts it on pop-back, so the screens call `loadIfNeeded()` (one read per ViewModel); only pull to refresh / Retry call `load()`. One shared `GooglePlayAppSectionLoader` does this for all three sections: the load runs in a task it owns (view cancellation can't cut it short, and the core ignores cancellation anyway), a `load()` while one is in flight waits for it instead of opening a second edit (`isSyncing` is the guard), and the connection is built once per ViewModel so every read of a screen goes through the same core provider and its edit lock. Each section shows its cache first. The menu explains the side effect in a short footer under the three sections and suggests a separate read-only service account when CI publishes with this one. The seams (`GooglePlayAppDetailsFetching`, `GooglePlayStoreListingsFetching`, `GooglePlayTracksFetching`) document the rule. | Reading must never break a release in progress; the user decides when an edit is opened. |
| D15 | **Reviews reuse the App Store screens through a provider seam.** `CustomerReviewsServicing` (fetch page / reply / delete reply / error copy + `CustomerReviewsTraits`) with `AppleCustomerReviewsService` and `GooglePlayCustomerReviewsService`, built per account by `CustomerReviewsServiceFactory`. `RatingsReviewsView`, `ReviewDetailView`, reply templates and the `ratingsReviews` / `reviewDetail` routes are shared; Play uses the package name as `appId`/`bundleId`. Traits drive what differs: Play offers only "newest" (no sort menu), no reply deletion (a reply is an upsert, so editing just replies again), no iTunes rating summary, a ~350-character soft counter in the shared `StackReplyComposer`, and a note that Google only shares reviews with a comment written or edited in the last 7 days. Rating filters are applied by the core per page, so the list skips up to 4 empty pages that still have a successor. The next-page row loads when it appears and again after each page that added reviews while it stays on screen; a page that adds nothing or fails leaves an explicit "Load More" / "Try Again" (no automatic loop — Google counts each page against ~200 review GETs/hour), and an empty list with more pages offers "Load More" instead of "No reviews". Loads and next pages run in ViewModel-owned tasks (the App Store rating sweep must not be cancelled half-way by a pushed review) and drop results meant for an older list (refresh, sort, filter). The App Store rating summary comes from `AppStoreRatingSummaryFetching` (`ITunesRatingSummaryFetcher`): a cancelled sweep changes nothing and a partial one never replaces a complete summary. A successful reply also updates the Play reviews cache. |  One review UI for both stores instead of a copy; the Apple flow keeps its behaviour (same sort options, delete + create on edit, same copy). |
| D16 | Play replies are gated by the account's `review` rule exactly like Apple (`canEdit(.review)` to reply, `canView(.review)` to open Ratings & Reviews); deletion additionally needs `traits.canDeleteReplies` (false for Play). The read-only store sections need `canView(.apps)`. Every section ViewModel re-checks the per-app scope and its rule before reading (`GooglePlayAppSectionAccess`, in `GooglePlayAppSectionLoader`), and the Ratings & Reviews ViewModel re-checks the per-app scope and `canView(.review)` before loading (both stores). | `.review` is now a Play rule resource (D9), so exports can grant or withhold replying. Older Play `.scexport` files carry no `review` permission and therefore can't open reviews — fail closed. |
| D17 | Per-app Play caches, one entry per section: `googleplay-details|listings|tracks|reviews.{accountId}.{packageName}` (`GooglePlayAppScopedCache`). Reviews cache only the unfiltered newest-first first page. Every entry carries its `accountId`, so `AccountCascadeDeleter` removes all of a deleted Play account's entries with a `fetchAll` (also for apps that already left the app list). | Offline-first per section without one section rewriting another; stable storage ids. |
| D18 | **App icons come from the public Play store page.** The core's `AppIcons` capability (`provider.appIcons()`, `Capability.appIcons`) reads the `og:image` of `play.google.com/store/apps/details?id={package}` and returns a 512 px `https://play-lh.googleusercontent.com/…=s512` URL — no credentials, no OAuth token, no Android Publisher call. `GooglePlayAccountConnection.fetchIconUrl(packageName:)` (seam `GooglePlayAppIconFetching`) is best effort: unsupported, offline or any error is logged at info level and becomes `nil`. The icon is cached in `GooglePlayAppItem.iconUrl` (optional, so older caches still decode); the app list asks only for apps with no icon yet (after the sync, whether or not it succeeded; never offline; never outside the account's scope), at most 4 lookups in flight, applies each icon onto the current list by package name and persists once. A manual add looks up the new app's icon too. Unpublished / unknown packages (`nil`) keep the green Play tile and are asked again on the next load. Icons show through the shared `StackAppIcon` (list row, detail header, export app-scope picker). No feature flag. | `edits.images` would need an edit, and opening one cancels any edit the same service account has open for the app (e.g. a CI upload, D14) — unacceptable for something that runs on every list load. The store page is public, cheap and has the same artwork users see. |

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
  - Manual add keeps the `APIProviderPlay` access check (D5; moved to the core in Phase 3).
  - `AccountCascadeDeleter` also deletes `googleplay-apps.{accountId}`.
  - Tests: VM load/cache/merge/error paths, cascade delete.

### Phase 2 — Export / import parity + account polish — implemented, pending manual UI check

> T5–T7 implemented; `xcodebuild test` 667/667 green (76 new tests). Not yet validated on device with a real Google service account.

- **T5 — Export Play accounts** ✅:
  - Shared `AccountExporter` + `AccountTransferCredentials` (D8) used by `SettingsAccountsViewModel` and `AccountSettingsViewModel`; Apple payload unchanged (regression test compares it with the pre-Phase-2 builder output), Play writes `credentials.serviceAccountJSON`.
  - Every export entry point (Settings › Accounts swipe + edit sheet, Account Settings) is driven by `AccountModel.isExportable` (D9).
  - `ExportAccountView` shows only `AccountRuleResource.resources(for:)` (Play: Apps) and feeds the per-app scope picker through `ExportableAppsLoader` (Play: cached `GooglePlayAppItem` list, package name as scope key).
- **T6 — Import Play accounts + enforce scope** ✅:
  - "Import" offered in the Play Accounts list (`supportsImport`); both import paths go through `AccountImporter` (D8, D10).
  - Side effect of sharing the importer: the per-provider Accounts list now also restores `appsBundles` (it used to drop it — for Apple too).
  - `GooglePlayAppList` enforces scope and `apps` rules (D13).
- **T7 — Account polish** ✅:
  - Role picker / badge hidden for Play (D11).
  - Rename keeps the per-app scope: `SettingsAccountsViewModel.updateAccountName` and `AccountSettingsViewModel.save` rebuilt the account without `appsBundles`, silently widening an imported account's scope (fixed with `AccountModel.updating(name:role:)`, all providers).
  - Play accounts reach Account Management from a gear in `GooglePlayAppList` (same as the App Store list): Account Settings (rename, permissions, export) and Delete Account; the ASC-only Certificates/Identifiers/Devices/Profiles section is hidden for Play. Settings › Accounts rename / delete already worked (cascade delete covers the Play app cache since Phase 1).
- Still open: native-speaker review of the Google Cloud / Play Console strings (Phase 1 + the four Phase 2 strings were translated best-effort).

### Phase 3 — App detail on the core — implemented, pending manual UI check

> T8–T11 implemented, plus the staff-review fixes; `xcodebuild test` 834/834 green. Not yet validated on device with a real Google service account. Core: `Capability` gained `.appDetails`, `.storeListings`, `.tracks`; Play `capabilities()` = `[.apps, .reviews, .appDetails, .storeListings, .tracks]` (binding re-vendored).

- **T8 — Connection + models** ✅:
  - `GooglePlayAccountConnection` implements focused seams: `GooglePlayAppDetailsFetching`, `GooglePlayStoreListingsFetching`, `GooglePlayTracksFetching` (edit-based, D14) and `GooglePlayReviewsConnecting` (page with sort `-createdDate`, page size clamped 1–100, reply). All behind `requireOnline()`.
  - App-side models in `StackConnect/Models/`: `GooglePlayAppDetailsModel`, `GooglePlayStoreListingModel`, `GooglePlayTrackModel` / `GooglePlayReleaseModel` (typed `GooglePlayReleaseStatus`, `rolloutFraction` from `userFraction` while rolling out or halted, version codes kept as decimal strings), `CustomerReviewsPageModel`, `CustomerReviewResponseModel`, and the per-section cache entries (D17).
  - Reviews map onto the existing `CustomerReviewModel` through the shared `CoreReviewMapper` (Apple's `mapCustomerReview` now forwards to it). The composite review id is passed through, never parsed.
  - `GooglePlayErrorTranslator`: `Http 404` depends on the operation — package not found for listing apps / manual add / listing reviews, "review no longer available" on a reply, a generic "couldn't load, try again" for the edit-based reads (an invalidated edit also 404s); `Http 403` → no access to the app, `Http 400` on a reply → reply too long (~350 characters), `.Unsupported` → "Google Play doesn't support this action."; `.Auth` keeps the core's detail (it names the app and the Play Console permission).
- **T9 — Remove `APIProviderPlay`** ✅: manual add uses `GooglePlayCoreAccessChecker` (D5); package removed from `project.yml` and deleted.
- **T10 — `GooglePlayAppDetail` module** ✅:
  - App rows in `GooglePlayAppList` navigate to `HomeRoute.googlePlayAppDetail`. The menu (header with name, package name, platform and the cached default language) lists Ratings & Reviews and, under the edit footer, Store Listings, Tracks & Releases and App Details (`StackListRow`). It only reads the cache (D14).
  - Sections: `GooglePlayStoreListings` (languages, default first → read-only listing detail), `GooglePlayTracks` (tracks production → testing → custom, releases with `StackCapsuleBadge` status, version codes, rollout bar → release detail with release notes per language), `GooglePlayAppInfo` (default language, tappable email / phone / website). Offline-first with the standard sync toast; a failed sync keeps the cache with an inline banner. The three ViewModels are thin: `GooglePlayAppSectionLoader` (cache-first, access + credentials guards, live read, errors, once-per-screen, in-flight guard) does the work, parameterized by the section's cache entry (`GooglePlayAppSectionCache`) and fetch closure. Links from store data (website, promo video, contact email / phone) only open `http(s)`, `mailto` and `tel` (`ExternalLinkURL`); anything else is shown as text.
  - Reviews reuse the App Store screens (D15) with Play permissions (D16).
  - New DS components: `StackIconTile`, `StackInlineErrorSection`, `StackLoadableContent`, `StackReplyComposer` (now used by both reply sheets).
  - `AccountCascadeDeleter` removes the per-app caches (D17).
- **T11 — Docs** ✅ (this section, D5, D9, D14–D17).
- **Review fixes** ✅: once-per-screen edit reads + shared section loader (D14), App Store rating summary safe from cancellation, load-more that can't stall on short pages (D15), operation-specific 404 copy, `canView(.review)` re-check in Ratings & Reviews (D16), `AppleReviewsConnecting` seam + service / factory tests, store-neutral reply-template copy, reply sheets reset when swiped away.
- **T12 — App icons** ✅ (D18): core re-vendored with `Capability.appIcons` (Play `capabilities()` = `[.apps, .reviews, .appDetails, .storeListings, .tracks, .appIcons]`); `GooglePlayAppIconFetching` seam on `GooglePlayAccountConnection`; `GooglePlayAppItem.iconUrl` (old caches decode); `GooglePlayAppListViewModel` carries icons across merges, fetches missing ones after each load (bounded, scope-checked, applied onto the current list, persisted once) and after a manual add; `ExportableApp(playApp:)` maps the icon. New DS component `StackAppIcon` (remote icon + placeholder + loading) used by the Play list row and detail header and adopted by the App Store list, archived apps, app detail, export app-scope picker and Home app icons (same visuals). Tests: merge, enrichment scope / bounds / offline / failure / concurrent add-remove, manual add, persistence, old-cache decode, export mapping, connection best-effort paths, capability list.

**Follow-ups**
- Manual check on device with a real service account: edit-based reads with view-only access (Google doesn't document which permission `edits.insert` needs for reads), reply limits, 7-day review window.
- Native-speaker review of the Phase 3 strings (translated best-effort, like Phases 1–2).
- The App Store review list still loads live (no cache); `CustomerReviewsCaching` could back it too.
- Play review metadata the core doesn't map yet (app version, device, reviewer language) and Google's 200 GET/hour review quota (no client-side throttling beyond the bounded page skipping and the no-loop next-page row).
- A reply sent from the review detail updates the detail and the Play cache, but not the list behind it (same as before for App Store); the list catches up on refresh.
- Writing listings / tracks (commit an edit) is out of scope: everything except replies stays read-only.

### Phase 4 — Home / sync integration
- Android apps in the Home dashboard and widgets (`AppPlatform.android`), background sync of Play accounts through the core `SyncService`, Play reviews in AllReviews.
- Keep D14: a background Play sync may list apps and reviews, but must never call the edit-based reads.

## 3. Verification (every task)

```bash
xcodegen generate --spec project.yml
xcodebuild build -project StackConnect.xcodeproj -scheme "StackConnect Development" -destination 'platform=iOS Simulator,id=<sim>'
xcodebuild test  -project StackConnect.xcodeproj -scheme "StackConnect Development" -destination 'platform=iOS Simulator,id=<sim>'
```

Re-vendoring the core: run `build/build-xcframework.sh` in `stack-connect-core`, then copy `bindings/swift/StackCoreRust.xcframework` and `bindings/swift/Sources/StackCoreRust/StackCoreRust.swift` into `Packages/StackCoreRust/` (the xcframework is gitignored here; the wrapper is tracked).
