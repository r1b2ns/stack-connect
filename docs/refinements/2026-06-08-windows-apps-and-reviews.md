# Refinement: Windows Port — Apps, App Detail, Ratings & Reviews, Recent Reviews Card

**Date:** 2026-06-08
**Status:** Refined
**Platform:** Windows port (SwiftCrossUI + WinUI backend, Swift 6)
**Features:** 5 — F1 Apps List, F2 App Detail, F3 Ratings & Reviews list, F4 Review Detail (with reply), F5 Recent Reviews Home card
**Scope:** 17 user stories (US-W01..US-W17), 31 tasks (T-W01..T-W31), 80 test cases (TC-001..TC-080)

---

## Reference Screenshots (iOS behavior reference)

1. **Home + Recent Reviews widget** — apps list + "Recent Reviews (5)" card (app icon, name, stars, time-ago, title, body excerpt, chevron; "See more").
2. **Apps list** — Apps|Users segmented control, account title, search by name/bundle ID, Favorites + All Apps, colored status dot + status text + version, archive button.
3. **App detail** — header card (icon, name, bundle id, status + version); platform "iOS" section + versions + See All; General (App Information, App Review, History); App Store (App Privacy, App Accessibility, Ratings and Reviews); Analytics; TestFlight; favorite + archive.
4. **Ratings & Reviews list** — "4.8" + stars + "42.308 ratings"; Filter by Rating; sort button; "Reviews (50)"; review cards (stars, date, title, body, nickname, chevron).
5. **Review detail** — Customer Review card (stars, datetime, title, full body, nickname, territory); "Write a Reply"; helper text; share button.

---

## Key Confirmed Decisions (from refinement Q&A)

| # | Decision |
|---|----------|
| D1 | **Windows v1 makes LIVE App Store Connect API calls** (apps, reviews, replies, users). Resolves the prior "no live sync" constraint for these screens. |
| D2 | Apps List includes **Search, Favorites toggle, Archive + separate Archived screen, and the Users tab** — all in scope. |
| D3 | App Detail: only **Ratings and Reviews** is functional; all other options + platform versions are **tappable → "Coming Soon"**. |
| D4 | Ratings list: **aggregate rating card + pagination (Load More)** in scope; **Filter & Sort hidden in v1** (model infra still built). |
| D5 | Review reply supports **Create + Edit + Delete** (create/edit = same upsert endpoint; delete via confirmation screen). |
| D6 | iOS **share replaced by Copy-to-clipboard** with "Copied!" confirmation. |
| D7 | Recent Reviews is an **in-app Home card** (not an OS widget), aggregating across **all connected accounts**, capped at **5 rows**. |
| D8 | **Re-import merges** data but **preserves local isFavorite/isArchived** flags. |
| D9 | Users tab uses a **new `WindowsUserModel`** fetched via live API. |

---

## 1. Requirements (Product Owner)

### 1.1 Summary
Five features bring the StackConnect Windows app to functional parity with iOS for the core App Store Connect workflow: browse apps, view app details, read and respond to customer reviews, and surface recent reviews on the Home dashboard. iOS is the behavioral reference; Windows-specific adaptations are documented under Assumptions.

### 1.2 User Stories

**Feature 1 — Apps List**
- **US-W01** View apps list for an ASC account — list rows show icon, name, colored status indicator, status text, version. (Must, M)
- **US-W02** Search apps by name or bundle ID — real-time, case-insensitive filtering. (Must, S)
- **US-W03** Toggle app favorite from the list — Favorites section, persisted. (Must, S)
- **US-W04** Archive an app + view/restore in a dedicated Archived Apps screen. (Must, M)
- **US-W05** Browse Users & Access tab — name + role. (Must, M)

**Feature 2 — App Detail**
- **US-W06** View app detail header + all option sections. (Must, M)
- **US-W07** Navigate to Ratings and Reviews from app detail. (Must, S)
- **US-W08** See "Coming Soon" for non-functional options. (Must, S)
- **US-W09** Toggle favorite and archive from app detail. (Must, S)

