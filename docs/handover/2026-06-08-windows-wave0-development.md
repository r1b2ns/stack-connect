# Handover — Windows Port Wave 0 & Wave 1 Development

**Date:** 2026-06-08
**Skill:** `/personal-development` — **now SERIAL, ONE TASK PER SESSION** (the skill was rewritten: one agent at a time, foreground only; each session develops exactly one task end-to-end then ends).
**Base branch:** `experiment/windows`
**Artifact (source of truth):** `docs/refinements/2026-06-08-windows-apps-and-reviews.md`
**Test cases:** `docs/refinements/2026-06-08-windows-port-test-cases.md`
**Status:** Wave 0 COMPLETE (all 4 tasks done + merged). Wave 1 IN PROGRESS — T-W05, T-W06, T-W07, T-W08 DONE and MERGED; T-W09 DONE (tests, awaiting merge).

**Snapshot:**
- **Wave 0 (DONE):** All four foundation tasks merged into `experiment/windows`: T-W01 (`7ef4617`), T-W02 (`eba9738`), T-W03 (`1bf59ab`), T-W04 (`0786ae8`).
- **Wave 1 (IN PROGRESS):** T-W05 (`WindowsAppsListModel`) DONE and MERGED as `13e82b4`. T-W06 (`WindowsAppsListView` + `WindowsAppRow`) DONE and MERGED as `de9b89a`. T-W07 (`WindowsArchivedAppsView` + Restore) DONE and MERGED as `0fcc886`. T-W08 (`WindowsUsersTabView`) DONE and MERGED as `bae0951`. T-W09 (`WindowsAppsListModel` comprehensive tests) DONE, awaiting merge (branch `feat/T-W09-windows-apps-list-model-tests` + commits `9c76869`, `629ee8a`). Next unblocked task: **T-W10** (wire `.appsList`/`.archivedApps` in RootView + navigate from accounts row — deps T-W03, T-W06, T-W07, T-W08 all DONE).

> **Wave 0 foundation complete.** Wave 1: T-W05/T-W06/T-W07/T-W08 DONE and MERGED; T-W09 DONE and awaiting merge. Next task: **T-W10**.

---

## Session decisions (locked in)

- **Scope:** Wave 0 — Foundation only: **T-W01, T-W02, T-W03, T-W04** (no inter-dependencies among them).
- **Git authorization:** **Commit only.** `git-docs-manager` auto-commits each green task. **Push, PR, and all merges (to `experiment/windows` or `master`) stay gated** — ask the user before any of them.
- **No AI attribution** in any commit/PR (verified on all commits so far).
- Windows SwiftPM packages auto-discover files → **no `xcodegen` needed** for Windows package changes (only for iOS app-target file changes).
- All test execution → `test-runner` agent. All git/docs → `git-docs-manager` agent.

---

## Task board (current state)

### Wave 0 (DONE)

| Task | Title | Branch | Commits | Gate state |
|------|-------|--------|---------|------------|
| **T-W01** | SDK + AppleConnectionProtocol for Windows GUI | `feat/T-W01-windows-apple-connection` | `7e5fbca` (feat) + `3eb047b` (correction) | ✅ DONE — merged `7ef4617`. Staff APPROVE / QA PASS 98/98 / PO ACCEPTED. 1 correction. |
| **T-W02** | `WindowsClipboard.setText()` | `feat/T-W02-windows-clipboard-settext` | `ab1f133` (feat) + `556c537` (correction) | ✅ DONE — merged `eba9738`. Staff APPROVE / QA PASS 89 tests 0 fail / PO ACCEPTED / 1 correction. |
| **T-W03** | Parameterize `WindowsRoute` + wire RootView | `feat/T-W03-windows-route-enum` | `d40635e` (feat) + `a34995e` (S-1 correction) | ✅ DONE — merged `1bf59ab`. Staff APPROVE / QA PASS 86 tests 0 fail / PO ACCEPTED / 1 correction. |
| **T-W04** | Shared Windows UI components | `feat/T-W04-windows-shared-components` | `949101a` (feat) | ✅ DONE — merged `0786ae8`. Staff APPROVE / QA PASS 104 tests 0 fail / PO ACCEPTED / 0 corrections. 3 non-blocking follow-ups (S-1, S-2, S-3). |

### Wave 1 (IN PROGRESS)

