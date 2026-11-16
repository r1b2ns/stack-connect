# Implementation Plan — Google Play releases, Home sync and user management

> Branch: `feat/play-store-account` (iOS) — pairs with `feat/play-store-account` in `stack-connect-core`.
> Follows `docs/plans/google-play-account.md` (Phases 1–3 done). This is the first **write** block for Google Play.
> Prototype: "Google Play — Protótipo de features" — releases: screens 1–6; Home and widgets: 19–20 (section 6); users: 16, 17, 21, 22 (section 7).

## 0. Starting point

| Area | Today |
|---|---|
| Core `Tracks` capability | Only `fetchTracks(appId:)`, read through a throwaway edit (insert → read → delete). Nothing is ever committed. |
| `TrackReleaseInfo` | `name`, `status`, `versionCodes`, `userFraction`, `releaseNotes`, `inAppUpdatePriority`. No `countryTargeting`, no review/lifecycle state. |
| iOS | `GooglePlayTracks` module (tracks list + read-only release detail), `GooglePlayTrackModel` / `GooglePlayReleaseModel`, `GooglePlayAppSectionLoader` (cache-first, once per screen). |
| Rules | Play rule resources are `[.apps, .review]`; tracks are gated by `canView(.apps)`. |
| App list / app detail | No release status. The detail menu only reads caches (D14). |

App Store Connect parity targeted by this block: version rows with status on the app list and app detail, version detail with a bottom action bar, phased release sheet, pre-submit checklist, submit / release / pause.

## 1. API surface (verified against the Android Publisher v3 discovery document)

| Need | Endpoint | Edit? |
|---|---|---|
| Review / lifecycle state per release | `GET applications/{pkg}/tracks/{track}/releases` → `ReleaseSummary { track, releaseName, releaseLifecycleState, activeArtifacts }`. States: `DRAFT`, `NOT_SENT_FOR_REVIEW`, `IN_REVIEW`, `APPROVED_NOT_PUBLISHED`, `NOT_APPROVED`, `PUBLISHED`. Excludes obsolete releases. | **No** |
| Read a track | `edits.tracks.get` / `list` | Yes |
| Change a track (rollout, halt, resume, complete, new release, promote) | `PUT edits.tracks.update` — replaces the track's `releases[]` (`status`, `userFraction`, `versionCodes`, `name`, `releaseNotes`, `countryTargeting`, `inAppUpdatePriority`) | Yes |
| Bundles that can go into a release | `edits.bundles.list` → `versionCode`, `sha1`, `sha256` | Yes |
| Validate / publish | `edits.validate`, `edits.commit?changesNotSentForReview=&changesInReviewBehavior=` (`CANCEL_IN_REVIEW_AND_SUBMIT` \| `ERROR_IF_IN_REVIEW`) | Yes |

Not offered by the API (drawn as "Only in Play Console"): rejection reason, review history, cancelling a review, upload date / version name of a bundle. Uploading an `.aab` (`edits.bundles.upload`) exists but is out of scope on a phone.

To validate with a real service account (not stated in the discovery document): release notes limit (500 characters per language), the exact Play Console permission each call needs, when Google requires `changesNotSentForReview=true` (it rejects the commit with an explanatory message when the flag doesn't match the app's state), and whether `releases.list` returns version codes for every state.

## 2. Decisions

| # | Decision | Rationale |
|---|---|---|
| R1 | **Status comes from `releases.list`, never from an edit.** A new core call returns the summaries of one track; iOS asks for the four standard tracks (plus cached custom ones) and caches the result per app. It powers the app list status lines and the app detail track sections, and may run automatically (list load, pull to refresh, later the Phase 4 background sync). | It is the only edit-free read, so it can't cancel a CI upload (D14 stays intact for automatic paths). It also gives the review state, which `edits.tracks` doesn't. |
| R2 | **Writes are typed mutations applied by the core inside one edit**: insert → `tracks.get` (fresh) → apply mutation → `tracks.update` → `validate` → `commit`; on any failure the edit is deleted and the original error wins. The app never sends a whole track back. Mutations: `setRollout(fraction)`, `halt`, `resume`, `complete`, `updateMetadata(name, notes, priority, countryTargeting)`, `createRelease(…)`, `promote(fromTrack, …)`. Each targets a release by its version codes. | `tracks.update` is a full replace: composing it from a cached track could silently drop a release someone else just published. Reading and writing in the same edit removes the stale-write window, and UniFFI can't carry a closure. |
| R3 | **One commit per user action.** The Review Checklist's "Also in this edit" section in the prototype (listing + screenshots batched with a release) is deferred to the Store block. | Keeps the first write path small and each action atomic; batching needs a client-side edit session, which is a separate design. |
| R4 | **D14 revised for writes only.** A write opens an edit by nature, so every write is an explicit, confirmed user action: the confirmation states that any edit this service account has open elsewhere is cancelled. Edit-based *reads* keep the existing rule (only when the section opens / pull to refresh, once per screen). | The user decides when an edit is opened; nothing changes for automatic paths. |
| R5 | **New Play rule resource: `.version`.** `canView(.version)` shows release status and release detail; `canEdit(.version)` allows rollout / halt / resume / complete / metadata; `canAdd(.version)` allows new release and promote. Play resources become `[.apps, .version, .review]`. Older Play `.scexport` files carry no `version` permission → releases are hidden (fail closed, same as D16). The existing Tracks section moves from `.apps` to `.version`. | Mirrors Apple, where versions are gated by `.version`; an exported account can be read-only for releases. |
| R6 | **Feature flag `googlePlayReleaseWrites`** (OFF by default) gates every write entry point (bottom bar, swipe actions, `+`). Status and read screens are not flagged. `docs/FEATURE_FLAGS.md` is updated in the same task. | A wrong tap changes production for real users; the flag lets the read side merge and ship while writes are validated against a real account. Revisits D7 for this block only. |
| R7 | **A release is identified by track + sorted version codes**, not by name or index. | Names are optional and editable; indexes change when Google drops obsolete releases. |
| R8 | **Rollout rules live in one pure type** (`GooglePlayReleaseActions`): which actions a release offers given track kind, `status`, `userFraction` and lifecycle state. `draft` → Roll out; `inProgress` → Increase / Halt / Release to all; `halted` → Resume / Release to all; `completed` → Promote only. Staged rollout is offered on production and open testing only. | One testable place instead of conditions spread over the view, the swipe actions and the bottom bar (as `VersionDetailView` does per state today). |
| R9 | **Favorites and Archive for Play apps stay out** (drawn in the prototype). | Both live on `AppModel`, and Play apps are not in `AppModel` until Phase 4 (D6). |