**Feature 3 — Ratings & Reviews List**
- **US-W10** View aggregate rating card (avg, stars, count). (Must, M)
- **US-W11** Browse paginated reviews via Load More. (Must, M)

**Feature 4 — Review Detail**
- **US-W12** View full review detail. (Must, S)
- **US-W13** Create, edit, and delete a reply. (Must, L)
- **US-W14** Copy review to clipboard. (Should, S)

**Feature 5 — Recent Reviews Home Card**
- **US-W15** View Recent Reviews card (up to 5, across all accounts, count badge). (Must, M)
- **US-W16** Navigate from card to Review Detail and to Reviews List. (Must, S)
- **US-W17** Refresh card (auto on load + manual). (Must, S)

### 1.3 Acceptance Criteria (grouped by feature)

**F1 — Apps List**
- AC-W01-1 Rows show icon, name, colored status, status text, version.
- AC-W01-2 Offline: cached list shown + stale/sync-error indicator.
- AC-W01-3 No apps → empty state.
- AC-W01-4 First load → loading indicator, no stale/partial content.
- AC-W01-5 Favorites section above All Apps; favorites only in Favorites.
- AC-W01-6/7/8 Status colors: Ready for Sale=green, Pending Developer Release=yellow, Prepare for Submission=blue (colored text fallback allowed).
- AC-W02-1..5 Search filters by name and bundle ID (case-insensitive); empty-match state; clearing restores sections; Favorites + All Apps filtered independently; empty sections hidden.
- AC-W03-1..3 Favorite toggle moves app between sections immediately, persists, survives restart.
- AC-W04-1..5 Archive requires confirmation; removes from main list; Archived screen lists archived apps; Restore requires confirmation and returns app to All Apps; empty archived state.
- AC-W05-1..5 Apps/Users tab strip (Apps default); Users tab shows name + role; switching back restores Apps list; loading + empty states.

**F2 — App Detail**
- AC-W06-1 Header: icon, name, bundle ID, colored status, status text, version.
- AC-W06-2 Sections rendered: General (App Information, App Review, History), App Store (App Privacy, App Accessibility, Ratings and Reviews), Analytics, TestFlight.
- AC-W06-3 Platform "iOS" + version placeholder shows "Coming Soon"; no navigation.
- AC-W06-4 Favorite + archive actions visible.
- AC-W07-1/2 "Ratings and Reviews" navigates to list with correct appId; back returns to detail with state intact.
- AC-W08-1/2 All 7 non-functional rows → "Coming Soon", no crash; dismiss returns to detail.
- AC-W09-1..3 Favorite toggle persists and reflects on list; archive confirms, pops to list, removed from main list.

**F3 — Ratings & Reviews List**
- AC-W10-1 Aggregate card: numeric average, stars, locale-formatted count.
- AC-W10-2 Rating loading state independent of reviews list.
- AC-W10-3 iTunes lookup failure → "Rating unavailable"; reviews still shown.
- AC-W11-1 Rows: stars, date ("21 May 2026"), bold title, 2–3 line body excerpt, nickname + person icon, chevron.
- AC-W11-2 Load More appends next page; spinner on button; button hidden when no more pages.
- AC-W11-3 First-page loading state; no partial/stale rows.
- AC-W11-4 Zero reviews → empty state; no Load More.
- AC-W11-5 First-page failure → non-blocking error + retry; cached reviews shown if available.
- AC-W11-6 Row tap → Review Detail with full review data.

**F4 — Review Detail**
- AC-W12-1 Full review: stars, "21 May 2026 at 12:10", title, full body, nickname + person icon, territory + globe icon.
- AC-W12-2 No reply → "Write a Reply" + helper text.
- AC-W12-3 Existing reply → reply body + date + Edit/Delete.
- AC-W13-1..4 Create: empty input disables Submit; submit shows loading + disables input; success shows reply inline + Edit/Delete + persists; failure shows error, no partial reply.
- AC-W13-5/6 Edit pre-populates text; save updates body + date + persists.
- AC-W13-7/8/9 Delete requires confirmation; success restores "Write a Reply" + persists; failure keeps reply + error.
- AC-W14-1/2 Copy formats review text to clipboard; shows "Copied!" confirmation.