| Task | Title | Deps | Gate state |
|------|-------|------|------------|
| **T-W05** | `WindowsAppsListModel` (F1 Apps List) | T-W01 | ✅ DONE — merged `13e82b4`. Staff APPROVE (1 correction round: 3 should-fixes on duplicate-ID safety, cached fields on live-sync, loading-indicator test rename) / QA PASS 19 WindowsAppsListModelTests + full package 138/138 tests, 0 failures / PO ACCEPTED. 1 correction. |
| **T-W06** | `WindowsAppsListView` + `WindowsAppRow` | T-W03, T-W04, T-W05 | ✅ DONE — merged `de9b89a`. Staff APPROVE (1 correction round: BL-1 dead accountId removed from view+route+callsites, SF-1 state-guard order isSearchEmpty-before-isEmpty, SF-2 os.Logger fallback warning in RootView) / QA PASS (full WindowsAppCore suite 138 tests 0 failures; view-layer ACs inspection-verified; SwiftCrossUI rendering flagged platform-only manual) / PO ACCEPTED (all in-scope ACs met). 1 correction. |
| **T-W07** | `WindowsArchivedAppsView` (Archived Apps + Restore) | T-W03, T-W05 | ✅ DONE — merged `0fcc886`. Staff APPROVE (1 correction round: SF#1 silent storage-fetch error, SF#2 missing test, Nit#3 stale doc-comment) / QA PASS (150 tests, 0 failures; all TCs + edge cases verified) / PO ACCEPTED (AC-W04-3, AC-W04-4, AC-W04-5 all Met). 1 correction. |
| **T-W08** | `WindowsUsersTabView` (Users tab content) | T-W01, T-W06 | ✅ DONE — merged `bae0951`. Staff APPROVE (1 correction round: S-1 SwiftCrossUI-import observation left intentionally as-is per accepted pattern) / QA PASS (162 tests, 0 failures; TC-012, TC-013 + edge/negative verified; SwiftCrossUI platform-only) / PO ACCEPTED (AC-W05-1..5 all Met). 1 correction. |
| **T-W09** | Comprehensive unit tests for `WindowsAppsListModel` | T-W05 | ✅ DONE — awaiting merge from `feat/T-W09-windows-apps-list-model-tests`. Staff APPROVE (1 correction round: S-1 duplicate-ID assertion strengthened to `count == 2`, S-2 `SuspendableAppleConnection.resumeFetchApps` guarded against nil-continuation, N-1 removed trivially-true assertion, N-4 added `resumeIfPending()` teardown) / QA PASS (199 tests, 0 failures, all WindowsAppsListModelTests 56/56 green, no CheckedContinuation leaks) / PO ACCEPTED (all ACs met by real assertions). 1 correction (629ee8a). |
| **T-W10** | Wire `.appsList`/`.archivedApps` in RootView + navigate from accounts row | T-W03, T-W06, T-W07, T-W08 | ⏳ NEXT UNBLOCKED (all deps met). |
| **T-W11** | Clipboard sync UX + affordances | T-W01 (soft) | ⏳ BLOCKED softly (can start independently). |
| **T-W15** | macOS integration + WKWebView bridge | none | ⏳ BLOCKED (depends on iOS side stability first; soft block). |
| **T-W17** | Review detail view (header + reply composer UX) | T-W04 | ⏳ BLOCKED. |
| **T-W18** | Rating histogram + filter UI | T-W04 | ⏳ BLOCKED. |
| **T-W30** | Splash screen + app launch sequencing | none | ⏳ BLOCKED (late-stage task; wait for core features stable). |

---

## Now-unblocked tasks (situational awareness)

- **T-W09** (DONE — awaiting merge from `feat/T-W09-windows-apps-list-model-tests`; commits `9c76869`, `629ee8a`).
- **T-W10** (wire `.appsList`/`.archivedApps` in RootView + navigate from accounts row — deps T-W03, T-W06, T-W07, T-W08 now all DONE) — **NEXT POINTER**.
- **T-W11** (no critical blockers; T-W01 soft dep DONE).
- **T-W15** (no deps; soft-blocked pending iOS stability).
- **T-W17**, **T-W18** (T-W04 DONE).
- **T-W30** (no deps; late-stage, soft-blocked).

**Critical path (unchanged):** T-W01 → T-W16 → T-W19 → T-W28 → T-W29.

Worktrees live under `/Users/rubensmachion/repos/Open/stack-connect-worktrees/feat-<task>/`.

---

## What each task delivered

### T-W01 (branch `feat/T-W01-windows-apple-connection`)
Created:
- `StackConnectWindowsApp/Sources/WindowsAppCore/Connection/AppleConnectionProtocol.swift`
- `.../WindowsAppCore/Connection/ReviewSortOrder.swift` (correction; enum: `createdDateDescending`, `createdDateAscending`, `ratingDescending`, `ratingAscending`)
- `.../WindowsAppCore/Models/UserModel.swift`
- `.../WindowsAppCore/Models/ReviewsPage.swift`
- `.../StackConnectWindowsApp/Connection/WindowsAppleConnection.swift`
- `.../Tests/WindowsAppCoreTests/AppleConnectionProtocolTests.swift`
Modified: `StackConnectWindowsApp/Package.swift`, `.../Tests/WindowsAppCoreTests/Mocks/TestMocks.swift`.

Staff review findings (all addressed in `3eb047b`):
- **B-1 (blocking):** `upsertReply` only POSTed. Fixed: signature now `func upsertReply(reviewId: String, existingResponseId: String?, responseBody: String) async throws` using **delete-then-create** (SDK has **no PATCH** endpoint for `customerReviewResponses`).
- **S-1:** `@unchecked Sendable` → converted `WindowsAppleConnection` to an `actor`.
- **S-2:** `sort: String` → `sort: ReviewSortOrder`.
- **N-3:** mock argument capture added (lastFetchReviewsSort/FilterRating/Limit, lastUpsertReplyExistingResponseId).

### T-W02 (branch `feat/T-W02-windows-clipboard-settext`)
Modified `.../WindowsAppCore/Shared/WindowsClipboard.swift` (added `setText(_:) -> Bool`), created `.../Tests/WindowsAppCoreTests/WindowsClipboardTests.swift` (6 tests; TC-073 macOS-host returns false). 89 tests green.
Staff review CHANGES REQUESTED:
- **Blocking:** committed `setText` uses direct `memcpy(pMem, utf16Units, byteCount)` with a Swift array → must use `withUnsafeBufferPointer` (team standard from commit `37dbdc3`).
- **Should-fix:** add `defer { CloseClipboard() }`.
Correction agent `ae685d87701072ab0` **finished green** (89 tests, 0 fail). Fixes applied and committed as `556c537`: B-1 `memcpy` now inside `utf16Units.withUnsafeBufferPointer`; S-2 `defer { CloseClipboard() }` (removed 4 manual calls); N-2 reuse `wide(_:)` helper; N-1 `pMem`→`lockedPointer`; test nit `XCTAssertNotNil(retrieved)` added. **Committed 556c537, passed all gates (Staff APPROVE, QA PASS, PO ACCEPTED), not yet merged.**

**Non-blocking follow-up (do not block task completion):**
- **S-1 (should-fix):** replace `buffer.baseAddress!` force-unwrap in `WindowsClipboard.setText` with a guard-let defensive pattern (safe today because `wide()` always appends a null terminator, but defensive idiom preferred).
- **2 style nits:** (1) consistency in `EmptyClipboard` guard brace placement; (2) header-comment confirmation that the Windows clipboard is now properly locked/unlocked. Record these as optional cleanup for a future refactor, not blockers.

### T-W03 (branch `feat/T-W03-windows-route-enum`)
Modified `.../StackConnectWindowsApp/App/WindowsHomeCoordinator.swift` (parameterized cases: `appsList(accountId:)`, `archivedApps(accountId:)`, `appDetail(appId:accountId:)`, `comingSoon(title:)`, `ratingsAndReviews(appId:bundleId:accountId:)`, `reviewDetail(reviewId:appId:accountId:)`, `replyComposer(reviewId:accountId:existingReplyBody:)`, `deleteReplyConfirm(reviewId:responseId:accountId:)` — all ids `String`), `.../App/RootView.swift` (exhaustive `destination(for:)`, no default; placeholders via `WindowsPlaceholderView`), `.../Home/WindowsHomeView.swift` (widgetsSlot closures). 86 tests green.
Staff review APPROVE with should-fix:
- **S-1:** `onSeeMoreReviews` pushed `.comingSoon` instead of `.ratingsAndReviews(firstReviewApp)` (violates AC-W16-2 / A-01).
Correction agent `a72f606078658fd0d` **finished green** (86 tests, 0 fail). Changed `onSeeMore`/`onSeeMoreReviews` signature `() -> Void` → `(AppModel?) -> Void` across `WindowsRecentReviewsWidgetView.swift`, `WindowsWidgetContainerView.swift`, `WindowsHomeView.swift`; widget passes `data.reviews.first?.app`; `widgetsSlot` routes to `.ratingsAndReviews(appId:bundleId:accountId:)` (falls back to `.comingSoon` only when nil). **Committed as `a34995e`**. Task DONE: Staff APPROVE / QA PASS 86 tests 0 fail / PO ACCEPTED. 1 correction. Not yet merged (Wave 0 close-out).

### T-W04 (branch `feat/T-W04-windows-shared-components`)
Developer `a9537749abaac23c7` **finished green** (104 tests, 0 fail). 9 files created and **committed as `949101a`**:
- `.../StackConnectWindowsApp/Shared/WindowsStatusBadge.swift` (uses `AppStoreState.color`; Ready for Sale=green, Pending Developer Release=yellow, Prepare for Submission=blue; colored-text fallback per A-04)
- `.../StackConnectWindowsApp/Shared/WindowsSectionHeader.swift` (title + optional `onSeeAll`)
- `.../StackConnectWindowsApp/Shared/WindowsOptionRow.swift` (glyph/label + chevron; `.onTapGesture`)
- `.../StackConnectWindowsApp/Shared/WindowsRatingStarsView.swift` (delegates to `StarRatingFormatter.starString(for:)`)
- `.../StackConnectWindowsApp/Shared/WindowsLoadMoreButton.swift` (`isLoading` → `ProgressView()`)
- `.../StackConnectWindowsApp/Shared/WindowsCountBadge.swift` (hidden when count 0)
- `.../StackConnectWindowsApp/Shared/WindowsComingSoonView.swift` (centered glyph + title + message; plain literals)
- `.../WindowsAppCore/Shared/WindowsDateFormatting.swift` (Foundation-pure: `relativeDate(_:relativeTo:)` time-ago + `absoluteDate(_:timeZone:)` "d MMM yyyy"; injectable `now`)
- `.../Tests/WindowsAppCoreTests/WindowsDateFormattingTests.swift` (18 tests)

**Task DONE:** Committed as `949101a` with message:
```
feat(T-W04): add reusable Windows UI components and date formatting helper

Add 7 reusable SwiftCrossUI view components to Shared/ (WindowsStatusBadge,
WindowsSectionHeader, WindowsOptionRow, WindowsRatingStarsView,
WindowsLoadMoreButton, WindowsCountBadge, WindowsComingSoonView) and a
pure-logic WindowsDateFormatting helper in WindowsAppCore with relative
(time-ago) and absolute (d MMM yyyy) formatters.

WindowsStatusBadge uses AppStoreState.color for status-to-color mapping.
WindowsRatingStarsView reuses StarRatingFormatter from StackHomeCore.
WindowsDateFormatting is fully unit-tested (18 test cases).
```

**Gate verdicts:** All gates passed first review.
- **Staff Review:** APPROVE (no blocking findings; 3 non-blocking should-fix follow-ups).
  - **S-1:** `WindowsAppCore` target declares `SwiftCrossUI` in Package.swift — pre-existing drift from earlier account-model tasks (NOT introduced by T-W04). The new WindowsDateFormatting.swift is itself Foundation-only/clean. Follow-up: either remove SwiftCrossUI from WindowsAppCore + move the model files importing it into the executable target, or document the deviation.
  - **S-2:** `WindowsDateFormatting.absoluteDate(_:timeZone:)` allocates a new DateFormatter per call — cache it as a static formatter (single-threaded renderer, so safe).
  - **S-3:** `WindowsRecentReviewsWidgetView` has a private `relativeDate` duplicating `WindowsDateFormatting.relativeDate` (diverges on the Darwin path) — refactor to use the canonical helper. This file is owned by downstream task T-W28.
- **QA:** PASS (104 tests, 0 failures, including 18 new WindowsDateFormatting tests; all 7 components PASS-by-inspection).
- **PO:** ACCEPTED (all 6 acceptance criteria met).
- **Corrections:** 0 (first review approved).

Merged into `experiment/windows` as `0786ae8`. Wave 0 close-out complete.

---

## Wave 1 Development — T-W05 (DONE)

### T-W05 (branch `feat/T-W05-windows-apps-list-model`)
**Task:** Build `WindowsAppsListModel` — the data model fetching and managing the list of apps for the authenticated account, with cached state, live-sync merge strategy, and comprehensive test suite.

**Deliverables:**
- `StackConnectWindowsApp/Sources/WindowsAppCore/Models/WindowsAppsListModel.swift` — Main model with `@MainActor` concurrency protection, cached app store from SwiftData, live-sync merge logic using `uniquingKeysWith` to prevent duplicate-ID crashes.
- Preserved cached fields (`hasReviewPending`, `platformVersions`) across live-sync updates per staff feedback.
- `.../Tests/WindowsAppCoreTests/WindowsAppsListModelTests.swift` — 19 comprehensive test cases covering:
  - Initial load (empty cache, fetch from API).
  - Merge on live-sync (new apps, updated names, deleted apps).
  - Duplicate-ID safety via `uniquingKeysWith` resolver.
  - Cached metadata preservation.
  - Loading state transitions.

**Commits:**
- `046c133` (feat) — Initial `WindowsAppsListModel` and 15 test cases.
- `2e54227` (fix: staff should-fixes) — Corrections for duplicate-ID crash safety, cached-field preservation, and loading-indicator test rename.

**Gate verdicts:**
- **Staff Review:** APPROVE (after 1 correction round).
  - **B-0:** Duplicate-app IDs caused array merge crashes — fixed via `uniquingKeysWith { $1 }` (newer wins).
  - **S-1:** Live-sync merge overwrote `hasReviewPending`/`platformVersions` cached flags — fixed: filter merge to exclude these keys, restore from old state.
  - **S-2:** Loading indicator test name misleading (`testLoadingState` vs `testLoadingIndicator`) — renamed to `testLoadingTransitions` for clarity.
- **QA:** PASS (19 WindowsAppsListModelTests passing; full package run: 138 tests, 0 failures, no regressions).
- **PO:** ACCEPTED (all in-scope acceptance criteria met).
- **Corrections:** 1 (fix: 2e54227).

**Merged into `experiment/windows`:** Merge commit `13e82b4` (--no-ff merge strategy).

---

## Wave 1 Development — T-W06 (DONE)

### T-W06 (branch `feat/T-W06-windows-apps-list-view`)
**Task:** Build `WindowsAppsListView` + `WindowsAppRow` + `WindowsArchiveAppConfirmView` — the SwiftCrossUI view layer for Feature 1 (Apps List), consuming the merged `WindowsAppsListModel` (T-W05) and shared components (T-W04), wiring `.appsList` + `.archiveAppConfirm` in RootView.

**Deliverables:**
- `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Apps/WindowsAppsListView.swift` — toolbar (back + account name + Archived + Refresh), Apps|Users tab strip (Apps default), search field, Favorites + All Apps sections, loading/empty/search-empty/sync-error states.
- `.../Apps/WindowsAppRow.swift` — icon glyph, name, WindowsStatusBadge (colored status), version, favorite star toggle, explicit Archive button, chevron. No swipe actions.
- `.../Apps/WindowsArchiveAppConfirmView.swift` — archive confirmation as a PUSHED route (Confirm/Cancel), not an alert/sheet.
- Modified `.../App/WindowsHomeCoordinator.swift` (added `accountName` to `.appsList`; `.archiveAppConfirm(appId:appName:)` — `accountId` removed in correction per BL-1) and `.../App/RootView.swift` (wired `.appsList`/`.archiveAppConfirm` to real views; introduced `AppsListModelCache` reference-holder so both routes share one `WindowsAppsListModel`).

**Commits:**
- `9d08bdb` (feat) — Initial `WindowsAppsListView`, `WindowsAppRow`, `WindowsArchiveAppConfirmView`, and RootView integration.
- `e7bbcfa` (fix: staff BL-1/SF-1/SF-2) — Corrections for accountId removal, state-guard order, and os.Logger fallback.

**Gate verdicts:**
- **Staff Review:** APPROVE (after 1 correction round).
  - **BL-1 (blocking):** `WindowsRoute.archiveAppConfirm(accountId:appId:appName:)` carried dead `accountId` field (not used in view) — removed from enum case, updated RootView callsite, removed from WindowsArchiveAppConfirmView signature (option b applied).
  - **SF-1:** State-guard order in `WindowsAppsListView.buildAppsList()` — reordered guards to loading → isSearchEmpty → isEmpty → populated to prevent "No Apps" flash when search text is empty on first render.
  - **SF-2:** RootView's `.archiveAppConfirm` nil-model fallback had no logging — added `os.Logger.warning` under `#if canImport(os)`, matching the StackHomeCore HomeWidgetLog/SyncLog convention (since `Log.print` isn't available in the Windows app target).