## 3. Tasks

### Core (`stack-connect-core`, `crates/stack_core/src/providers/googleplay/`)

- **C1 — Release summaries (no edit).** `Tracks.fetchReleaseSummaries(appId:, track:) -> [ReleaseSummaryInfo]` (`track`, `name`, `lifecycleState` as raw string, `versionCodes`). New `releases.rs`; `404` on an unknown track maps to an empty list. Tests with the mock server: mapping, unknown state passthrough, no `edits` call is made.
- **C2 — Richer track read.** `TrackReleaseInfo` gains `countryTargeting { countries, includeRestOfWorld }?`. Additive binding change.
- **C3 — Bundles.** `Tracks.fetchBundles(appId:) -> [BundleInfo]` (`versionCode`, `sha256`) through the existing `with_edit` session.
- **C4 — Track mutations (R2).** `Tracks.applyReleaseChange(appId:, track:, change: ReleaseChange, options: CommitOptions) -> TrackInfo`, where `CommitOptions { sendForReview: Bool, changesInReviewBehavior }`. Extends the edit session with `put`, `validate`, `commit`. Returns the committed track. Errors: validation / commit failures surface Google's message in `StackError.Http`; a release that no longer exists → a dedicated, typed error. Tests: each mutation's resulting `releases[]`, fraction bounds (0 < f < 1), failed validate deletes the edit and never commits, concurrent mutations on one app never overlap (existing edit lock).
- **C5 — Capability + docs + re-vendor.** `Capability.releaseManagement` (so hosts can hide writes on providers without it), `docs/`, `build/build-xcframework.sh`, copy the xcframework and `StackCoreRust.swift` into `Packages/StackCoreRust`.

### iOS