**F5 — Recent Reviews Home Card**
- AC-W15-1 Card in widgetsSlot: header "Recent Reviews" + count badge, up to 5 rows, "See More".
- AC-W15-2 Row: app icon, app name, stars, time-ago, title, body excerpt, chevron.
- AC-W15-3 Fewer than 5 reviews → only available shown; badge accurate.
- AC-W15-4 No reviews anywhere → empty state in card.
- AC-W16-1 Row tap → Review Detail.
- AC-W16-2 "See More" → Ratings list of first (topmost) review's app.
- AC-W16-3 Back returns to Home with card state intact.
- AC-W17-1 Auto-fetch on Home load across all accounts.
- AC-W17-2 Manual Refresh button shows loading and updates content.
- AC-W17-3 Refresh failure → non-blocking error; cached reviews remain.

### 1.4 Assumptions
- A-01 "See More" navigates to the first/topmost review's app when reviews span multiple apps.
- A-02 Windows "Copy" replaces iOS share entirely (no share sheet).
- A-03 Recent Reviews card capped at 5 rows.
- A-04 Colored status indicators may fall back to colored text if a filled colored circle isn't renderable.
- A-05 Pagination uses a "Load More" button (no infinite scroll).
- A-06 Clipboard text format: app name, star line, datetime, title, body, "Reviewer: nickname, territory".

### 1.5 Out of Scope
Functional screens for App Information, App Review, History, App Privacy, App Accessibility, Analytics, TestFlight, and Platform Versions/See All (all "Coming Soon"); Filter by Rating; Sort; cross-app aggregated reviews screen; OS-level Windows widget; push notifications; review export (PDF/CSV); configurable card row count; user detail/edit screen.

---

## 2. Design Spec (UX Designer)

### 2.1 Screen / Route List
`appsList`, `archivedApps`, `appDetail`, `comingSoon(title)`, `ratingsAndReviews`, `reviewDetail`, `replyComposer`, `deleteReplyConfirm`, plus the existing Home (Recent Reviews card injected into `widgetsSlot`). All secondary actions are **pushed routes** (no sheets/alerts).

### 2.2 Route Enum
```
enum WindowsRoute {
  case home
  case appsList(accountId)
  case archivedApps(accountId)
  case appDetail(appId, accountId)
  case comingSoon(title)
  case ratingsAndReviews(appId, bundleId, accountId)
  case reviewDetail(reviewId, appId, accountId)
  case replyComposer(reviewId, accountId, existingReplyBody?)
  case deleteReplyConfirm(reviewId, responseId, accountId)
}
```

### 2.3 Navigation Flow
- Home → Recent Reviews card: row tap → `reviewDetail`; "See more" → `ratingsAndReviews`.
- Accounts list → `appsList` → (Archived button → `archivedApps`; app row → `appDetail`).
- `appDetail`: "Ratings and Reviews" → `ratingsAndReviews`; any other option / "See All" → `comingSoon`.
- `ratingsAndReviews`: review row → `reviewDetail`.
- `reviewDetail`: "Write a Reply"/"Edit Reply" → `replyComposer`; "Delete Reply" → `deleteReplyConfirm`.
- Back via existing "< Back" convention; coordinator manages push/pop.

### 2.4 Component Inventory
`StatusBadge` (colored pill), `AppRow`, `ReviewRow` (list + home variants), `RatingStars` (Unicode stars), `AggregateRatingCard`, `SectionHeader` (+ optional "See All"), `OptionRow` (glyph + label + chevron), `ComingSoonView`, `ReplyComposerView`, `DeleteConfirmView`, `LoadMoreButton`, `CountBadge`, and the existing `InfoBar` (sync/error/copy-confirm; auto-dismiss via `Task.sleep`). Apps|Users uses a custom **tab strip** (HStack of buttons + accent underline) to simulate a segmented control.