- **QA:** PASS (full WindowsAppCore suite 138 tests, 0 failures, no regressions; view-layer acceptance criteria inspection-verified; SwiftCrossUI rendering flagged platform-only manual).
- **PO:** ACCEPTED (all in-scope acceptance criteria met).
- **Corrections:** 1 (fix: e7bbcfa).

**Merged into `experiment/windows`:** Merge commit `de9b89a` (--no-ff merge strategy).

**Notes:** Out-of-scope correctly deferred — T-W07 (Archived Apps screen + Restore) still a placeholder; T-W08 (Users tab content) still a placeholder. Windows package files auto-discovered → no xcodegen. Push/PR remain gated.

---

## Wave 1 Development — T-W07 (DONE)

### T-W07 (branch `feat/T-W07-windows-archived-apps-view`)
**Task:** Build `WindowsArchivedAppsView` + restore confirmation flow — the SwiftCrossUI view layer for Archived Apps screen, consuming the cached app list (T-W05), wiring `.archivedApps` + `.restoreAppConfirm` in RootView.

**Deliverables:**
- `StackConnectWindowsApp/Sources/WindowsAppCore/Models/WindowsArchivedAppsModel.swift` — Data model fetching and managing the list of archived apps, with cached state and live-sync merge.
- `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Apps/WindowsArchivedAppsView.swift` — toolbar (back + account name + Refresh), Archived apps list with status badges, loading/empty/sync-error states.
- `.../Apps/WindowsRestoreAppConfirmView.swift` — restore confirmation as a PUSHED route (Restore/Cancel).
- `.../Tests/WindowsAppCoreTests/WindowsArchivedAppsModelTests.swift` — 12 comprehensive test cases covering initial load, merge on live-sync, cached state preservation, and loading transitions.
- Modified `.../App/WindowsHomeCoordinator.swift` (added `.restoreAppConfirm(appId:appName:)` route) and `.../App/RootView.swift` (wired `ArchivedAppsModelCache` reference-holder and `.archivedApps`/`.restoreAppConfirm` routes to real views).