- **T1 — Connection seams and models.**
  - `GooglePlayAccountConnection`: `GooglePlayReleaseSummariesFetching` (edit-free), `GooglePlayBundlesFetching`, `GooglePlayReleaseManaging` (the mutations). All behind `requireOnline()`.
  - Models: `GooglePlayReleaseLifecycleState` (typed, unknown-safe, `displayName`, `color`: draft gray, not sent gray, in review orange, approved yellow, not approved red, published green), `GooglePlayReleaseSummaryModel`, `GooglePlayBundleModel`, `GooglePlayReleaseChange`, `countryTargeting` on `GooglePlayReleaseModel` (optional, old caches decode), `GooglePlayReleaseActions` (R8).
  - Cache: `googleplay-releases.{accountId}.{packageName}` (`GooglePlayAppScopedCache`), removed by `AccountCascadeDeleter`.
  - `GooglePlayErrorTranslator`: validation failure (show Google's message), commit while in review, "must not be sent for review" hint, release no longer exists.
- **T2 — Rule resource `.version` for Play (R5).** `AccountRuleResource.resources(for:)`, export permission picker, permissions summary, `GooglePlayAppSectionAccess`, Tracks section gate. Tests for old exports (no `version` → hidden).
- **T3 — Status on the app list and app detail (R1).**
  - `GooglePlayAppListViewModel`: after the app sync, fetch summaries for apps in scope (bounded concurrency like the icon lookup, never offline), persist once. Row: one status line per track that has a release (6 pt dot + "Production · In review (4.2.0)").
  - `GooglePlayAppDetail`: one section per track with release rows (name, lifecycle dot line, chevron) and "See all tracks". Rollout percentage and status badge come from the tracks cache when present (it needs the edit), otherwise only the lifecycle line shows. Header and footer copy updated; the edit warning footer stays on the edit-based sections.
- **T4 — Release Detail rework** (`GooglePlayReleaseDetailView` → own ViewModel). Header (track, status, name as hero, review status), Build row, release name / notes / priority (editable when `canEdit(.version)` and the flag is on; read-only otherwise, as `StackTextView` does for App Store text), rollout row, country targeting (read-only in this block), "Only in Play Console" footer. Bottom `.bar` driven by `GooglePlayReleaseActions`. Swipe actions on release rows mirror the bar.
- **T5 — Staged Rollout sheet.** Release-method choice, percentage (slider + 1 / 5 / 10 / 20 / 50 / 99 steps), status section with Halt / Resume. Save → confirmation (R4) → mutation → toast → refresh summaries and the tracks cache from the returned track. Reuses the look of `PhasedReleaseSheet`; shared pieces go to `Infra/DS` (Stack*).
- **T6 — New Release / Promote sheet + bundle picker.** Track picker, source (promote from a release, or pick a bundle from `fetchBundles`), name, release notes per language (pre-filled from the previous release on that track), draft toggle, rollout, priority. `+` on app detail and on a track; "Promote" from a release. Guard: version code must be higher than the track's live one.
- **T7 — Review Checklist sheet.** Rows with satisfied / warning indicators (bundle, name, release notes per listing language, rollout, version code), "Send changes for review" toggle, "If a review is in progress" picker, validation error block with Share Error. Mirrors `PreSubmitChecklistSheet`; shared row component extracted to `Infra/DS`.
- **T8 — Feature flag, strings, docs.** `FeatureFlag.googlePlayReleaseWrites` + `docs/FEATURE_FLAGS.md`; all strings via `String(localized:)` in `Localizable.xcstrings`; update `google-play-account.md` (D14 note, Phase list) and this file's status.

Order: C1 → T1 (read part) → T2 → T3 can ship first (read-only, no flag). Then C2–C5 → T1 (write part) → T4 → T5 → T7 → T6.

Status:
- C1–C5 ✅ in the core; re-vendored in the app (fake data overrides every new handle method).
- T1 read part ✅: `GooglePlayReleaseSummariesFetching` (edit-free), `GooglePlayReleaseLifecycleState`, `GooglePlayReleaseSummaryModel`, `GooglePlayReleaseKey` (R7), `countryTargeting` on `GooglePlayReleaseModel`, `GooglePlayReleaseSummariesCache` (`googleplay-releases.*`, cascade-deleted), `GooglePlayReleaseActions` (R8) with the full matrix tests, `ReleaseNotFound` copy. Write seams (`GooglePlayBundlesFetching`, `GooglePlayReleaseManaging`) come with T4–T7.
- T2 ✅: Play resources are `[.apps, .version, .review]`; Tracks gated by `.version`; old exports hide releases.
- T3 ✅: the Play app list fetches release summaries after each sync (standard tracks + custom tracks known from the tracks cache, at most 4 requests in flight, in scope only, never offline, only with `canView(.version)`; an app's cache is replaced only when all its tracks answered) and shows one line per track (`StackStatusLine`, shared with the App Store list). The list adopts the App Store list chrome (large title, search, glass toolbar buttons; Add App bottom-leading; no Users tab, favorites or archive yet). The app detail shows one section per track from the caches only (lifecycle line from the summaries; status badge and rollout from the tracks cache when present), "See all tracks", Store presence, Quality and "Only in Play Console". A release row opens the release detail when the tracks cache holds it, otherwise the tracks screen.
- T1 write part + T8 flag ✅: `GooglePlayBundlesFetching`, `GooglePlayReleaseManaging` (`requireOnline()`), `GooglePlayBundleModel`, `GooglePlayReleaseChange` / `GooglePlayNewRelease` / `GooglePlayCommitOptions` mapped to the core types, translator copy for releases (Google's validation message, commit while in review, "must not be sent for review", release gone), `FeatureFlag.googlePlayReleaseWrites` (OFF; ON for the launch in fake data mode through `FeatureFlags.sessionDefaults`), `GooglePlayReleaseWriteAccess` (flag + scope + `canEdit` / `canAdd(.version)`).
- T4 ✅: `GooglePlayReleaseDetailViewModel` (caches only) and the screen of prototype 3 (header, Build, Content with editable name / notes / priority, Rollout, Country targeting read-only, Only in Play Console, bottom bar from `GooglePlayReleaseActions`); swipe actions on the app detail rows mirror the bar. Every write goes through `GooglePlayReleaseWriteViewModel` (confirmation stating R4 → `GooglePlayReleaseWriter.apply` → toast) and `GooglePlayReleaseWriter` updates the tracks cache from the committed track and re-reads that track's summaries; a failure writes nothing. DS: `StackActionBar` / `StackActionButtonLabel` (also used by the App Store version detail), `StackSubtitleRow`.
- T5 ✅: `GooglePlayRolloutSheet` (prototype 4): release method (all users / percentage, percentage only on production and open testing), slider 1–99 % + 1 / 5 / 10 / 20 / 50 / 99 steps, Rollout Status with Halt / Resume; opened from Increase Rollout (starts on the next step), Roll Out on a staged track and the release detail's Staged Rollout row. Choices live in `GooglePlayRolloutForm` (tested). Confirmations show over the sheet, which closes after a successful write. DS: `StackChoiceRow` (also adopted by the App Store phased release sheet), `StackStepChip`.
- T7 ✅: `GooglePlayReviewChecklistView` (prototype 6) is the confirmation of every publishing write (rollout, release to all, metadata, new release, promote; halt / resume keep an alert): items from `GooglePlayReviewChecklist` (bundle, name, release notes per store listing language, rollout, version code above live), "Send changes for review" and "If a review is in progress" (`GooglePlayCommitOptions`), and on a refusal the translated message with Share Error while the checklist stays open. Shown as its own sheet or pushed inside the rollout / new release sheets. "Also in this edit" stays out (R3). DS: `StackChecklistRow` (adopted by the App Store pre-submit checklist). The fake backend refuses release notes over 500 characters, like Google.
- T6 ✅: `GooglePlayNewReleaseSheet` + `GooglePlayNewReleaseViewModel` (prototype 5): track picker with what each track serves, source (bundle picker over `fetchBundles`, an explicit edit-based read, or the promoted release), name, priority, release notes per language pre-filled from the newest release of the chosen track (or the promoted release), draft toggle, staged rollout on production / open testing; the version code must be higher than the one live on the target track (Next disabled with the reason). Entry points: "+" on the app detail, "+" on each track of Tracks & Releases, Promote from the release detail's Actions section and the swipe actions. "Next" pushes the Review Checklist.
- T8 ✅: flag, strings (all locales) and docs (`FEATURE_FLAGS.md`, `FAKE_DATA.md`).
- Not done in this block: "Add Language" for release notes (the sheet edits the languages of the previous release + the store listing languages), country targeting editing (read-only, open question 2), the release detail's "Crashes in This Version" row and the app detail's Distribution / Graphics / Vitals rows (other blocks), favorites / archive (R9).

## 4. Tests

- ViewModels and services, with `MockPersistentStorable`, `MockKeyStorable` and a mock connection per seam.
- `GooglePlayReleaseActions`: full matrix of track kind × status × lifecycle state.
- App list: summaries bounded, scope-checked, skipped offline, a failure keeps the cached status.
- Writes: denied without `.version` edit / add, denied with the flag off, confirmation required, a failed commit leaves caches untouched, a successful one updates the tracks cache and the summaries.
- Old caches and old `.scexport` files still decode.

## 5. Verification (every task)

```bash
xcodegen generate --spec project.yml
xcodebuild build -project StackConnect.xcodeproj -scheme "StackConnect Development" -destination 'platform=iOS Simulator,id=<sim>'
xcodebuild test  -project StackConnect.xcodeproj -scheme "StackConnect Development" -destination 'platform=iOS Simulator,id=<sim>'
```

Manual, with a real service account on a test app (internal track first): status without an edit while a CI edit is open, rollout increase / halt / resume / complete, promote internal → closed, commit with and without "send for review", behaviour with view-only Play Console access.

## 6. Home sync and widgets for Android apps

Replaces the outline of "Phase 4" in `google-play-account.md`. Depends on C1 (release summaries) only, so it can ship with the read-only half of this block (T1 read part → T3), before any write.

### Starting point

- `SyncService.performSyncAll` keeps only `.apple` accounts (`SyncService.swift:83`). Nothing in the background touches a Play account; `googleplay-apps.{accountId}` is refreshed only when the Play app list screen is open.
- The three Home widgets (In Review, Awaiting Release, Recent Reviews), AllReviews, local notifications and the WidgetKit extension read only `AppModel`, `PhasedReleaseModel` and `CustomerReviewModel`. The extension decodes the app's records by type name from the shared App Group store and re-implements the categorization (it has already drifted: no `awaitingVersions`, no account filter, no dedupe).
- Row taps, the AllReviews header and the `stackconnect://app/…` deep link all open the Apple `AppDetail`.
- `CustomerReviewModel` is provider-neutral and `ReviewDetail` already works for Play when it gets the real Play `AccountModel` (`CustomerReviewsServiceFactory`).

### Decisions

| # | Decision | Rationale |
|---|---|---|
| H1 | **Play apps do not become `AppModel`; no `AppPlatform.android`.** The widgets read a provider-neutral `DashboardEntry` (provider, accountId, appId, name, iconUrl, platform label + glyph, status label + color, version text, optional progress, recency date, navigation target) built from `AppModel` (through the existing `AppStatusCategorizer`) and from the Play caches. Supersedes the `AppPlatform.android` idea in Phase 4. | `AppStoreState`, "Day x of 7" and every `AppDetail` link are App Store concepts; `AppPlatform.allCases` would leak Android into the Apple app detail and `CreatePlatformSheet`; a second copy of the Play app list would need to stay in step with `GooglePlayAppItem`. |
| H2 | **The Play sync leg never opens an edit** (keeps D14). Per account: `fetchApps` (same merge as the app list, moved to a shared type), missing icons, `fetchReleaseSummaries` per app, first page of reviews. | Background work must not cancel a CI upload. |
| H3 | **Widget mapping.** In Review ← lifecycle `IN_REVIEW`, `NOT_APPROVED`, `NOT_SENT_FOR_REVIEW`. Awaiting Release ← `APPROVED_NOT_PUBLISHED` (managed publishing), plus staged rollouts (`inProgress` / `halted`) **from the tracks cache**, shown as a percentage bar instead of "Day x of 7". | Mirrors the App Store buckets. The rollout fraction only exists in `edits.tracks`, so it is as fresh as the last time the user opened Tracks or changed the rollout in the app (a successful write refreshes the cache); the row shows no bar when nothing is cached. |
| H4 | **Play reviews are saved as `CustomerReviewModel`** with `appId = packageName` under `review.{packageName}.{reviewId}`, next to the Apple ones. Recent Reviews and AllReviews resolve `review.appId` against both app sources and pass the real Play account. The `.apple` placeholder account in `HomeWidgetDataLoader` is removed (an orphaned review is dropped instead). | Reuses the neutral review cache, so the widget extension and notifications need no second review path. |
| H5 | **Review quota.** Background (`.lightweight`) sync reads reviews for at most 20 Play apps per run, rotating through the rest on later runs; full sync is capped at 5 concurrent like Apple. | Google allows about 200 review GETs per hour per app owner; a 30-minute background cadence must stay well under it. |
| H6 | **The WidgetKit extension reads one snapshot** written by the app after each sync (`WidgetDashboardSnapshot` in the App Group store: the three lists of ready-to-draw entries). The extension stops decoding `AppModel` / `CustomerReviewModel` and drops its own categorizer. | One categorization for in-app and home-screen widgets, both stores included, and the existing drift disappears. |
| H7 | **Navigation carries the provider.** `DashboardEntry.target` is `.appStore(AppModel)` or `.googlePlay(GooglePlayAppItem)`; the coordinator routes to `appDetail` or `googlePlayAppDetail`. The `app` and `review` deep links resolve the account first and branch on its provider. | Every tap site otherwise lands on the Apple-only `AppDetail`. |
| H8 | **Notifications become provider-neutral.** `SyncChange.StatusChange` carries a display label and color instead of `AppStoreState`; Play status changes are detected on the lifecycle state. | Same local notifications for both stores. |

### Tasks

- **S1 — Play sync leg.** Partition accounts by provider in `performSyncAll`; `GooglePlayAccountSync` (apps merge shared with `GooglePlayAppListViewModel`, scope filter, icons, summaries → `googleplay-releases.*`, reviews → `CustomerReviewModel`, `SyncMetadata`, `SyncChange`). Bounded concurrency; `accountsInProgress` and the "Syncing N accounts…" banner include Play accounts. `preloadWidgetIcons` also takes Play icon URLs. `AccountCascadeDeleter` removes the Play reviews. `testSyncAllSkipsNonAppleAccounts` changes intent.
- **S2 — `DashboardEntry` + builders.** `HomeWidgetDataLoader` builds entries from both sources; `HomeAppRowView`, `HomePhasedProgressView` (day/7 or percentage) and `HomeRecentReview` take the neutral type. Platform groups: iOS, macOS, tvOS, visionOS, Android (header glyph: the green `smartphone` already used on the Play app header).
- **S3 — Widgets.** In Review / Awaiting Release / Recent Reviews load both stores (H3, H4); widget summaries become store-neutral ("Apps waiting on review").
- **S4 — AllReviews.** Groups by app across both stores (also fixes the `uniqueKeysWithValues` crash on a duplicate app id); header "See more" routes by provider; pull to refresh runs the full sync including Play.
- **S5 — Routing and deep links (H7).** Coordinator helper, `DeepLink` handling, notification taps.
- **S6 — WidgetKit snapshot (H6).** Writer in the app after each sync and after a dashboard-affecting write; extension loader, DTOs and views read the snapshot; Android glyph and percentage progress in the extension rows.
- **S7 — Notifications (H8) and docs.**

Order: S1 → S2 → S3 → S4 → S5 → S6 → S7. S1–S5 change nothing for Apple-only users except the removed placeholder account; S6 is the only step that rewrites existing Apple behaviour and gets its own regression tests (snapshot for an Apple-only store must draw the same rows as today, plus the rows the extension currently misses).

Status:
- S1 ✅: `SyncService` runs Apple and Google Play accounts in one task group (Firebase is skipped); `GooglePlayAccountSync` takes only the edit-free seams (`GooglePlaySyncConnecting` = app list + icons + release summaries + reviews), so no edit can be opened by construction. The app list merge, the tracks to ask and the bounded summaries fetch moved to `GooglePlayAppListSync`, shared with `GooglePlayAppListViewModel`. Reviews are saved as `CustomerReviewModel` (`review.{packageName}.{reviewId}`); lightweight runs read at most 20 apps, resuming from `GooglePlayReviewRotation` (`googleplay-review-rotation.{accountId}`). `SyncState.providerByAccountId` drives the "Syncing 3 accounts… (2 App Store Connect, 1 Google Play)" banner; widget icons include the Play list icons. `AccountCascadeDeleter` removes the account's Play reviews (unless another Play account lists the package) and its rotation cursor. `GooglePlayTracksCache.fetchedAt` dates the rollout the Home shows (H3).
- S2 ✅: `DashboardEntry` / `DashboardReview` (provider, account, app id, name, icon, `DashboardPlatform`, status text + `DashboardStatusColor`, version, `DashboardProgress` phased or rollout, recency, `DashboardTarget`) built by `DashboardEntryBuilder` from `AppModel` (through `AppStatusCategorizer`) and from `GooglePlayDashboardSource` (Play list item + summaries + tracks caches, `HomeWidgetDataLoader.loadGooglePlaySources`, scope- and rule-checked). The drawing vocabulary (`DashboardPlatform`, `DashboardStatusColor`, `DashboardProgress`) lives in `StackCore` for the extension. Rows group iOS → macOS → tvOS → visionOS → Android with a glyph header (`StackPlatformLabel`); without headers the row shows the glyph (`StackPlatformGlyphView`). `HomeDashboardProgressView` draws day x of 7 or the rollout bar with "Rollout as of …". `HomeCoordinator.open` routes a row by its target.
- S3 ✅: In Review and Awaiting Release merge the App Store rows with the Play rows of every Play account allowed to view `version` (scope-checked, caches only); Recent Reviews adds the Play reviews of accounts allowed to view `review`. Footnotes: "The Android rollout percentage is the last value read…" under rollout rows, "Google Play only shares reviews with a comment from the last 7 days." when Play reviews are listed. Widget summaries are store-neutral ("Apps waiting on review", "Approved releases and staged rollouts"). Fake data: Trailhead's open testing 4.3.0-beta2 is the release in review (production 4.2.0 rolls out at 20 %), and the fake store seeds each Play app's tracks cache as read the day before so the Home draws the rollout bars.
- S4 ✅: All Reviews groups the rows of both stores per app (`provider.appId`, so a package listed by two Play accounts is one group and a duplicate App Store app id no longer crashes the old `Dictionary(uniqueKeysWithValues:)`), shows the platform glyph and the Play note per Play section, and "See more" opens the app in its own store. The `.apple` placeholder account is gone: a review of an unknown account is dropped (rows keep showing only while the accounts can't be read at all, and the tap then resolves the account from storage). Pull to refresh runs the full sync, Play included (S1).
- S5 ✅: `HomeCoordinator.navigate(to:account:)` / `open(_:accountId:account:)` route a `DashboardTarget` to `appDetail` or `googlePlayAppDetail` (and a `DashboardReview` to Review Detail, with the package for Play). `DeepLinkResolver` resolves `stackconnect://app/…` and `…/review/…` (widgets and notification taps go through `DeepLinkRouter`) by loading the account first and branching on its provider; Play links carry the package name and the opaque review id, percent-encoded.
- S6 ✅: `WidgetDashboardSnapshot` (StackCore) holds the three lists as ready-to-draw rows (name, icon URL, `DashboardPlatform`, localized status, color, version, progress, deep link; 12 rows + full counts, 5 reviews). `WidgetDashboardSnapshotWriter` builds it with the in-app builders and saves it as `WidgetDashboard.json` in the App Group (a file rather than a SwiftData record: the extension needs no model container, and fake mode moves it like the icon cache) after every sync and after every Play release write, then reloads the timelines. The extension only reads the snapshot (its DTOs and categorizer are gone): rows with the Apple / Android glyph after the name (its own `AndroidGlyph` asset), "N apps" header, rollout / phased bars, per-row links, "Updated HH:mm" on the large family, its own string catalog. Regression tests: an Apple-only store draws the same rows (one per platform version, day x of 7) plus the rows the old extension missed (a still-phasing version behind a newer one) and without the orphan / duplicate rows it used to show. `-StackFakeDataWidgets YES` feeds the home-screen widgets in fake mode; `WidgetRenderingTests` renders them for review.
- S7 ✅: `SyncChange.StatusChange` carries a `StatusLabel` (text + color) instead of `AppStoreState`; App Store changes use the state name, Play changes are detected per release (track + version codes) on the lifecycle state, after the first sync ("Production · Approved, not published (2.8.1)"). `LocalNotificationService` posts both the same way; a single change opens the app in its store through `DeepLinkResolver`. Docs: this section, `google-play-account.md` (Phase 4), `FAKE_DATA.md`.
- Not done in this block: home-screen widgets were validated through `WidgetRenderingTests` renders, not by placing them on a simulator home screen; App Store version writes (release / pause a phased release) don't rewrite the WidgetKit snapshot themselves — the next sync does.

### Tests

Sync leg (no edit call is ever made, scope filter, quota rotation, failure of one account doesn't stop the others), entry builders (mapping table H3, missing tracks cache → no bar), mixed-store sorting and grouping, AllReviews with the same package under two accounts, deep links per provider, snapshot round-trip.

## 7. User management

Prototype: screens 16 (Users), 21 (Invite User), 17 (User Detail), 22 (App Permissions). Independent of the release and Home work: it needs neither edits nor `releases.list`, so it can be built in parallel once U-C1 lands.

### Starting point

- App Store Connect has a Users tab on the app list (`AppListView` segmented "Apps | Users", gated by `canView(.users)`), `UserAccess` (list, filter chips, invite sheet), `UserDetail` (roles, access, visible apps, remove / cancel invite).
- The core's `Users` capability is App Store–shaped: `inviteUser(email:firstName:lastName:roles:allAppsVisible:provisioningAllowed:)`, `updateUser(id:roles:…)`, `fetchUserVisibleApps`, `deleteUser(id:isPending:)`. None of it fits Google Play.
- `GooglePlayAppList` has no tabs; Play rule resources don't include `.users`.

### API surface (verified against the Android Publisher v3 discovery document)

| Need | Endpoint |
|---|---|
| List | `GET developers/{developerId}/users` (paged) → `email`, `name` (resource name), `accessState` (`INVITED`, `INVITATION_EXPIRED`, `ACCESS_GRANTED`, `ACCESS_EXPIRED`), `expirationTime`, `developerAccountPermissions[]`, `grants[] { packageName, appLevelPermissions[] }`, `partial` |
| Invite | `POST developers/{developerId}/users` with email, account permissions, grants, expiration |
| Edit account permissions / expiry | `PATCH developers/{developerId}/users/{email}` |
| Remove | `DELETE developers/{developerId}/users/{email}` |
| Per-app access | `grants.create` / `patch` / `delete` under the user |

20 account-level permissions (`CAN_MANAGE_PERMISSIONS_GLOBAL` is "Admin") and 14 app-level permissions. No edit is involved, so none of this can cancel a CI upload.

Not offered by the API: discovering the developer account ID, resending an invitation, a first / last name on invite, roles. To validate with a real account: which permission the calling service account needs (expected: Admin), whether `users.list` returns service accounts, and what `partial` means in practice.

### Decisions

| # | Decision | Rationale |
|---|---|---|
| U1 | **Separate Play screens, shared DS pieces.** New modules `GooglePlayUsers`, `GooglePlayUserDetail`, plus the invite and app-permission sheets; they reuse the look of `UserAccess` / `UserDetail` (avatar row, filter chips, toggle sections), with the repeated pieces extracted to `Infra/DS` (Stack*). The App Store modules are not generalized. | The data shape differs at every level (permissions instead of roles, per-app grants instead of visible apps, expiry, no names); a shared ViewModel would be conditionals all the way down. |
| U2 | **A new core capability, `PlayUsers`**, instead of bending `Users`: `fetchUsers`, `inviteUser(email, accountPermissions, grants, expiration)`, `updateUser(email, accountPermissions, expiration)`, `deleteUser(email)`, `setGrant(email, packageName, permissions)`, `deleteGrant(email, packageName)`. Permissions cross the FFI as raw strings; the app owns the typed catalog. | The App Store signature can't express grants or expiry, and raw strings keep a new Google permission from breaking decoding. |
| U3 | **Developer ID is an optional field in Add Account** (Google Play), stored on the account's Play settings (SwiftData, not Keychain; included in `.scexport`). It can be filled in later from the account settings; while it is empty the Users tab shows a one-field setup state. A `404` / `403` on the first load offers to correct it. | Google doesn't expose it and it isn't secret (it is in every Play Console URL). Asking up front avoids a setup step later, but it stays optional so adding an account for releases and reviews isn't blocked. |
| U4 | **Permission catalog in one type** (`GooglePlayPermissionCatalog`, mirroring `UserRoleCatalog`): display name, group (App access, Releases, Store presence, Users & feedback, Monetization), account-level ↔ app-level pairing, and implied permissions (any permission implies "View app information"; Admin implies all). Unknown permissions are preserved on save and listed as "Other". | One source for the list, detail, invite and app-permission screens; saving must never drop a permission the app doesn't know. |
| U5 | **Presets are app-side shortcuts** (Admin, Release manager, Support, Finance, Custom) that only pre-fill toggles. Nothing is stored about the preset. | Google Play has no roles; a stored preset would drift from the real permissions. |
| U6 | **Rules, same as App Store Connect.** Play rule resources gain `.users`: `canView` shows the tab, `canAdd` invites, `canEdit` changes permissions and grants, `canDelete` removes. Accounts created on the device get every permission; an imported (`.scexport`) account can manage users exactly as far as the `users` permissions in its export allow, and can't be re-exported. Older `.scexport` files have no `users` permission → tab hidden (fail closed). No feature flag: every write is an explicit, confirmed action on a screen that is new. | Same model as App Store Connect (`AccountModel` rules + `AccountOrigin`). |
| U7 | **Removing the calling service account or stripping its own Admin permission is blocked in the app** (compared by `client_email`), with an explanatory alert. | It would lock this account out of the tab, and of everything else if it removes itself. |
| U8 | **"Resend invitation" = delete + invite again** with the same permissions, offered only for `INVITATION_EXPIRED`, behind a confirmation that says so. | The API has no resend. |
| U9 | **App list chrome.** `GooglePlayAppList` adopts the App Store list layout (segmented "Apps | Users", large title, search, gear), per prototype screen 1. Offline-first: users are cached per account (`googleplay-users.{accountId}`), removed by `AccountCascadeDeleter`. | Parity with the App Store account screen; the cache holds e-mail addresses, so it must go with the account. |

### Tasks

- **U-C1 — Core `PlayUsers` capability (U2)** in `providers/googleplay/users.rs`: list with paging, invite, patch (field mask), delete, grant upsert / delete; `Capability.playUsers`; mock-server tests (paging, masks, `404` on unknown developer, `403` naming the missing permission); re-vendor.
- **U1 — Connection seam + models.** `GooglePlayUsersConnecting`; `GooglePlayUserModel` (access state typed and unknown-safe), `GooglePlayGrantModel`, `GooglePlayPermissionCatalog` (U4), presets (U5); developer ID on the account's Play settings, optional field in Add Account and editable in account settings, export / import (U3); cache; `GooglePlayErrorTranslator` copy for wrong developer ID, missing Admin permission, user already exists, not a Google account.
- **U2 — Rules (U6).** `.users` for Play in `AccountRuleResource.resources(for:)`, export picker, permissions summary.
- **U3 — App list chrome (U9)** and the Users tab entry.
- **U4 — `GooglePlayUsers`.** Setup state (developer ID), search, filter chips (All, Admins, Invited, Expired, Service accounts), rows (avatar, name or e-mail, summary, state / scope badge), swipe Remove and Resend (U8), pull to refresh, sync toast.
- **U5 — `GooglePlayUserDetail`.** Header with access state, expiry, Admin toggle, account permissions, app grants list, Remove User; self-protection (U7).
- **U6 — Invite User sheet.** E-mail validation, expiry, presets, account permissions, app grants; pending state in the list after sending.
- **U7 — App Permissions sheet.** App picker (apps in the account's scope only) when adding, grouped toggles, implied permissions locked on, Remove Access.
- **U8 — Strings, docs.** `Localizable.xcstrings`; update `google-play-account.md` (D9 rule resources).

Order: U-C1 → U1 → U2 → U3 → U4 → U5 → U7 → U6.

### Tests

Catalog (implication rules, unknown permissions survive a round trip), ViewModels with a mock connection (setup state, filters, invite validation, self-protection, resend = delete + create, a failed write leaves the cache untouched), rules for old exports and for imported accounts with partial `users` permissions, error translator, cascade delete of the users cache, export / import of the developer ID.

Status:
- U-C1 ✅ in the core; re-vendored (`FakePlayUsers` overrides every `PlayUsers` method).
- U1 ✅: `GooglePlayUsersConnecting` on `GooglePlayAccountConnection` (online only, raw permission strings, RFC 3339 expiry); `GooglePlayUserModel` (typed, unknown-safe `GooglePlayUserAccessState`, name derived from the e-mail since Google has none, service accounts by domain), `GooglePlayGrantModel`; `GooglePlayPermissionCatalog` (all 17 current account-level and 13 app-level values plus Admin, grouped as in prototype 22, legacy `CAN_SEE_ALL_APPS` / `CAN_ACCESS_APP` read as "View app information", implications, unknown values kept and listed as "Other", list summary) and `GooglePlayPermissionPreset` (Admin, Release manager, Support, Finance, Custom; account-level toggles only). Developer ID: `AccountModel.googlePlayDeveloperId` (SwiftData, accepts digits or a pasted Play Console URL), optional field in Add Account, editable in Account Settings, written to / read from `.scexport` (`googlePlayDeveloperId`, invalid values dropped). `GooglePlayUsersCache` (`googleplay-users.{accountId}`), removed by `AccountCascadeDeleter`. Translator copy (`.users`, `.inviteUser`, `.userChange`): wrong developer ID (404), missing Admin (`Auth` / 403), user already exists (409), not a Google account (400), user or access gone (404 on a change). Fake data: 10 users for Northwind Labs and developer ID `4829103756618820931` on the fake Play account.
- U2 ✅: Play rule resources are `[.apps, .version, .review, .users]`, so the export picker and the Account Settings permissions summary offer Users (Play footer copy). Accounts created on the device get every permission; an older `.scexport` has no `users` permission and hides the tab (fail closed). D9 in `google-play-account.md` updated.
- U3 ✅: `GooglePlayAppList`'s entry owns both tabs like the App Store `AppListEntry`: account title, "Apps | Users" segmented control (Users only with `canView(.users)`, reusing `AppListTab`) and the trailing gear. The Users tab (`GooglePlayUsers`) loads offline-first from `googleplay-users.{accountId}`, re-reads the account so a developer ID set in Account Settings is picked up, shows the one-field setup state while the ID is empty (digits or a pasted Play Console URL; changing it drops the other account's cache) and, on a 404 / 403, an error with "Change Developer ID". `GooglePlayUsersAccess` holds the rules (U6), the per-app scope limits and self-protection (U7) in one place. DS: `StackAvatar`, `StackPersonRow`, `StackPersonHeader`, `StackFilterChips`.
- U4 ✅: Users list per prototype 16: search (name or e-mail), filter chips All / Admins / Invited / Expired (invitation or access) / Service accounts, rows (avatar tone by state, derived name or the address for invitations, "Invitation sent / expired", permission summary with app count and expiry, All Apps / N Apps / Invited / Expired badge), "Users (N)" header and the swipe footer. Swipe Remove (confirmation; Cancel Invitation wording for pending ones) and Resend on expired invitations (confirmation saying it is delete + invite again; the same permissions, app access and a still-future expiry; if the new invite fails, the removed invitation leaves the list too). Refusals (rules, scope, the service account itself) explain themselves in an alert. Writes update the list and the cache only on success; pull to refresh; sync toast. The App Store Users list (filter strip, row, avatar) and User Detail header now use the same DS pieces.
- U5 ✅: `GooglePlayUserDetail` (prototype 17, route `googlePlayUserDetail`): header (avatar, name, e-mail, access state badge), Access (expiry row → `GooglePlayAccessExpirySheet`, shared with the invite sheet; Admin toggle), Account Permissions · All Apps (every account-level permission; implied ones shown on and locked: everything under Admin, "View app information" under any other), "Other" for values the catalog doesn't know (kept on save), App Permissions (N) rows with icon, name and summary, swipe Remove Access, and Remove User / Cancel Invitation. Save (nav bar) sends the normalized account permissions and the expiry; grants and removals are immediate, behind confirmations. Every write updates the screen and `googleplay-users.*` only after Google accepted it (`GooglePlayUsersCacheStore`), so the list shows it on the way back without a request. Self-protection (U7): the service account (by `client_email`) can't lose Admin nor be removed, with an explanatory alert and footer. A scoped import can't change account-wide permissions; a `partial` user is read-only.

## 8. Open questions

1. Should the write flag (R6) be ON in Debug builds by default?
2. Country targeting editing: this block (adds a country picker) or with the Store block?
3. Custom closed tracks: `releases.list` needs the track name, and track names are only discoverable through an edit. Accept that custom-track status appears only after the user has opened Tracks once (names cached), or probe on first open of the app detail?
4. Awaiting Release for Android: is a possibly stale rollout percentage (H3) acceptable, or should the row show "Rolling out" with no number unless the cache is recent?
5. Should "Not sent for review" count as In Review on the dashboard (H3), as "Ready for Review" does for the App Store?

### Resolved

- Imported Play accounts and users: same rule as App Store Connect — the export's `users` permissions decide (U6).
- Developer ID: optional field in Add Account, editable later (U3).