### 2.5 Per-Screen Layout (top → bottom)
- **Home card:** header ("Recent Reviews" + count badge + refresh) → up to 5 `ReviewRow` (home variant) → "See more". States: loading/empty/error (InfoBar).
- **Apps & Users:** toolbar (back + account name + Archived) → tab strip → search `TextField` → (Apps: Favorites section + All Apps section, or filtered flat list; empty/loading states) / (Users: name + role rows, no chevron).
- **Archived Apps:** toolbar → archived `AppRow` + "Restore" per row → empty state.
- **App Detail:** toolbar → header card → platform section ("iOS" + See All → Coming Soon) → General/App Store/Analytics/TestFlight `OptionRow`s → favorite + archive buttons.
- **Coming Soon:** toolbar (title) → centered glyph + title + "This feature is coming soon."
- **Ratings & Reviews:** toolbar (no sort/filter in v1) → `AggregateRatingCard` → reviews list (`ReviewRow` list variant) → `LoadMoreButton` (when more pages) → error banner.
- **Review Detail:** toolbar (back + Copy) → review card (stars, datetime, title, full body, nickname, territory) → reply section (no-reply: "Write a Reply" + helper / existing: reply body + date + Edit/Delete) → error/success banners.
- **Reply Composer:** toolbar (Cancel) → multiline `TextEditor` (prefilled when editing) → helper text → Submit (loading) + Cancel (dirty-state guard) → error banner.
- **Delete Confirm:** compact centered confirmation (warning + message + Cancel/Delete[destructive]); success pops to clean `reviewDetail`.

### 2.6 WinUI / Fluent Adaptations
Segmented control → tab strip; `.sheet` → pushed routes; swipe actions → explicit buttons; FAB → right-aligned bottom button; share sheet → Copy + InfoBar; colored SF Symbol tiles → colored rounded-rect + glyph/text; pull-to-refresh → explicit Refresh button; long-press menu → inline buttons; large titles → toolbar title.

### 2.7 UX Risks
1. Fluent/SF glyph rendering in SwiftCrossUI (needs a day-one spike; fallback to colored rect + short text). 2. Reply composer without sheets → dirty-state guard (inline Discard/Keep editing). 3. Delete confirm as a pushed route may read like a page → use compact "dialog-like" layout, no page-name title. 4. "See more" → single app may confuse on multi-app cards → annotate with app name. 5. InfoBar auto-dismiss needs a cancellable `Task.sleep` timer. 6. Multi-account aggregation cost → fetch sequentially / progressive population. 7. Users tab dead-end → remove chevron so rows read as informational.

---

## 3. Task Breakdown (Developer)

### 3.1 Codebase Findings
- **Coordinator:** `WindowsHomeCoordinator` uses a hand-rolled `routeStack: [WindowsRoute]` (`push/pop/popToRoot`); `RootView.destination(for:)` switches exhaustively (no `default`) → adding routes is compile-safe. Existing `.appDetail/.reviewDetail/.allReviews` cases are **value-less** and must be parameterized.
- **Pattern:** ViewModels ("Models") live in testable lib `WindowsAppCore` (`@SwiftCrossUI.Published`, `@MainActor`); template = `WindowsAccountsListModel`. Views live in executable `StackConnectWindowsApp` and create models via `@State`. DI (`storage: PersistentStorable`, `secrets: KeyStorable`) injected at init via `WindowsHomeModel`. Mocks `MockStorage`/`MockSecrets` exist.
- **Models present:** `AppModel` already has `isArchived/isFavorite/platformVersions/appStoreState`; `CustomerReviewModel` has `territory/responseId/responseBody/responseState/responseDate/appId` + `hasResponse`. `AppStoreState.color` exists. `StarRatingFormatter` + `HomeRecentReview` + `RecentReviewsWidget` (aggregates ≤5 across accounts) exist in `StackHomeCore`.
- **API gap (critical):** `AppleAccountConnection` lives only in the iOS target and is Foundation-pure, but the **Windows GUI package does not depend on `appstoreconnect-swift-sdk`** (the headless `StackConnectWindows` package proves it builds on Windows via branch `windows-support`). → **T-W01 spike** resolves availability (Option A: extract to shared `Packages/StackAppleConnection`; Option B: add SDK to Windows GUI package + copy connection class). A connection protocol is needed for testability.
- **SwiftCrossUI verified:** `TextField`/`TextEditor`/`SecureField`, `Color` + `RoundedRectangle`/`.fill`/`.cornerRadius`, `Button`, `ProgressView`, `ScrollView/VStack/HStack/ForEach` all work. **No SF Symbols** (use text/emoji glyphs). `WindowsClipboard.getText()` exists; **`setText()` does not** (→ T-W02).
- **Placement:** new ViewModels + `iTunesLookupService` go in `WindowsAppCore`. **SwiftPM auto-discovers** new `.swift` files (no xcodegen for Windows; only `Package.swift` change is the SDK dependency in T-W01).