**Commits:**
- `3c8950e` (feat) — Initial `WindowsArchivedAppsModel`, `WindowsArchivedAppsView`, `WindowsRestoreAppConfirmView`, and RootView integration.
- `638b09f` (fix: staff SF#1/SF#2/Nit#3) — Corrections for silent storage-fetch error handling, missing test case, and stale doc-comment cleanup.

**Gate verdicts:**
- **Staff Review:** APPROVE (after 1 correction round).
  - **SF#1:** `WindowsArchivedAppsModel` cached load did not log errors if SwiftData fetch silently failed — added proper error handling and logging.
  - **SF#2:** Test coverage gap: missing test for empty archived apps state — added `testEmptyArchivedApps` test case.
  - **Nit#3:** Stale doc-comment in `WindowsRestoreAppConfirmView` referencing deleted field — removed.
- **QA:** PASS (150 tests total, 0 failures; 12 new WindowsArchivedAppsModelTests passing; all view-layer acceptance criteria verified; no regressions).
- **PO:** ACCEPTED (acceptance criteria AC-W04-3, AC-W04-4, AC-W04-5 all Met).
- **Corrections:** 1 (fix: 638b09f).

**Files created/modified:**
- NEW: `WindowsArchivedAppsModel.swift`, `WindowsArchivedAppsView.swift`, `WindowsRestoreAppConfirmView.swift`, `WindowsArchivedAppsModelTests.swift` (12 tests).
- MODIFIED: `WindowsHomeCoordinator.swift` (added `.restoreAppConfirm(appId:appName:)` route), `RootView.swift` (ArchivedAppsModelCache + `.archivedApps`/`.restoreAppConfirm` wiring).

**Merged into `experiment/windows`:** Merge commit `0fcc886` (--no-ff merge strategy). Worktree and branch removed.

---

## Wave 1 Development — T-W08 (DONE)

### T-W08 (branch `feat/T-W08-windows-users-tab`)
**Task:** Build `WindowsUsersTabView` — the SwiftCrossUI view layer for Users tab content in the Apps tab group, consuming the account-level user list (via `AppleConnectionProtocol.fetchUsers()`), wiring Users tab UI in `WindowsAppsListView`.

**Deliverables:**
- `StackConnectWindowsApp/Sources/WindowsAppCore/Users/WindowsUsersListModel.swift` — Data model fetching and managing the list of users for the authenticated account, with cached state and live-sync merge. Account-level user fetch (not per-app breakdown) per design review D1/D9 reconciliation.
- `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Users/WindowsUsersTabView.swift` — SwiftCrossUI view for Users tab content, replacing previous placeholder; toolbar (back + account name + Refresh), Users list with status indicators, loading/empty/sync-error states.
- `.../Tests/WindowsAppCoreTests/WindowsUsersListModelTests.swift` — 12 comprehensive test cases covering initial load, merge on live-sync, cached state preservation, and loading transitions.
- Modified `.../Apps/WindowsAppsListView.swift` (replaced `usersTabPlaceholder` with `WindowsUsersTabView`, added `usersModel` @State + init param to accept injected model).
- Modified `.../App/RootView.swift` (added `UsersListModelCache` reference-holder to share one `WindowsUsersListModel` instance across navigation contexts).

**Commits:**
- `046261d` (feat) — Initial `WindowsUsersListModel`, `WindowsUsersTabView`, test suite, and `WindowsAppsListView` replacement of placeholder.
- `74a294a` (fix: staff correction S-2/N-1/N-2/N-3) — Corrections for test-name clarity, redundant `_hasLoaded` init removal, RootView comment accuracy, and en-dash fallback inline comment.

**Gate verdicts:**
- **Staff Review:** APPROVE (after 1 correction round).
  - **S-1:** `WindowsUserModel` import in `WindowsUsersListModel` from Foundation-pure model (no duplicate model created) — observation noted; SwiftCrossUI import pattern in model file intentionally left as-is, consistent with accepted `WindowsAppsListModel` pattern.
  - **S-2:** Test name `testLoadingState` unclear — renamed to `testLoadingTransitions` for consistency.
  - **N-1:** Redundant `_hasLoaded` init assignment removed.
  - **N-2:** RootView comment accuracy clarified.
  - **N-3:** En-dash fallback inline comment added.
- **QA:** PASS (12 new WindowsUsersListModelTests passing; full package run: 162 tests, 0 failures, no regressions; TC-012, TC-013 + edge/negative cases verified; view-layer SwiftCrossUI rendering flagged platform-only manual).
- **PO:** ACCEPTED (acceptance criteria AC-W05-1 through AC-W05-5 all Met).
- **Corrections:** 1 (fix: 74a294a).

**Reconciliation note:** Users are fetched at account level via `AppleConnectionProtocol.fetchUsers()` (the earlier task breakdown's per-app `loadUsersForApp` was reconciled to account-level live load per design review D1/D9). The existing Foundation-pure `UserModel` from T-W01 was reused — no duplicate `WindowsUserModel` created, maintaining consistency with the codebase.

**Files created/modified:**
- NEW: `WindowsUsersListModel.swift`, `WindowsUsersTabView.swift`, `WindowsUsersListModelTests.swift` (12 tests).
- MODIFIED: `WindowsAppsListView.swift` (replaced users placeholder with real view, added model injection), `RootView.swift` (UsersListModelCache + model wiring).

**Merged into `experiment/windows`:** Merge commit `bae0951` (--no-ff merge strategy). Worktree and branch removed.

**Full test suite status:** 162 tests, 0 failures. All Wave 1 feature models (T-W05, T-W06 view layer, T-W07, T-W08) now complete and merged.

---

## Wave 1 Development — T-W09 (DONE)

### T-W09 (branch `feat/T-W09-windows-apps-list-model-tests`)
**Task:** Comprehensive unit tests for `WindowsAppsListModel` — extend the baseline 19 tests (from T-W05) to 56 tests covering load, cache, search, favorite, archive, and revert workflows with mid-flight state observation via suspendable mock.

**Deliverables:**
- Extended `StackConnectWindowsApp/Tests/WindowsAppCoreTests/WindowsAppsListModelTests.swift` from 19 → 56 test cases covering:
  - Initial load (empty cache, fetch from API).
  - Merge on live-sync (new apps, updated names, deleted apps).
  - Search filtering (by name, status).
  - Favorite toggle (local + remote sync).
  - Archive workflow (local + remote).
  - Revert on failure (favorite/archive rollback).
  - Duplicate-ID safety via `uniquingKeysWith`.
  - Cached metadata preservation.
  - Loading state transitions and mid-flight observation.
- Added `SuspendableAppleConnection` mock (additive, extends baseline mocks) to `StackConnectWindowsApp/Tests/WindowsAppCoreTests/Mocks/TestMocks.swift`:
  - Uses `CheckedContinuation` to observe mid-flight `isLoading` state.
  - Provides `resumeIfPending()` teardown helper to prevent leaked continuations.
- No production code changed (test-only task).

**Commits:**
- `9c76869` (feat) — Extended test suite from 19 → 56 tests, added `SuspendableAppleConnection` mock with CheckedContinuation support.
- `629ee8a` (fix: staff findings) — Corrections for S-1 (duplicate-ID assertion), S-2 (continuation safeguard), N-1 (trivial assertion removal), N-4 (teardown cleanup).

**Gate verdicts:**
- **Staff Review:** APPROVE (after 1 correction round).
  - **S-1:** Weak duplicate-ID remote assertion (only checked existence) — strengthened to explicit `count == 2` to catch off-by-one errors.
  - **S-2:** `SuspendableAppleConnection.resumeFetchApps` could resume a nil continuation on teardown misuse — added assertionFailure guard + nil-before-resume check.
  - **N-1:** Test `testDuplicateRemoteApps` had trivially-true assertion `fetchAppsCallCount == 0` — removed (fetch was never called in this path).
  - **N-4:** `SuspendableAppleConnection` CheckedContinuation could leak if test exited early — added `addTeardownBlock` with `resumeIfPending()` helper to safe-close all pending continuations.
- **QA:** PASS (full WindowsAppCore suite 199 tests, 0 failures, no flakiness, no CheckedContinuation leaks; `WindowsAppsListModelTests` 56/56 green; all test cases TC-001..011, TC-057/058/059, TC-078 covered by real assertions).
- **PO:** ACCEPTED (all in-scope acceptance criteria met: AC-W01-1..5, AC-W02-1..5, AC-W03-1..3, AC-W04-1..2 model slice, revert-on-failure favorite+archive — all verified by real, green test assertions).
- **Corrections:** 1 (commit `629ee8a`).

**Files created/modified:**
- EXTENDED: `WindowsAppsListModelTests.swift` (19 → 56 tests).
- MODIFIED: `TestMocks.swift` (added `SuspendableAppleConnection`).

**Status:** DONE — all gates passed. Branch `feat/T-W09-windows-apps-list-model-tests` awaiting merge into `experiment/windows` (pending explicit user authorization per project rule).

---

## Resume checklist — ONE TASK PER SESSION (serial)

The four agents from the old parallel run all finished green. The remaining work is now done **one task per session** (the new skill model). **Do exactly one task per session**, in this order, then update this handover and end the session.

### Session order (next session starts at the top non-done task)

| Order | Task | Status | Notes |
|-------|------|--------|-------|
| 1 | **T-W01** | ✅ DONE (merged `7ef4617`) | Wave 0 |
| 2 | **T-W02** | ✅ DONE (merged `eba9738`) | Wave 0 |
| 3 | **T-W03** | ✅ DONE (merged `1bf59ab`) | Wave 0 |
| 4 | **T-W04** | ✅ DONE (merged `0786ae8`) | Wave 0 |
| 5 | **T-W05** | ✅ DONE (merged `13e82b4`) | Wave 1 — `WindowsAppsListModel` |
| 6 | **T-W06** | ✅ DONE (merged `de9b89a`) | Wave 1 — `WindowsAppsListView` + `WindowsAppRow` + `WindowsArchiveAppConfirmView` |
| 7 | **T-W07** | ✅ DONE (merged `0fcc886`) | Wave 1 — `WindowsArchivedAppsView` + restore confirmation |
| 8 | **T-W08** | ✅ DONE (merged `bae0951`) | Wave 1 — `WindowsUsersTabView` (Users tab content) |
| 9 | **T-W09** | ✅ DONE (awaiting merge) | Wave 1 — Comprehensive unit tests for `WindowsAppsListModel` |
| 10 | **T-W10** | ⏳ NEXT (pending) | Wave 1 — Wire `.appsList`/`.archivedApps` in RootView + navigate from accounts row |

### Per-session rules (from the rewritten skill)
- **One agent at a time, foreground only** — never `run_in_background`; wait for each agent before the next.
- **Git auth is per session, commit-only** — confirm at session start. Push/PR stay gated. **Merges into `experiment/windows` need explicit user OK; never merge to `master` automatically.**
- After the task is **PO-ACCEPTED**, `git-docs-manager` updates this handover (mark done, record SHA/verdicts, set next-task pointer) and the session **ends** — the next task is a **fresh session** to save tokens.

### Wave 0 close-out (COMPLETE)
All four Wave 0 tasks have been implemented, passed all gates (Staff APPROVE, QA PASS, PO ACCEPTED), and are now merged into `experiment/windows`. Wave 0 Windows port foundation is live.

**Merged branches:**
- **T-W01:** `feat/T-W01-windows-apple-connection` → merged as `7ef4617`.
- **T-W02:** `feat/T-W02-windows-clipboard-settext` → merged as `eba9738`.
- **T-W03:** `feat/T-W03-windows-route-enum` → merged as `1bf59ab`.
- **T-W04:** `feat/T-W04-windows-shared-components` → merged as `0786ae8`.

Wave 0 is fully closed. Next unblocked task: **T-W05** (WindowsAppsListModel; depends only on T-W01, which is done).

## Key facts for gate agents
- Pass per-task slice of: Task Breakdown (artifact §3.2), Acceptance Criteria, Test Cases — keyed by task id.
- Package split: `WindowsAppCore` (testable, Foundation-pure, SDK-free) vs `StackConnectWindowsApp` (executable, SDK adapter lives here). SDK `appstoreconnect-swift-sdk` branch `windows-support` (fork `r1b2ns`) added to **executable target only**.
- Test-runner is the only agent that runs tests; git-docs-manager is the only agent that commits/pushes/PRs/merges/docs.
