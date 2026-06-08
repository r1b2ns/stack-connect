# Handover — Windows Port Wave 0 & Wave 1 Development

**Date:** 2026-06-08
**Skill:** `/personal-development` — **now SERIAL, ONE TASK PER SESSION** (the skill was rewritten: one agent at a time, foreground only; each session develops exactly one task end-to-end then ends).
**Base branch:** `experiment/windows`
**Artifact (source of truth):** `docs/refinements/2026-06-08-windows-apps-and-reviews.md`
**Test cases:** `docs/refinements/2026-06-08-windows-port-test-cases.md`
**Status:** Wave 0 COMPLETE (all 4 tasks done + merged). Wave 1 IN PROGRESS — T-W05 DONE and MERGED.

**Snapshot:**
- **Wave 0 (DONE):** All four foundation tasks merged into `experiment/windows`: T-W01 (`7ef4617`), T-W02 (`eba9738`), T-W03 (`1bf59ab`), T-W04 (`0786ae8`).
- **Wave 1 (IN PROGRESS):** T-W05 (`WindowsAppsListModel`) DONE and MERGED as `13e82b4`.

> **Wave 0 foundation complete.** Wave 1 development started. Next unblocked task: **T-W06** (`WindowsAppsListView` + `WindowsAppRow` — all dependencies met).

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
| **T-W06** | `WindowsAppsListView` + `WindowsAppRow` | T-W03, T-W04, T-W05 | ⏳ PENDING (next unblocked task) — waiting for development session. |
| **T-W07** | `WindowsAppDetailView` (header + metadata) | T-W03, T-W05 | ⏳ BLOCKED until T-W05 done. |
| **T-W09** | Status badges / category pills | T-W05 | ⏳ BLOCKED until T-W05 done. |
| **T-W11** | Clipboard sync UX + affordances | T-W01 (soft) | ⏳ BLOCKED softly (can start independently). |
| **T-W15** | macOS integration + WKWebView bridge | none | ⏳ BLOCKED (depends on iOS side stability first; soft block). |
| **T-W17** | Review detail view (header + reply composer UX) | T-W04 | ⏳ BLOCKED. |
| **T-W18** | Rating histogram + filter UI | T-W04 | ⏳ BLOCKED. |
| **T-W30** | Splash screen + app launch sequencing | none | ⏳ BLOCKED (late-stage task; wait for core features stable). |

---

## Now-unblocked tasks (situational awareness)

- **T-W06** (T-W03, T-W04, T-W05 all DONE) — **NEXT POINTER**.
- **T-W07** (T-W03, T-W05 both DONE).
- **T-W09** (T-W05 DONE).
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
| 6 | **T-W06** | ⏳ NEXT (pending) | Wave 1 — `WindowsAppsListView` + `WindowsAppRow` (deps: T-W03, T-W04, T-W05 all DONE) |

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