### 3.2 Tasks

**Wave 0 — Foundation**
- **T-W01 (L)** Spike: resolve `AppleAccountConnection` availability for the Windows GUI (Option A shared package vs Option B copy); define a testable connection protocol; verify dependency graph + review/user/reply/pagination methods callable. *Deps: —*
- **T-W02 (S)** Spike: implement `WindowsClipboard.setText()` (Win32 `OpenClipboard/EmptyClipboard/GlobalAlloc/SetClipboardData`); macOS stub returns false; add test. *Deps: —*
- **T-W03 (M)** Extend `WindowsRoute` with parameterized cases (appsList, archivedApps, appDetail, comingSoon, ratingsAndReviews, reviewDetail, replyComposer, deleteReplyConfirm); wire placeholders in `RootView`; update Home `widgetsSlot` closures. *Deps: —*
- **T-W04 (M)** Reusable components in `Shared/`: `WindowsStatusBadge`, `WindowsSectionHeader`, `WindowsOptionRow`, `WindowsRatingStarsView`, `WindowsLoadMoreButton`, `WindowsCountBadge`, `WindowsComingSoonView`, extract `WindowsDateFormatting.relativeDate`. *Deps: —*

**Wave 1 — F1 Apps List**
- **T-W05 (M)** `WindowsAppsListModel` (offline-first load + live sync, search filter, favorite/archive toggle with persistence + revert-on-failure). *Deps: T-W01*
- **T-W06 (L)** `WindowsAppsListView` + `WindowsAppRow` (toolbar, tab strip, search, Favorites/All sections, states; row tap → appDetail). *Deps: T-W03, T-W04, T-W05*
- **T-W07 (S)** `WindowsArchivedAppsView` (archived rows + Restore; empty state). *Deps: T-W03, T-W05*
- **T-W08 (M)** `WindowsUsersListModel` + `WindowsUserModel` + `WindowsUsersTabView` (live `fetchUsers`; name+role; states). *Deps: T-W01, T-W06*
- **T-W09 (M)** Unit tests for `WindowsAppsListModel` (load/cache/search/favorite/archive/revert). *Deps: T-W05*
- **T-W10 (S)** Wire `.appsList`/`.archivedApps` in `RootView`; navigate from accounts row (non-expired). *Deps: T-W03, T-W06, T-W07*

**Wave 2 — F2 App Detail**
- **T-W11 (M)** `WindowsAppDetailModel` (cache load + optional live refresh; favorite/archive). *Deps: T-W01 (soft)*
- **T-W12 (M)** `WindowsAppDetailView` (header card, option rows, platform "Coming Soon", favorite/archive). *Deps: T-W03, T-W04, T-W11*
- **T-W13 (S)** Unit tests for `WindowsAppDetailModel`. *Deps: T-W11*
- **T-W14 (S)** Wire `.appDetail`/`.comingSoon` in `RootView`. *Deps: T-W03, T-W04, T-W12*

**Wave 3 — F3 Ratings & Reviews**
- **T-W15 (M)** `iTunesLookupService` (175-storefront concurrent lookup; pure `computeWeightedAverage`; SQLite TTL cache). *Deps: —*
- **T-W16 (L)** `WindowsRatingsReviewsModel` (parallel aggregate + first page; Load More; hidden sort/filter infra). *Deps: T-W01, T-W15*
- **T-W17 (S)** `WindowsAggregateRatingCard` component. *Deps: T-W04*
- **T-W18 (S)** `WindowsReviewRow` component. *Deps: T-W04*
- **T-W19 (M)** `WindowsRatingsReviewsView` (card + list + Load More + states; row tap → reviewDetail). *Deps: T-W03, T-W16, T-W17, T-W18*
- **T-W20 (M)** Unit tests for model + `iTunesLookupService`. *Deps: T-W15, T-W16*
- **T-W21 (S)** Wire `.ratingsAndReviews` in `RootView`. *Deps: T-W03, T-W19*

**Wave 4 — F4 Review Detail**
- **T-W22 (M)** `WindowsReviewDetailModel` (load review; sendReply upsert; deleteReply; copyReviewToClipboard). *Deps: T-W01, T-W02*
- **T-W23 (M)** `WindowsReviewDetailView` (full review; reply states; Copy; banners). *Deps: T-W03, T-W22*
- **T-W24 (M)** `WindowsReplyComposerView` (+ optional focused composer model; multiline editor; submit/loading; dirty guard). *Deps: T-W03, T-W22*
- **T-W25 (S)** `WindowsDeleteReplyConfirmView` (confirm/cancel; error). *Deps: T-W03, T-W22*
- **T-W26 (M)** Unit tests for `WindowsReviewDetailModel` (send/edit/delete success+failure; clipboard string build; guards). *Deps: T-W22*
- **T-W27 (S)** Wire `.reviewDetail`/`.replyComposer`/`.deleteReplyConfirm` in `RootView`. *Deps: T-W03, T-W23, T-W24, T-W25*

**Wave 5 — F5 Recent Reviews Card**
- **T-W28 (M)** Enhance `WindowsRecentReviewsWidgetView` + `widgetsSlot` for real navigation (review→detail, see-more→ratings, app→detail) + count badge. *Deps: T-W03, T-W04, T-W19, T-W23*
- **T-W29 (S)** Verify auto-refresh via `HomeViewModel.loadDashboard()` + add manual refresh button. *Deps: T-W28*
- **T-W30 (S)** Integration test: multi-account aggregation cap-5 + date-desc in `RecentReviewsWidgetTests`. *Deps: —*

**Wave 0/6 — Re-import merge (from D8)**
- **T-W31 (M)** On `.scexport` re-import, **merge** app data while preserving local `isFavorite`/`isArchived` (read existing `AppModel` from SQLite, carry flags forward before save). Add unit test. *Deps: T-W05 (model conventions); import path in WindowsAppCore.*

### 3.3 Parallelization & Critical Path
- **Wave 0 parallel:** T-W01, T-W02, T-W03, T-W04, T-W15, T-W30 (and T-W31 design).
- After T-W01: F1/F2/F3/F4 models unblock; component tasks (T-W17/T-W18) need only T-W04; all unit-test tasks run alongside their views.
- **Critical path:** `T-W01 → T-W16 → T-W19 → T-W28 → T-W29` (T-W01 is the single most important blocker).

### 3.4 Technical Risks
- **R1 (HIGH→mitigated by D1/T-W01):** SDK availability + dependency-graph resolution in the SwiftCrossUI package.
- **R2 (LOW):** `setText()` Win32 implementation (mirror of existing `getText()`).
- **R3 (MED):** iTunes lookup is slow / many concurrent requests → TTL cache + stale-while-revalidate.
- **R4 (LOW):** Opaque pagination token not serializable → re-entry reloads page 1 (matches iOS).
- **R5 (MED):** Multi-account aggregation cost → sequential/progressive fetch.
- **R6 (LOW):** TextEditor placeholder / `.lineLimit` gaps → label placeholder + manual truncation.
- **R7 (MED):** Parent/child state sync on pop → review detail re-fetches in `.task` after composer/delete pops.

### 3.5 Resolved Doubts
Q-01 → **live API enabled (D1)**; Q-02 → **live API + `WindowsUserModel` (D9)**; Q-03 → platform versions remain "Coming Soon" (no data needed); Q-04 → **build hidden filter/sort infra (D4)**; Q-05 → reply is **upsert** (same call for create/edit, D5); Q-06 → "See more" → first review's app (A-01); Q-07 → **merge on re-import (D8 → T-W31)**.

---

## 4. Test Cases (QA)

> Full document: [`2026-06-08-windows-port-test-cases.md`](./2026-06-08-windows-port-test-cases.md) — **80 test cases (TC-001..TC-080)**.

### 4.1 Coverage Summary
- **F1 Apps List:** TC-001..TC-013 (cache load, live sync, search by name/bundleId, favorites, archive/restore, users tab, empty + network-failure edges).
- **F2 App Detail:** TC-014..TC-022 (header, sections, Ratings navigation, 7 Coming-Soon placeholders + platform versions, favorite toggle, archive pop-back).
- **F3 Ratings & Reviews:** TC-023..TC-031 (aggregate card, iTunes fallback, paginated list, Load More, pagination reset on re-entry, empty/error).
- **F4 Review Detail:** TC-032..TC-044 (full display, reply create/edit upsert, delete confirm cancel vs confirm, copy-to-clipboard Windows + macOS-host fallback, API errors).
- **F5 Recent Reviews Card:** TC-045..TC-055 (multi-account aggregation cap-5 + date-desc, count badge, row→detail, see-more→ratings, auto/manual refresh, empty/error + cache fallback, TTL).
- **Cross-feature / Integration:** TC-056..TC-077 (re-import merge preserving flags, favorite/archive persistence across restart, navigation stack + multi-level routes, parent/child state sync, favorite preserved during archive).
- **Edge / boundary:** TC-059..TC-080 (empty accounts, timeouts, 500/401, special chars + long text + emoji in nickname, old/future dates, opaque pagination token).
- **Platform constraints:** TC-068..TC-073 (no sheets/swipe/pull-to-refresh/alerts; Load More; clipboard Windows-only fallback).
- **Pure-logic units:** TC-078 search filter, TC-079 iTunes weighted average, TC-080 pagination token opacity.

### 4.2 Automation Split
- **Automatable (~60):** Unit/Integration on `WindowsAppsListModel`, `WindowsUsersListModel`, `WindowsAppDetailModel`, `WindowsRatingsReviewsModel`, `WindowsReviewDetailModel`, `iTunesLookupService`, and core `RecentReviewsWidget` — using `MockStorage`/`MockSecrets` + mocked connection.
- **Manual / UI (~25):** SwiftCrossUI rendering, navigation push/pop, glyph rendering, clipboard on Windows.
- **P0 (launch-critical):** 14 (live load, reply create/delete, multi-account aggregation, navigation integrity, persistence/merge).

### 4.3 Test Data & Mocks
3 accounts (acct-001..003); 5 apps (mixed status, favorites, archived); 5 recent reviews spanning accounts; 3 users/app; rating distribution (4.8 avg / 42,308 total); seeded pagination tokens + reply states. A **connection protocol** (from T-W01) must be mockable for model-level tests.

### 4.4 Coverage Matrix (US → TC)
| US | TC IDs |
|----|--------|
| US-W01 | TC-001, TC-002, TC-003, TC-059 |
| US-W02 | TC-004, TC-005, TC-006, TC-078 |
| US-W03 | TC-007, TC-008, TC-057 |
| US-W04 | TC-009, TC-010, TC-011 |
| US-W05 | TC-012, TC-013 |
| US-W06 | TC-014, TC-015 |
| US-W07 | TC-016 |
| US-W08 | TC-017, TC-018 |
| US-W09 | TC-019, TC-020, TC-021, TC-022 |
| US-W10 | TC-023, TC-024, TC-025 |
| US-W11 | TC-026..TC-031, TC-080 |
| US-W12 | TC-032, TC-033 |
| US-W13 | TC-034..TC-041 |
| US-W14 | TC-042, TC-043, TC-044 |
| US-W15 | TC-045..TC-049 |
| US-W16 | TC-050, TC-051, TC-052 |
| US-W17 | TC-053, TC-054, TC-055 |

*(See the full test-cases file for complete preconditions/steps/expected results per TC.)*

---

*End of refinement artifact. This document is the single source of truth for the subsequent development session (`/personal-development`).*
