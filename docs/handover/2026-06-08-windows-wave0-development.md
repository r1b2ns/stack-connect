# Handover — Windows Port Wave 0 & Wave 1 Development

**Date:** 2026-06-08
**Skill:** `/personal-development` — **now SERIAL, ONE TASK PER SESSION** (the skill was rewritten: one agent at a time, foreground only; each session develops exactly one task end-to-end then ends).
**Base branch:** `experiment/windows`
**Artifact (source of truth):** `docs/refinements/2026-06-08-windows-apps-and-reviews.md`
**Test cases:** `docs/refinements/2026-06-08-windows-port-test-cases.md`
**Status:** Wave 0 COMPLETE (all 4 tasks done + merged). Wave 1 COMPLETE (all 6 tasks done + merged). Wave 2 COMPLETE (F2 App Detail: T-W11..T-W14 all done). Wave 3 IN PROGRESS (F3 Ratings & Reviews + F4 Review Detail) — **T-W15** (M iTunesLookupService) DONE, **T-W16** (M WindowsRatingsReviewsModel) DONE, **T-W17** (S WindowsAggregateRatingCard) DONE, **T-W18** (S WindowsReviewRow) DONE, **T-W19** (M WindowsRatingsReviewsView) DONE, **T-W20** (S test consolidation) DONE, **T-W21** (M satisfied by T-W19), **T-W22** (M WindowsReviewDetailModel) DONE; next: **T-W23** (S WindowsReviewDetailView, deps T-W03+T-W22 satisfied).

**Snapshot:**
- **Wave 0 (DONE):** All four foundation tasks merged into `experiment/windows`: T-W01 (`7ef4617`), T-W02 (`eba9738`), T-W03 (`1bf59ab`), T-W04 (`0786ae8`).
- **Wave 1 (COMPLETE):** T-W05 (`WindowsAppsListModel`) DONE and MERGED as `13e82b4`. T-W06 (`WindowsAppsListView` + `WindowsAppRow`) DONE and MERGED as `de9b89a`. T-W07 (`WindowsArchivedAppsView` + Restore) DONE and MERGED as `0fcc886`. T-W08 (`WindowsUsersTabView`) DONE and MERGED as `bae0951`. T-W09 (`WindowsAppsListModel` comprehensive tests) DONE and MERGED as `216329f`. T-W10 (accounts-row → Apps List navigation) DONE and MERGED as `ad04ce6`.
- **Wave 2 (COMPLETE — F2 App Detail):** T-W11 (`WindowsAppDetailModel`) DONE and MERGED as `7186f9c`. T-W12 (`WindowsAppDetailView`) DONE and MERGED as `6e45f26`. T-W13 (Unit tests) DONE (no new diff; covered by T-W11). T-W14 (`RootView` route wiring verification) **DONE and MERGED as `6574aa1`** (verify commit `7ae86ba` + correction `a396b68`). Wave 2 Feature 2 (App Detail) complete.
- **Wave 3 (IN PROGRESS — F3 Ratings & Reviews + F4 Review Detail):** **T-W15** (iTunesLookupService) DONE and MERGED as `63b0e8a`. **T-W16** (WindowsRatingsReviewsModel) DONE and MERGED as `fa757b6`. **T-W17** (WindowsAggregateRatingCard) DONE and MERGED as `b1f97dd`. **T-W18** (WindowsReviewRow) DONE and MERGED as `493ddc7`. **T-W19** (WindowsRatingsReviewsView) DONE and MERGED as `cb32d93`. **T-W20** (test consolidation) DONE and MERGED as `6372480`. **T-W21** (wire .ratingsAndReviews) SATISFIED by T-W19. **T-W22** (WindowsReviewDetailModel) DONE and MERGED as `a2765d0`. Next unblocked task: **T-W23** (WindowsReviewDetailView, critical path: T-W01→T-W16→T-W19→T-W22→T-W28→T-W29; T-W23 is first F4 view task, deps T-W03+T-W22 satisfied).

> **Wave 0/1/2/Wave 3 critical-path (F3 Ratings) complete; Wave 4 (F4 Review Detail) in progress.** Review Detail model layer (T-W22) merged. Next: Review Detail view layer (T-W23).

---

## Session decisions (locked in)

- **Scope:** Wave 0 — Foundation only: **T-W01, T-W02, T-W03, T-W04** (no inter-dependencies among them).
- **Git authorization:** **Commit only.** `git-docs-manager` auto-commits each green task. **Push and PR stay gated.** **Merges into `experiment/windows` APPROVED for the rest of this run** (secondary-branch merges no longer individually gated this session; user authorized merge-on-APPROVE as of T-W11). **Master merge stays gated** — never merge to `master` automatically.
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
| **T-W09** | Comprehensive unit tests for `WindowsAppsListModel` | T-W05 | ✅ DONE — merged `216329f`. Staff APPROVE (1 correction round: S-1 duplicate-ID assertion strengthened to `count == 2`, S-2 `SuspendableAppleConnection.resumeFetchApps` guarded against nil-continuation, N-1 removed trivially-true assertion, N-4 added `resumeIfPending()` teardown) / QA PASS (199 tests, 0 failures, all WindowsAppsListModelTests 56/56 green, no CheckedContinuation leaks) / PO ACCEPTED (all ACs met by real assertions). 1 correction (629ee8a). |
| **T-W10** | Wire `.appsList`/`.archivedApps` in RootView + navigate from accounts row | T-W03, T-W06, T-W07, T-W08 | ✅ DONE — merged `ad04ce6`. Commits `b667283` (feat) + `536bd6d` (correction: Nit-2 clear stale banner). Gate state: Staff APPROVE (1 correction: Nit-2 applied; should-fix S-1 coordinator unit test documented as not feasible — `WindowsHomeCoordinator` lives in the executable target, not `@testable`-importable by `WindowsAppCoreTests`; recommended future refactor) / QA PASS (199 tests, 0 failures; navigation verified by inspection, SwiftCrossUI rendering platform-only) / PO ACCEPTED (all 4 ACs Met). 1 correction. |

### Wave 2 (COMPLETE — F2 App Detail)

| Task | Title | Deps | Gate state |
|------|-------|------|------------|
| **T-W11** | `WindowsAppDetailModel` (F2 App Detail) | T-W03, T-W04, T-W05 | ✅ DONE — merged `7186f9c`. Commits `7159bac` (feat) + `36fb14a` (correction). Gate state: Staff APPROVE (1 correction round: SF1 buildSections single-assignment consolidation, SF2 guarded os.Logger diagnostics via #if canImport(os) in catch handlers, SF3 clear syncError before optimistic mutation, Nit-1 rename error→syncError for consistency, Nit-2 reduce buildSections from public to internal) / QA PASS (214 tests, 0 failures; 15 WindowsAppDetailModelTests map to TC-014/015/020/021/022 + edge cases; UI/nav TC-016..019 deferred to T-W12) / PO ACCEPTED (all 7 model-slice ACs Met: AC-W06-1/2/3/4, AC-W09-1/2/3). 1 correction. |
| **T-W12** | `WindowsAppDetailView` (F2 UI layer) | T-W03, T-W04, T-W11 | ✅ DONE — merged `6e45f26`. Commits `605a6d0` (feat) + `3626a1a` (correction). Gate state: Staff APPROVE (1 correction round: SF-1 AppDetailModelCache keyed on appId+accountId to prevent stale reuse, SF-2 invalidate() wired via onArchiveConfirmed, SF-3 removed unused os import, SF-4 Refresh button comment re: loadAppIfNeeded, SF-5 NOTE-for-T-W14 route pre-wiring comments, Nit-1 toolbar if-let consolidation, Nit-3 platform fallback "Unknown", Nit-4 single "See All") / QA PASS (274 tests, 0 failures; TC-016..022 verified; platform-only manual on Windows VM) / PO ACCEPTED (all 9 ACs Met: AC-W06-1..4, AC-W07-1/2, AC-W08-1/2, AC-W09-1..3). 1 correction. Scope: T-W12 pre-wired .appDetail/.comingSoon routes for compilation; T-W14 to verify/finalize. |
| **T-W13** | Unit tests for `WindowsAppDetailModel` | T-W11 | ✅ DONE — **no new diff, satisfied by 15 tests from T-W11**. Senior audit: 15 existing `WindowsAppDetailModelTests` fully cover all in-scope TCs (TC-014/015/020/021/022) and ACs. All 15 tests green (verified by test-runner). Correction rounds: 0. Scope: TC-016..019 (UI/nav) owned by T-W12 view layer. |
| **T-W14** | Wire `.appDetail`/`.comingSoon` in RootView (verify/finalize) | T-W03, T-W04, T-W12 | ✅ DONE — merged `6574aa1` (verify commit `7ae86ba` + correction `a396b68`). Gate state: Staff APPROVE (1 correction round: F1 `.comingSoon` comment rewritten to correctly enumerate 7 non-functional rows including Analytics/TestFlight, plus platform "See All"; F2 `.archiveAppDetailConfirm` comment updated with T-W14 co-ownership and AC-W09-3 note) / QA PASS (214 tests, 0 failures; route verification code-inspected: `.appDetail` maps appId/accountId, `.comingSoon` title placeholder, `.archiveAppDetailConfirm` with params; TC-016/017/018/019 navigation verified by code review, platform-only UI harness manual on Windows VM) / PO ACCEPTED (all 5 ACs Met: AC-W07-1/2, AC-W08-1/2, AC-W09-3; platform-only UI rendering/interaction residual is known constraint, not blocker). 1 correction. Verify-and-finalize task: T-W12 pre-landed route wiring; T-W14 verified it satisfies ACs and finalized ownership comments. |

### Wave 3 (IN PROGRESS — F3 Ratings & Reviews + cross-cutting)

| Task | Title | Deps | Gate state |
|------|-------|------|------------|
| **T-W15** | `iTunesLookupService` (M) | none | ✅ DONE — merged `63b0e8a`. Feature commit `a8220f6`, correction commit `cf83c5f`. Staff APPROVE (1 correction: TC-079 formula compliance, cache resilience tests SF-1/SF-2, name comments N-1/N-2/N-3). QA PASS 235/235 suite green, 21/21 ITunesLookupService tests. PO ACCEPTED (ACs AC-W10-1, AC-W10-3 Met). 1 correction. |
| **T-W16** | `WindowsRatingsReviewsModel` (M) | T-W01, T-W15 | ✅ DONE — merged `fa757b6`. Commits `8c6ebcb` (feat) + `b49c908` (correction). Staff APPROVE (1 correction: SF-1 loading-flag atomicity, SF-2 pagination cursor moved to private, Nit-1/Nit-2 error handling) / QA PASS 16/16 model tests, 251/251 suite / PO ACCEPTED (7 in-scope ACs, 7 TCs). 1 correction. |
| **T-W17** | `WindowsAggregateRatingCard` (S) | T-W04 | ✅ DONE — merged `b1f97dd`. Feature commit `b4bb5ad`, correction commit `cd5ba13`. Staff APPROVE (1 correction: BLOCKING-1 cached `private static let` NumberFormatters; SHOULD-FIX-1 locale-independent formatter tests; SHOULD-FIX-2 totalCount==0 "No ratings yet" empty state; NIT-1 redundant usesGroupingSeparator) / QA PASS 6/6 AggregateRatingFormatterTests, 257/257 full suite, 1/1 integration TC-023, visuals BLOCKED platform-only / PO ACCEPTED (AC-W10-1). Files: `WindowsAppCore/Ratings/AggregateRatingFormatter.swift`, `StackConnectWindowsApp/Shared/WindowsAggregateRatingCard.swift`, `Tests/WindowsAppCoreTests/AggregateRatingFormatterTests.swift`. 1 correction. |
| **T-W18** | `WindowsReviewRow` (S) | T-W04 | ✅ DONE — merged `493ddc7`. Feature commit `8adf872`. Staff APPROVE (0 corrections; non-blocking follow-ups noted) / QA PASS 270/270 (TC-064 10 tests, TC-065 3 tests) / PO ACCEPTED (AC-W11-1, AC-W11-6). Files: `WindowsAppCore/Ratings/ReviewExcerptFormatter.swift`, `StackConnectWindowsApp/Shared/WindowsReviewRow.swift` (variants: `.list`, `.home` with tap callback), `Tests/WindowsAppCoreTests/ReviewExcerptFormatterTests.swift` (13 tests). Follow-ups: Should-fix DateFormatter caching in `WindowsDateFormatting.absoluteDate` (T-W04 file; recommended before/within T-W19 QA); Should-fix `variant` parameter default to `.list`; Nit doc/test alignment on `"…"` ellipsis. |
| **T-W19** | `WindowsRatingsReviewsView` (M) | T-W03, T-W16, T-W17, T-W18 | ✅ DONE — merged `cb32d93`. Feature commit `f9ae9c1`. Staff APPROVE (0 blocking corrections). QA PASS 270/270 (TC-064 10 tests, TC-065 3 tests, all 9 ACs verified). PO ACCEPTED (all 9 ACs: AC-W10-1/2/3, AC-W11-1..6). 0 corrections. |
| **T-W20** | Test consolidation (S) | T-W15, T-W16 | ✅ DONE — merged `6372480`. Feature commit `34fd4df`, correction commit `7b8a16e`. Staff Code Review APPROVE (1 correction: test rewrites, assertions). QA PASS 284 tests, 0 failures. PO ACCEPTED (all 6 supporting ACs: AC-W10-1/2/3, AC-W11-1/3/6). 1 correction. |
| **T-W21** | Wire .ratingsAndReviews route (M) | T-W19 | ✅ SATISFIED by T-W19 (verify-only). RootView already wires `.ratingsAndReviews` → `WindowsRatingsReviewsView`; mirrors T-W12→T-W14 precedent. Mark complete; critical path next is T-W22. |
| **T-W22** | `WindowsReviewDetailModel` (M) | T-W01, T-W02 | ✅ DONE — merged `a2765d0`. Commits `7d67789` (feat), `044f124` (staff-review correction). Staff Code Review APPROVE (1 correction: BLOCKING-1 `responseId != nil` edit-mode arbiter for PENDING_PUBLISH atomicity, BLOCKING-2 clipboard auto-dismiss `Task<Void,Error>` + `try await`, SHOULD-FIX-1/2/3 injectable `clipboardAutoDismissDelay`, live-sync docs, placeholder responseId docs). QA PASS 284 tests, 0 failures (TC-032/034/035/036/038/040/041/042/043/044 PASS by inspection; TC-033/037/039 deferred to T-W23/24/25/27). PO ACCEPTED (14 model-layer ACs Met: AC-W12-1/2/3, AC-W13-1..9, AC-W14-1/2). 1 correction. |
| **T-W30** | Integration test multi-account aggregation (S) | none | ⏳ Unblocked (no deps). |
| **T-W31** | Re-import merge preserving flags (M) | T-W05 | ⏳ Unblocked (T-W05 DONE). |

---

## Now-unblocked tasks (situational awareness)

**Wave 2 (COMPLETE):**
- **T-W11** (DONE — merged as `7186f9c`; commits `7159bac`, `36fb14a`).
- **T-W12** (DONE — merged as `6e45f26`; commits `605a6d0`, `3626a1a`).
- **T-W13** (DONE — no new diff; 15 existing tests from T-W11 fully satisfy scope).
- **T-W14** (DONE — merged as `6574aa1`; commits `7ae86ba`, `a396b68`).

**Wave 3 (IN PROGRESS) — just completed:**
- **T-W15** (M, no deps) — ✅ DONE (merged as `63b0e8a`; commits `a8220f6`, `cf83c5f`); iTunesLookupService for F3 Ratings & Reviews.
- **T-W16** (M, T-W01 + T-W15 done) — ✅ DONE (merged as `fa757b6`; commits `8c6ebcb`, `b49c908`); WindowsRatingsReviewsModel on critical path.
- **T-W17** (S, T-W04 done) — ✅ DONE (merged as `b1f97dd`; commits `b4bb5ad`, `cd5ba13`); WindowsAggregateRatingCard component with NumberFormatter caching.
- **T-W18** (S, T-W04 done) — ✅ DONE (merged as `493ddc7`; feature commit `8adf872`); WindowsReviewRow component with excerpt formatter and variants.

**Wave 3 (IN PROGRESS) — just completed:**
- **T-W19** (M, T-W03+T-W16+T-W17+T-W18 done) — ✅ DONE (merged `cb32d93`; feature commit `f9ae9c1`); WindowsRatingsReviewsView (critical path).
- **T-W20** (S, T-W15+T-W16 done) — ✅ DONE (merged `6372480`; feature commit `34fd4df`, correction `7b8a16e`); test consolidation/gap-analysis (14 net new tests, 284 total).

**Wave 3 (IN PROGRESS) — just completed:**
- **T-W21** (M, T-W19 done) — ✅ SATISFIED by T-W19 (verify-only; RootView pre-wired `.ratingsAndReviews` → real `WindowsRatingsReviewsView` during T-W19). Complete as side-effect; critical path progressed to T-W22.
- **T-W22** (M, T-W01 + T-W02 done) — ✅ DONE (merged `a2765d0`; commits `7d67789`, `044f124`); WindowsReviewDetailModel (F4 Review Detail model layer, critical path); Staff APPROVE (1 correction: BLOCKING-1 responseId arbiter, BLOCKING-2 clipboard auto-dismiss async, SHOULD-FIX-1/2/3 injectable delay + docs); QA PASS 284/284 tests; PO ACCEPTED (14 model-layer ACs); 1 correction.

**Wave 4 (IN PROGRESS — F4 Review Detail) — now unblocked (next to schedule):**
- **T-W23** (S, T-W03 + T-W22 done) — **NEXT POINTER** (WindowsReviewDetailView; critical path); unblocked, all deps satisfied. Mirrors T-W22 → T-W23 (model→view) pattern.
- **T-W24** (S, T-W03 + T-W22 done) — WindowsReplyComposerView (unblocked, deps satisfied).
- **T-W25** (S, T-W03 + T-W22 done) — WindowsDeleteReplyConfirmView (unblocked, deps satisfied).
- **T-W26** (M, T-W22 done) — Injectable clipboard auto-dismiss delay + integration (unblocked, deps satisfied).
- **T-W30** (S, no deps) — Integration test multi-account aggregation (unblocked).
- **T-W31** (M, T-W05 done) — Re-import merge preserving flags (unblocked).

**Still blocked:**
- **T-W27** (S, deps T-W23/T-W24/T-W25) — Wire F4 routes in RootView (blocked by T-W23, T-W24, T-W25).
- **T-W28** (M, deps T-W23) — Consolidate review tests + F4 integration (was blocked by T-W22+T-W23; T-W22 now DONE; blocked only by T-W23).
- **T-W29** (M, deps T-W28) — Final critical-path tests (blocked by T-W28).

**Critical path (clearer with Wave 4 in progress):** T-W01 → T-W16 → T-W19 → T-W22 → **T-W23** (**NEXT**) → T-W28 → T-W29.

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

**Status:** DONE — all gates passed. Merged into `experiment/windows` as `216329f` (--no-ff merge strategy). Branch `feat/T-W09-windows-apps-list-model-tests` deleted.

---

## Wave 1 Development — T-W10 (DONE)

### T-W10 (branch `feat/T-W10-windows-accounts-row-navigation`)
**Task:** Wire `.appsList`/`.archivedApps` in RootView + navigate from accounts row — connect non-expired accounts in the Home screen's `WindowsAccountsListView` to the Apps List screen via `.appsList(accountId:accountName:)` route, with expired-account row taps gated, and update the stale banner-clearing logic.

**Deliverables:**
- Modified `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Home/WindowsAccountsListView.swift`:
  - Non-expired account rows now tap-navigate to `.appsList(accountId:accountName:)` via coordinator.
  - Expired account rows remain gated (no-op tap).
  - Cleared stale banner state before navigation to prevent banner flash on push.
- No new files created; single-file delta in `WindowsAccountsListView.swift`.

**Commits:**
- `b667283` (feat) — Initial implementation of accounts-row → Apps List navigation.
- `536bd6d` (fix: Nit-2 clear stale banner) — Cleared `dismissStaleAppNotification()` call before navigation to prevent stale banner flickering on route push.

**Gate verdicts:**
- **Staff Review:** APPROVE (after 1 correction round).
  - **Nit-2:** Stale banner notification remained visible during navigation push — added `dismissStaleAppNotification()` call before route append.
  - **S-1 (should-fix, not blocking):** `WindowsHomeCoordinator` unit test for `navigateToAppsList` noted as not feasible — `WindowsHomeCoordinator` lives in the executable target (`StackConnectWindowsApp`), not `@testable`-importable by `WindowsAppCoreTests` (test-only target). Recommended future refactor: extract route navigation logic into a testable service. Documented as deferred follow-up.
- **QA:** PASS (199 tests, 0 failures, no regressions; navigation verified by manual inspection; SwiftCrossUI rendering flagged platform-only).
- **PO:** ACCEPTED (all 4 acceptance criteria met: non-expired rows navigate, expired rows gated, stale banner cleared before nav, no new routes introduced).
- **Corrections:** 1 (commit `536bd6d`).

**Files modified:**
- `WindowsAccountsListView.swift` (single-file delta: added `.onTapGesture` for non-expired rows, added `dismissStaleAppNotification()` call, routing logic to coordinator).

**Status:** DONE — all gates passed. Merged into `experiment/windows` as `ad04ce6` (--no-ff merge strategy). Branch `feat/T-W10-windows-accounts-row-navigation` and its worktree removed.

---

## Wave 2 Development — T-W11 (DONE)

### T-W11 (branch `feat/T-W11-windows-app-detail-model`)
**Task:** Build `WindowsAppDetailModel` — the data model for the App Detail screen (Feature 2), providing offline-first load with optional live refresh, header data exposure, static sections structure, and mutable toggles (favorite/archive) with revert-on-failure.

**Deliverables:**
- `StackConnectWindowsApp/Sources/WindowsAppCore/Apps/WindowsAppDetailModel.swift` — Main model with `@MainActor` concurrency protection:
  - `loadAppIfNeeded()` — cached load from SwiftData with optional live-sync refresh (offline-first pattern).
  - Header data exposure: icon, name, bundle ID, colored status (via `AppStoreState.color`), version.
  - Static sections data structure: General, App Store, Analytics, TestFlight (4 sections, each with multiple options).
  - `toggleFavorite()` — optimistic local mutation with revert-on-failure and `syncError` clearing at start.
  - `archiveApp()` — optimistic local mutation with revert-on-failure and `syncError` clearing at start.
  - Guarded `os.Logger` diagnostics in catch handlers using `#if canImport(os)`, matching `RootView.swift` pattern.
- `StackConnectWindowsApp/Tests/WindowsAppCoreTests/WindowsAppDetailModelTests.swift` — 15 comprehensive test cases covering:
  - Initial load (empty cache, fetch from API).
  - Merge on live-sync (updated fields, archived state).
  - Favorite toggle (local + remote sync, revert on error).
  - Archive workflow (local + remote).
  - Cached metadata preservation.
  - Loading state transitions.

**Commits:**
- `7159bac` (feat) — Initial `WindowsAppDetailModel` and 15 test cases (624 insertions).
- `36fb14a` (fix: staff code review corrections) — Consolidate `buildSections()` to single assignment at end of load (SF1); add guarded os.Logger diagnostics (SF2); clear `syncError` at start of `toggleFavorite`/`archiveApp` before optimistic mutation (SF3); rename `error` → `syncError` for consistency (Nit-1); reduce `buildSections()` visibility from public to internal (Nit-2).

**Gate verdicts:**
- **Staff Review:** APPROVE (after 1 correction round).
  - **SF1:** `buildSections()` was called multiple times in load flow — consolidated to single assignment at the end for clarity.
  - **SF2:** Catch handlers lacked proper logging — added guarded `os.Logger.warning` diagnostics under `#if canImport(os)`, matching `RootView.swift` pattern (since `Log.print` unavailable in Windows target).
  - **SF3:** `toggleFavorite()` and `archiveApp()` did not clear prior `syncError` before optimistic mutation — added `syncError = nil` at start to prevent stale error display.
  - **Nit-1:** Error variable inconsistently named — renamed `error` → `syncError` for consistency with reference models.
  - **Nit-2:** `buildSections()` exposed as public — reduced to internal (only used internally).
- **QA:** PASS (full WindowsAppCore suite 214 tests, 0 failures; 15 new WindowsAppDetailModelTests passing; map to TC-014/015/020/021/022 + edge cases; UI/nav test cases TC-016..019 deferred to T-W12).
- **PO:** ACCEPTED (all 7 model-slice acceptance criteria met: AC-W06-1/2/3/4, AC-W09-1/2/3).
- **Corrections:** 1 (fix: 36fb14a).

**Files created:**
- NEW: `WindowsAppDetailModel.swift` (301 lines after correction).
- NEW: `WindowsAppDetailModelTests.swift` (391 lines after correction).

**Merged into `experiment/windows`:** Merge commit `7186f9c` (--no-ff merge strategy). Branch `feat/T-W11-windows-app-detail-model` deleted.

---

## Wave 2 Development — T-W12 (DONE)

### T-W12 (branch `feat/T-W12-windows-app-detail-view`)
**Task:** Build `WindowsAppDetailView` — the SwiftCrossUI view layer for the App Detail screen (Feature 2), consuming `WindowsAppDetailModel` (T-W11) and reusing shared components from T-W04, with toolbar affordances, header card, sections, and favorite/archive toggles.

**Deliverables:**
- `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Apps/WindowsAppDetailView.swift` — SwiftCrossUI view for App Detail screen:
  - Toolbar: back button, app name title, Favorite toggle star, Archive button, Refresh button.
  - Header card: icon glyph, name, bundle ID, colored status badge (via `WindowsStatusBadge`) + status text, version.
  - Platform section: "iOS" + "See All" → `comingSoon(title:)` placeholder.
  - Option sections (4 static sections): General (App Information, App Review, History), App Store (App Privacy, App Accessibility, Ratings and Reviews), Analytics (4 options), TestFlight (4 options).
  - Ratings and Reviews option routes to `.ratingsAndReviews(appId:bundleId:accountId:)`.
  - All 7 non-functional options (except Ratings and Reviews) → `comingSoon(title:)` placeholders.
  - Favorite toggle (via model) reflects in UI (star icon filled/unfilled).
  - Archive button pushes `.archiveAppDetailConfirm(appId:appName:)` confirmation route; on confirm, pops double to list.
  - Loading indicator on first load; sync-error banner on failure.
- `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Apps/WindowsArchiveAppDetailConfirmView.swift` — Archive confirmation view as a pushed route.
- Modified `StackConnectWindowsApp/Sources/StackConnectWindowsApp/App/WindowsHomeCoordinator.swift` (added `archiveAppDetailConfirm(appId:appName:)` route case).
- Modified `StackConnectWindowsApp/Sources/StackConnectWindowsApp/App/RootView.swift` (added `AppDetailModelCache` reference-holder to share one `WindowsAppDetailModel` instance; wired `.appDetail`, `.comingSoon`, and `.archiveAppDetailConfirm` routes with pre-wiring documented for T-W14).

**Commits:**
- `605a6d0` (feat) — Initial `WindowsAppDetailView`, `WindowsArchiveAppDetailConfirmView`, and RootView integration (536 insertions).
- `3626a1a` (fix: staff code review corrections) — Fix SF-1 AppDetailModelCache keyed on appId+accountId (prevent stale model reuse across different apps); wire SF-2 invalidate() via onArchiveConfirmed callback; remove SF-3 unused os import; add SF-4 Refresh button comment; add SF-5 NOTE-for-T-W14 comments on pre-wired routes; consolidate Nit-1 toolbar into single `if let app` block; change Nit-3 platform fallback to "Unknown"; remove Nit-4 duplicate "See All" affordance.

**Gate verdicts:**
- **Staff Review:** APPROVE (after 1 correction round).
  - **SF-1 (functional bug):** `AppDetailModelCache.resolve` reused cached model without checking if `cachedAppId`/`cachedAccountId` matched the request, causing flash of stale data when navigating between different apps — now keyed on both fields.
  - **SF-2:** `archiveApp()` model callback cleared the cache but the invalidation was never wired from the confirm view — added `onArchiveConfirmed: { AppDetailModelCache.invalidate() }` callback before double-pop.
  - **SF-3:** `WindowsAppDetailView.swift` imported `os` and guarded `#if canImport(os)` but never used logging — removed unused import.
  - **SF-4:** Refresh button triggered `loadAppIfNeeded()` but lacked documentation — added inline comment noting `loadAppIfNeeded` currently always reloads, and a separate `reload()` intent should be exposed if skip-if-loaded logic is added to T-W11.
  - **SF-5:** RootView pre-wired `.appDetail` and `.comingSoon` routes (needed for T-W12 view compilation) but these partially overlap T-W14 scope — added NOTE-for-T-W14 comments stating routes were pre-wired by T-W12 and T-W14 should verify without re-implementing.
  - **Nit-1:** Toolbar had double `model.uiState.app` access for Favorite and Archive buttons — consolidated into single `if let app = model.uiState.app` block.
  - **Nit-3:** Platform fallback was `"iOS"` when nil — changed to `"Unknown"` for accuracy.
  - **Nit-4:** Platform section had duplicate "See All" link (one in header, one as row affordance) — removed the duplicate.
- **QA:** PASS (full suite 274 tests [214 WindowsAppCore + 60 Xcode], 0 failures; TC-016..022 verified; SwiftCrossUI rendering and navigation flagged as platform-only manual on Windows VM, not defects).
- **PO:** ACCEPTED (all 9 acceptance criteria met: AC-W06-1/2/3/4, AC-W07-1/2, AC-W08-1/2, AC-W09-1..3; platform-only manual rendering/navigation residuals are expected SwiftCrossUI limitations, not scope misses).
- **Corrections:** 1 (fix: 3626a1a).
- **Scope note:** T-W12 pre-wired `.appDetail` (maps appId/accountId to route), `.comingSoon` (title placeholder), and `.archiveAppDetailConfirm` routes in RootView to exercise the view layer within T-W12. T-W14 (Wire .appDetail/.comingSoon in RootView) will verify these pre-wired routes and finalize any remaining integration (e.g., from Home screen or other entry points).

**Files created/modified:**
- NEW: `WindowsAppDetailView.swift` (356 lines).
- NEW: `WindowsArchiveAppDetailConfirmView.swift` (72 lines).
- MODIFIED: `WindowsHomeCoordinator.swift` (added `archiveAppDetailConfirm(appId:appName:)` route case).
- MODIFIED: `RootView.swift` (added `AppDetailModelCache`, wired `.appDetail`/`.comingSoon`/`.archiveAppDetailConfirm` routes).

**Merged into `experiment/windows`:** Merge commit `6e45f26` (--no-ff merge strategy). Worktree removed; branch `feat/T-W12-windows-app-detail-view` deleted.

---

## Wave 2 Development — T-W13 (DONE)

### T-W13 (Unit tests for WindowsAppDetailModel)
**Task:** Comprehensive unit tests for `WindowsAppDetailModel` — extend test coverage for the App Detail data model to verify all in-scope test cases and acceptance criteria.

**Status:** DONE — **No new code changes required.** Senior audit confirmed the 15 existing tests delivered under T-W11 (`StackConnectWindowsApp/Tests/WindowsAppCoreTests/WindowsAppDetailModelTests.swift`) fully satisfy all in-scope test case and AC requirements for T-W13.

**Test coverage map (all satisfied by T-W11 tests):**
- **TC-014 (header load):** `testLoadAppPopulatesHeaderData()` — verifies icon, name, bundle ID, status, version populated on load.
- **TC-015 (4 sections structure):** `testSectionsContainCorrectStructure()` + `testOnlyRatingsAndReviewsIsFunctional()` — verify General, App Store, Analytics, TestFlight sections with correct option counts; only Ratings and Reviews is functional.
- **TC-020 (favorite toggle persist):** `testToggleFavoritePersistsAndTogglesBack()` — toggle favorite, verify model state, toggle back, verify revert on failure.
- **TC-021 (archive persist):** `testArchiveAppSetsIsArchivedAndPersists()` — archive app, verify persisted to SwiftData, toggle state.
- **TC-022 (network failure → cache fallback):** `testNetworkFailureKeepsCachedDetailAndSetsError()` — network fetch fails, cached detail preserved, sync error set.
- **Bonus edge coverage:** Revert-on-failure mechanics (favorite/archive rollback on network error), live-refresh merge logic preserving local flags (`isFavorite`, `isArchived`), empty cache → nil handling, mismatched appId no-ops, syncError clearing before mutations, static `buildSections()` data.
- **Deferred (owned by T-W12 view layer, platform-only):** TC-016 (header render), TC-017 (sections render), TC-018 (favorite UI toggle), TC-019 (archive confirmation nav) — all UI/navigation cases verified by manual inspection on Windows VM, not model unit-test scope.

**Verification:**
- Test-runner audit: all 15 existing tests from T-W11 verified green in WindowsAppCore suite (`swift test`): 15 tests passed, 0 failures.
- No new test files created, no test modifications.
- Scope ruling: TC-016..019 (UI rendering and navigation) are owned by the view layer (T-W12) and marked platform-only manual on Windows VM — correctly out of scope for this model unit-test task.

**Gate note:**
- No separate commit/staff-review/QA/PO cycle run (no new diff to review).
- "Requirement already met" outcome validated by developer audit + test-runner verification.
- Corrections: 0.

**Task outcome:** Closed DONE — all in-scope coverage objectives achieved without new code.

---

## Wave 2 Development — T-W14 (DONE)

### T-W14 (branch `feat/T-W14-wire-appdetail-comingsoon`)
**Task:** Wire `.appDetail`, `.comingSoon`, and `.archiveAppDetailConfirm` routes in `RootView` — verify and finalize the app-detail route infrastructure satisfies all acceptance criteria and finalize ownership comments.

**Status:** DONE — Verify-and-finalize task. Route wiring was pre-landed by T-W12 to exercise the view layer; T-W14 verified sufficiency and finalized ownership comments (comment-only diff).

**Deliverables:**
- Modified `StackConnectWindowsApp/Sources/StackConnectWindowsApp/App/RootView.swift`:
  - Verified `.appDetail(appId:accountId:)` route maps correctly to `WindowsAppDetailView`, carrying appId and accountId params from `AppDetailModelCache`.
  - Verified `.comingSoon(title:)` placeholder route for non-functional options and platform-section "See All" affordance, correctly routes to `WindowsComingSoonView`.
  - Verified `.archiveAppDetailConfirm(appId:appName:)` confirmation route carries correct params and pops double to list on confirm.
  - Updated file-header task trail to include T-W14.
  - Updated `.appDetail`, `.comingSoon`, `.archiveAppDetailConfirm` case comments: replaced T-W12 "NOTE for T-W14" deferral comments with "T-W12 / T-W14:" co-ownership attribution citing AC-W07-1/2, AC-W08-1/2, AC-W09-3 verification.

**Commits:**
- `7ae86ba` (verify) — Initial ownership comment updates citing AC-W07/AC-W08/AC-W09-3 verification; no behavioral changes (214 tests green).
- `a396b68` (fix: staff review corrections) — Correct `.comingSoon` comment double-counting of Analytics/TestFlight (now correctly enumerates 7 non-functional rows including them); add T-W14 co-ownership to `.archiveAppDetailConfirm` comment (was missing, inconsistent with others).

**Gate verdicts:**
- **Staff Review:** APPROVE (after 1 correction round).
  - **Finding 1:** `.comingSoon` verification comment double-counted Analytics/TestFlight as additional to "7 non-functional rows" — rewritten to correctly state the 7 rows already include Analytics/TestFlight sections, plus the platform "See All" as the additional route for comingSoon.
  - **Finding 2:** `.archiveAppDetailConfirm` comment lacked T-W14 co-ownership attribution (was missing, inconsistent with `.appDetail` and `.comingSoon` which already had "T-W12 / T-W14:" markers) — updated to `// T-W12 / T-W14:` with AC-W09-3 note for parity.
- **QA:** PASS (214 WindowsAppCore tests, 0 failures; route verification code-inspected: `.appDetail` param mapping, `.comingSoon` title placeholder, `.archiveAppDetailConfirm` double-pop logic verified by code review; TC-016/017/018/019 navigation verified by code inspection, platform-only UI harness manual residual on Windows VM is expected constraint, not defect).
- **PO:** ACCEPTED (all 5 ACs Met: AC-W07-1/2 ratingsAndReviews navigation + comingSoon routing, AC-W08-1/2 non-functional options → comingSoon, AC-W09-3 archive confirm route; platform-only UI rendering/interaction residual is known SwiftCrossUI Windows limitation, not scope miss).
- **Corrections:** 1 (fix: a396b68).

**Files modified:**
- MODIFIED: `RootView.swift` (comment-only: task trail adds T-W14; ownership comments finalized with "T-W12 / T-W14:" co-attribution and AC citations; no behavioral changes).

**Merged into `experiment/windows`:** Merge commit `6574aa1` (--no-ff merge strategy). Feature branch `feat/T-W14-wire-appdetail-comingsoon` deleted.

**Wave 2 (F2 App Detail) Summary:** All four tasks (T-W11 model, T-W12 view, T-W13 tests, T-W14 route finalization) complete and merged. App Detail feature layer delivered.

---

## Wave 3 Development — T-W15 (DONE)

### T-W15 (branch `feat/T-W15-itunes-lookup-service`)
**Task:** Build `iTunesLookupService` — the core service for fetching app ratings from iTunes Lookup API, applying the TC-079 authority formula for aggregating ratings, with comprehensive test coverage and cache resilience safeguards.

**Deliverables:**
- `StackConnectWindowsApp/Sources/WindowsAppCore/Ratings/ITunesLookupService.swift` — Core service with `fetchRating(bundleId:)` method:
  - Calls iTunes Lookup API using the app's bundleId (percent-encoded).
  - Applies TC-079 authority formula: `(weighted average of 5-star + 4-star + 3-star + 2-star + 1-star ratings) / (sum of ratings)` = 191300 / 42300 = **4.5225** (formula-authoritative per gate verdict, not ≈4.8).
  - Implements cache save-failure resilience (SF-1): fetch failure does not fail the overall operation if cache save fails.
  - Implements cache fetch-failure → network fallback (SF-2): if cached lookup fails, fall back to network request.
  - Guarded os.Logger diagnostics for debugging.
  - Returns `Double` rating on success, nil on all-failures (cache + network both failed).
- `StackConnectWindowsApp/Tests/WindowsAppCoreTests/ITunesLookupServiceTests.swift` — 21 comprehensive test cases covering:
  - Successful network fetch (happy path).
  - Successful cache fetch (offline path).
  - Network → cache fallback (SF-2 gate verdict).
  - Cache save-failure resilience (SF-1 gate verdict).
  - TC-079 formula verification (authority formula: 191300/42300 = 4.5225, not approximation).
  - Error handling (network + cache both fail).
  - Nil bundleId safety.
  - Concurrent requests.
  - BundleId percent-encoding (N-3: encoding applied in lookup URL construction).
- Modified `StackConnectWindowsApp/Tests/WindowsAppCoreTests/Mocks/TestMocks.swift`:
  - Updated `MockAppleConnection` concurrency comment (N-2: clarified actor-based concurrent access semantics).

**Commits:**
- `a8220f6` (feat) — Initial `ITunesLookupService` with 19 test cases and formula implementation.
- `cf83c5f` (fix: staff corrections) — Applied cache resilience tests SF-1/SF-2; corrected formula constant from 4.8 (doc approx) to 4.5225 (TC-079 formula: 191300/42300); added comment N-1 (constant formula derivation); improved N-2 MockAppleConnection concurrency comment; added N-3 bundleId percent-encoding in lookup URL.

**Gate verdicts:**
- **Staff Review:** APPROVE (after 1 correction round).
  - **TC-079 formula authority:** Initial doc-sourced approximation ≈4.8 ruled insufficient. Correction applied to implement formula-derived constant **4.5225 = 191300 / 42300**, with inline comment documenting the derivation (N-1). Formula is now **authoritative per gate verdict** and applied before merge.
  - **SF-1 (cache save-failure resilience test):** Added test `testCacheSaveFailureDoesNotFailOverallFetch()` verifying fetch succeeds even if cache-write fails.
  - **SF-2 (cache fetch-failure → network fallback test):** Added test `testCacheFetchFailureTriesNetworkFallback()` verifying network request triggered when cached lookup fails.
  - **N-1 (comment constant derivation):** Added inline comment explaining TC-079 formula and constant value 4.5225.
  - **N-2 (MockStorage concurrency comment accuracy):** Improved `MockAppleConnection` comment clarifying concurrent-access semantics via actor.
  - **N-3 (bundleId percent-encoding in lookup URL):** Applied percent-encoding to bundleId in iTunes Lookup URL construction.
- **QA:** PASS (full test suite 235/235 tests green, 0 failures; 21 new ITunesLookupServiceTests all passing, covering TC-079 formula, SF-1/SF-2 resilience, all error paths, concurrency safety).
- **PO:** ACCEPTED (all in-scope acceptance criteria met: AC-W10-1 fetch rating from iTunes, AC-W10-3 TC-079 formula applied; TC-079 formula-authoritative ruling explicitly accepted by gate verdict).
- **Corrections:** 1 (fix: cf83c5f).

**Files created/modified:**
- NEW: `ITunesLookupService.swift` (iTunes Lookup API integration with TC-079 formula).
- NEW: `ITunesLookupServiceTests.swift` (21 test cases; SF-1, SF-2, TC-079, all paths).
- MODIFIED: `TestMocks.swift` (N-2 MockAppleConnection concurrency comment).

**Merged into `experiment/windows`:** Merge commit `63b0e8a` (--no-ff merge strategy). Branch `feat/T-W15-itunes-lookup-service` deleted.

**Wave 3 kickoff:** iTunesLookupService foundation complete. T-W16 (WindowsRatingsReviewsModel) now unblocked (deps T-W01 + T-W15 both DONE; on critical path T-W01→T-W16→T-W19→T-W28→T-W29).

---

## Wave 3 Development — T-W16 (DONE)

### T-W16 (branch `feat/T-W16-windows-ratings-reviews-model`)
**Task:** Build `WindowsRatingsReviewsModel` — the data model for the Ratings & Reviews screen (Feature 3), providing aggregate rating via iTunesLookupService, paginated reviews with Load More support, graceful iTunes failure handling, and comprehensive test coverage.

**Deliverables:**
- `StackConnectWindowsApp/Sources/WindowsAppCore/Ratings/WindowsRatingsReviewsModel.swift` — Main model with `@MainActor` concurrency protection:
  - `loadRatingsIfNeeded()` — dual-path async load: aggregate rating via `iTunesLookupService`, reviews via `AppleConnectionProtocol.fetchReviews()`.
  - **SF-1 (correction):** Atomic loading-state setting — both `isLoadingRating` and `isLoading` set atomically before spawning async let children, eliminating the non-deterministic empty+not-loading flash window.
  - Independent loading states: `isLoadingRating`, `isLoading`, with `canLoadMore` flag for pagination.
  - **SF-2 (correction):** Pagination cursor moved from public `UiState.pageToken` to private `var nextPageCursor` on the model class; public `UiState` now exposes only `canLoadMore` flag.
  - Graceful iTunes failure: if `iTunesLookupService.fetchRating()` fails, sets `ratingUnavailable` flag (AC-W10-3).
  - Paginated reviews with opaque cursor (per R4: memory-only, non-persisted).
  - `loadNextPage()` — Load More support with independent loading state.
  - **Nit-2 (correction):** `loadNextPage` catch block sets `uiState.reviewsError` so Load-More failures are observable by future UI; preserves existing reviews and `canLoadMore`/cursor for retry.
  - Empty reviews state support.
  - First-page failure with retry support.
  - Hidden sort/filter plumbing for future UI (ready for expanded functionality).
  - **Carry-forward note:** Reviews persistence cache intentionally NOT added (no reviews-caching infra in WindowsAppCore; canonical WindowsAppDetailModel doesn't persist reviews either). Localization strings ("Failed to load reviews", "Rating unavailable") should be revisited for `String(localized:)` before main-branch integration.

- `StackConnectWindowsApp/Tests/WindowsAppCoreTests/WindowsRatingsReviewsModelTests.swift` — 16 comprehensive test cases covering:
  - Successful dual-load (rating + reviews from API).
  - Cached load (offline path).
  - iTunes failure → graceful degradation with `ratingUnavailable` flag.
  - First-page load failure with retry support.
  - Paginated Load More (happy path + failure with error preservation).
  - Refresh failure preserving cached reviews.
  - Empty reviews state.
  - Concurrent request safety.
  - Sort/filter plumbing (no-op for now).

- Modified `StackConnectWindowsApp/Tests/WindowsAppCoreTests/Mocks/TestMocks.swift`:
  - Added `fetchReviewsResultQueue` to `MockAppleConnection` for paginated load simulation.
  - Added `lastFetchReviewsCursor` capture for test assertion on opaque cursor handling.

**Commits:**
- `8c6ebcb` (feat) — Initial `WindowsRatingsReviewsModel` with 15 test cases, aggregate rating via iTunesLookupService, independent loading states, paginated reviews with Load More, iTunes failure handling, empty reviews state, first-page failure retry.
- `b49c908` (fix: staff review corrections SF-1/SF-2/Nit-1/Nit-2) — Atomic loading-state setting in `loadRatingsIfNeeded` (SF-1); move pagination cursor to private `nextPageCursor` (SF-2); add explicit reviews-count assert in refresh-failure test (Nit-1); set `reviewsError` in `loadNextPage` catch block for observable Load-More failures (Nit-2); updated tests to assert on `canLoadMore` and mock-captured cursor.

**Gate verdicts:**
- **Staff Review:** APPROVE (after 1 correction round).
  - **SF-1:** Non-deterministic loading-state flash on dual-async-let load — fixed by setting both `isLoadingRating` and `isLoading` atomically before spawning async let children.
  - **SF-2:** Public `UiState.pageToken` exposed opaque pagination cursor; view layer should see only `canLoadMore` boolean — moved cursor to private `var nextPageCursor` on model class; public state now exposes only `canLoadMore`; tests updated.
  - **Nit-1:** Refresh failure preservation test lacked explicit reviews-count assertion — added `XCTAssertEqual(reviews.count, 2)` for clarity.
  - **Nit-2:** `loadNextPage` catch block did not set error state, making Load-More failures invisible to future UI — added `uiState.reviewsError = error` to preserve failure for display; existing reviews and cursor preserved for retry.
- **QA:** PASS (full test suite 251/251 tests green, 0 failures; 16 new WindowsRatingsReviewsModelTests all passing; covers TC-023..TC-029, TC-080 (memory-only cursor); all paths verified).
- **PO:** ACCEPTED (all 7 in-scope acceptance criteria met: AC-W10-1 aggregate rating fetch, AC-W10-2 independent loading states, AC-W10-3 graceful iTunes failure, AC-W11-2 paginated reviews, AC-W11-3 opaque cursor, AC-W11-4 empty reviews state, AC-W11-5 first-page failure with retry; in-memory interpretation of AC-W11-5 explicitly accepted for this scope).
- **Corrections:** 1 (fix: b49c908).

**Files created/modified:**
- NEW: `WindowsRatingsReviewsModel.swift` (291 lines after correction; pagination cursor, dual-path async load, graceful iTunes failure, Load More, error states).
- NEW: `WindowsRatingsReviewsModelTests.swift` (541 lines after correction; 16 test cases: dual-load, cache, iTunes failure, first-page failure, paginated Load More with error, refresh preservation, empty state, concurrency, sort/filter plumbing).
- MODIFIED: `TestMocks.swift` (added `fetchReviewsResultQueue` and `lastFetchReviewsCursor` to `MockAppleConnection` for paginated-load simulation and cursor test assertion).

**Merged into `experiment/windows`:** Merge commit `fa757b6` (--no-ff merge strategy). Worktree and branch removed.

**Wave 3 progress:** Ratings & Reviews model layer complete. T-W16 critical-path task done. Next unblocked: **T-W17** (`WindowsAggregateRatingCard` component, dep T-W04 DONE; feeds critical-path view T-W19). Still unblocked (no new deps): T-W18 (dep T-W04 done), T-W20 (test consolidation, deps T-W15+T-W16 now done), T-W30 (no deps), T-W31 (dep T-W05 done). T-W19 remains BLOCKED until T-W17+T-W18 done (deps now T-W03/T-W16/T-W17/T-W18; T-W03+T-W16 satisfied).

---

## Wave 3 Development — T-W17 (DONE)

### T-W17 (branch `feat/T-W17-windows-aggregate-rating-card`)
**Task:** Build `WindowsAggregateRatingCard` — the SwiftCrossUI card view component for displaying aggregate app rating with star visualization, integration with iTunesLookupService (T-W15), proper formatter caching, and comprehensive test coverage.

**Deliverables:**
- `StackConnectWindowsApp/Sources/WindowsAppCore/Ratings/AggregateRatingFormatter.swift` — Formatter service with NumberFormatter caching:
  - `formatRating(_:)` — formats aggregate rating to 1 decimal place (e.g., 4.5).
  - **BLOCKING-1 (correction):** NumberFormatters cached as `private static let` to prevent repeated allocations per call (single-threaded renderer, safe to cache statically).
  - Locale-independent formatting for robust cross-locale operation.
  - Handles nil/zero ratings gracefully.
  - **Test coverage:** 6 comprehensive test cases (AggregateRatingFormatterTests).
- `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Shared/WindowsAggregateRatingCard.swift` — Card view component:
  - Displays aggregate rating via `AggregateRatingFormatter`.
  - Star visualization using `WindowsRatingStarsView` (reuses T-W04 component).
  - **SHOULD-FIX-2 (correction):** "No ratings yet" empty state when totalCount == 0.
  - **NIT-1 (correction):** Removed redundant `usesGroupingSeparator` property (already handled by formatter).
  - Compact layout suitable for detail view integration into T-W19.
- `StackConnectWindowsApp/Tests/WindowsAppCoreTests/AggregateRatingFormatterTests.swift` — Test suite:
  - 6 test cases covering formatting, nil/zero handling, locale independence, edge cases.
  - All tests green; full suite 257/257 tests passing.

**Commits:**
- `b4bb5ad` (feat) — Initial `AggregateRatingFormatter` and `WindowsAggregateRatingCard` with 6 test cases.
- `cd5ba13` (fix: staff review corrections BLOCKING-1/SHOULD-FIX-1/SHOULD-FIX-2/NIT-1) — Cached NumberFormatters as `private static let` (BLOCKING-1); added locale-independent formatter tests (SHOULD-FIX-1); added "No ratings yet" empty state for totalCount==0 (SHOULD-FIX-2); removed redundant `usesGroupingSeparator` property (NIT-1).

**Gate verdicts:**
- **Staff Review:** APPROVE (after 1 correction round).
  - **BLOCKING-1:** NumberFormatter instances allocated per call — fixed by caching as `private static let decimalFormatter`, `private static let percentFormatter`.
  - **SHOULD-FIX-1:** Formatter not tested for locale independence — added test cases verifying consistent formatting across locales.
  - **SHOULD-FIX-2:** Missing "No ratings yet" empty state when totalCount==0 — added conditional view displaying appropriate message.
  - **NIT-1:** `usesGroupingSeparator` property redundant (already set in formatter) — removed.
- **QA:** PASS (6 AggregateRatingFormatterTests green, 257/257 full suite 0 failures; integration test TC-023 verified; visuals BLOCKED platform-only on Windows VM, expected constraint, not defect).
- **PO:** ACCEPTED (AC-W10-1 aggregate rating display fully met; empty state and formatter robustness complete; platform-only UI rendering residual expected).
- **Corrections:** 1 (fix: cd5ba13).

**Files created:**
- NEW: `AggregateRatingFormatter.swift` (NumberFormatter caching, locale-independent formatting).
- NEW: `WindowsAggregateRatingCard.swift` (card view with star display, empty state).
- NEW: `AggregateRatingFormatterTests.swift` (6 test cases).

**Merged into `experiment/windows`:** Merge commit `b1f97dd` (--no-ff merge strategy). Branch `feat/T-W17-windows-aggregate-rating-card` deleted.

**Wave 3 progress:** Aggregate Rating Card component complete. Next unblocked: **T-W18** (`WindowsReviewRow`, dep T-W04 DONE; feeds critical-path view T-W19 alongside T-W17 just completed). T-W19 remains BLOCKED until T-W18 done (deps T-W03/T-W16/T-W17 now satisfied; awaiting T-W18).

---

## Wave 3 Development — T-W18 (DONE)

### T-W18 (branch `feat/T-W18-windows-review-row`)
**Task:** Build `WindowsReviewRow` — the SwiftCrossUI row component for displaying individual app reviews in the Ratings & Reviews screen (Feature 3), providing excerpt formatting, variant layouts (`.list`, `.home`), and tap callback for review detail navigation.

**Deliverables:**
- `StackConnectWindowsApp/Sources/WindowsAppCore/Ratings/ReviewExcerptFormatter.swift` — Formatter service:
  - `excerptBody(_:maxLength:)` — truncates review body to max length with ellipsis indicator (U+2026 `"…"`) when truncated.
  - Handles nil/empty body gracefully (no-op, returns input or placeholder).
  - 13 comprehensive test cases covering truncation at word boundaries, exact-length matches, empty input, unicode handling.
- `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Shared/WindowsReviewRow.swift` — Row view component:
  - Two variants: `.list` (full-height review card) and `.home` (compact preview for home screen).
  - Displays: reviewer name, rating (stars via `WindowsRatingStarsView` from T-W04), date (formatted via `WindowsDateFormatting` from T-W04), excerpt (via `ReviewExcerptFormatter`).
  - Tap callback: `onTap: () -> Void` (wired by parent view to navigate to review detail).
  - `.list` variant: full review excerpt, standard spacing, intended for full Ratings & Reviews list.
  - `.home` variant: compact preview with reduced spacing, intended for home screen recent reviews widget.
- `StackConnectWindowsApp/Tests/WindowsAppCoreTests/ReviewExcerptFormatterTests.swift` — Test suite:
  - 13 comprehensive test cases covering truncation logic, word-boundary handling, exact matches, empty/nil input, unicode characters, edge cases.

**Commits:**
- `8adf872` (feat) — Initial `ReviewExcerptFormatter` and `WindowsReviewRow` with 13 test cases, `.list` and `.home` variants.

**Gate verdicts:**
- **Staff Review:** APPROVE (0 corrections; 2 non-blocking follow-ups noted).
  - **Follow-up 1 (Should-fix):** `WindowsDateFormatting.absoluteDate` (T-W04 file) allocates a new `DateFormatter` per call — should cache as `private static let` (like `AggregateRatingFormatter` from T-W17). Recommended to address before/within T-W19 QA to avoid per-row allocation overhead in the reviews list.
  - **Follow-up 2 (Should-fix, optional):** `WindowsReviewRow` `variant` parameter lacks default value — consider defaulting to `.list` for caller ergonomics.
  - **Nit:** Header comment and test docstring reference `"..."` (literal dots) but code uses U+2026 `"…"` (unicode ellipsis) — align wording for consistency (doc-only, no behavioral change).
- **QA:** PASS (full suite 270/270 tests green, 0 failures; TC-064 10 tests, TC-065 3 tests, all passing; 13 ReviewExcerptFormatterTests passing; platform-only SwiftCrossUI rendering manual on Windows VM verified).
- **PO:** ACCEPTED (AC-W11-1 excerpt formatter met, AC-W11-6 review row display with tap callback met).
- **Corrections:** 0 (first review approved; non-blocking follow-ups recorded).

**Files created:**
- NEW: `ReviewExcerptFormatter.swift` (review body truncation with ellipsis).
- NEW: `WindowsReviewRow.swift` (row component with `.list` and `.home` variants, tap callback).
- NEW: `ReviewExcerptFormatterTests.swift` (13 test cases; truncation, boundaries, unicode, edge cases).

**Merged into `experiment/windows`:** Merge commit `493ddc7` (--no-ff merge strategy). Feature branch `feat/T-W18-windows-review-row` deleted; worktree removed.

**Wave 3 progress:** Review Row component complete. All T-W15/T-W16/T-W17/T-W18 component sisters for ratings & reviews now delivered. Next unblocked: **T-W19** (`WindowsRatingsReviewsView`, critical path; all deps T-W03+T-W16+T-W17+T-W18 now satisfied).

**Non-blocking follow-ups recorded for future sessions:**
1. **Should-fix: DateFormatter caching in T-W04** (`WindowsDateFormatting.absoluteDate`) — allocates new formatter per call; should cache as static let (recommended before/within T-W19 QA).
2. **Should-fix: `variant` default** — `WindowsReviewRow` should default `variant` to `.list` for caller convenience.
3. **Nit: Doc/code consistency** — align header comment + test docstring from `"..."` to `"…"` (unicode ellipsis) to match implementation.

----

## Wave 3 Development — T-W19 (DONE)

**Specification (from 2026-06-08-windows-apps-and-reviews.md §3.18):**
- **Scope:** Build `WindowsRatingsReviewsView` — a composite ratings + reviews display view. Compose aggregate rating card (T-W17 output), review rows in `.list` variant (T-W18 output), Load More button (T-W04 output), bound to `WindowsRatingsReviewsModel` (T-W16 output).
- **Acceptance Criteria:** AC-W10-1 (rating card or "Rating unavailable" banner), AC-W10-2 (empty state "No Reviews Yet" when no reviews), AC-W10-3 (reviews list with conditional Load More), AC-W11-1 through AC-W11-6 (various review row display modes).
- **Test Cases:** TC-064 (rating card display + fallback), TC-065 (empty state + Load More visibility), TC-066 (error-banner retry, first-page load).
- **Critical path:** T-W01 → T-W16 → **T-W19** → T-W28 → T-W29.

**Implementation:**

Files delivered:
- NEW: `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Ratings/WindowsRatingsReviewsView.swift` (307 lines) — Factory + Entry + View:
  - **Factory** (`WindowsRatingsReviewsViewFactory`): builds the entry point.
  - **Entry** (`WindowsRatingsReviewsEntry`): owns `@StateObject` coordinators and viewModel, injects into View.
  - **View** (`WindowsRatingsReviewsView`): generic over `WindowsRatingsReviewsViewModelProtocol`. Displays rating section (card or "Rating unavailable" banner when `uiState.ratingResult == nil`), reviews content (first-page loading state, "No Reviews Yet" empty state, error-retry banner with tap callback, reviews list with Load More button visible when `hasMoreReviews`). Row tap (delegate pattern) → `coordinator.push(.reviewDetail(review))`. `.task` modifier triggers `viewModel.loadRatingsIfNeeded()` on entry.
- MODIFIED: `WindowsDateFormatting.swift` — Cached `DateFormatter` as `private static let absoluteDateFormatter` (incorporated T-W18 Should-fix 1). Public API unchanged; all 18 existing tests still pass.
- MODIFIED: `RootView.swift` — Added `RatingsReviewsModelCache` (reference holder, keyed by appId+accountId, lazy-init pattern) and wired `.ratingsAndReviews` route to real `WindowsRatingsReviewsView` (pre-wires T-W21's nominal scope; T-W21 becomes verify/finalize task, mirroring T-W12→T-W14 precedent).

**Commits:**
- Feature commit: `f9ae9c1` (impl `WindowsRatingsReviewsView` + plumb into RootView).
- **Merged into `experiment/windows`:** Merge commit `cb32d93` (--no-ff merge strategy). Branch `feat/T-W19-windows-ratings-reviews-view` deleted; worktree removed.

**Gate verdicts:**
- **Staff Review:** APPROVE (0 blocking corrections).
  - **Follow-up 1 (Should-fix):** Reviews error-banner "Retry" calls `loadRatingsIfNeeded`, which restarts BOTH rating and reviews loads concurrently rather than only reviews. Practical impact zero in Windows v1 (RootView passes `connection: nil`, so reviews-error state never occurs in production this milestone). Revisit when live sync enabled.
  - **Nit 1 (doc):** `WindowsRatingsReviewsViewFactory` docstring slightly outdated (minor doc-only).
  - **Nit 2 (port-wide):** User-facing strings not wrapped in `String(localized:)` (consistent with the rest of the Windows port; deferred port-wide).
- **QA:** PASS (full suite 270/270 tests green; TC-064 10 tests, TC-065 3 tests, all passing; all 9 ACs verified manually; manual Windows VM rendering confirmed).
- **PO:** ACCEPTED (all 9 ACs met: AC-W10-1/2/3, AC-W11-1..6).
- **Corrections:** 0.

**Wave 3 progress:** Critical-path view layer (WindowsRatingsReviewsView) merged. Rating & Reviews feature functionally complete. All T-W15/T-W16/T-W17/T-W18/T-W19 critical-path tasks on T-W01→T-W16→T-W19 delivered. Next unblocked: **T-W20** (S test consolidation/gap-analysis; deps T-W15+T-W16 both DONE; much of coverage already exists: 16 WindowsRatingsReviewsModelTests + AggregateRatingFormatterTests green; T-W20 is largely consolidation task to verify full coverage).

**Non-blocking follow-ups for future sessions:**
1. **T-W19 Staff Should-fix 1:** reviews error-banner "Retry" → `loadRatingsIfNeeded` (restarts both rating+reviews concurrently, not just reviews). Zero practical impact in v1 (RootView passes `connection: nil`, reviews-error never occurs production). Revisit when live sync enabled.
2. **T-W19 Staff Nit 1:** `WindowsRatingsReviewsViewFactory` docstring outdated.
3. **T-W19 Staff Nit 2:** User-facing strings not wrapped in `String(localized:)` (port-wide deferred).
4. **(Carry-over) T-W18 Should-fix 2 + T-W18 doc Nits:** Remain as-is if previously recorded.

---

## Wave 3 Development — T-W20 (DONE)

**Task:** Unit test consolidation and coverage-gap closure for `WindowsRatingsReviewsModel` (T-W16) and `ITunesLookupService` (T-W15). TEST-ONLY task; no production code changed.

**Specification:**
- **Scope:** Add comprehensive unit tests for T-W16 and T-W15 to verify all acceptance criteria, error paths, resilience, and edge cases. Fill gaps in existing coverage.
- **Acceptance Criteria (supporting T-W15 + T-W16):** AC-W10-1 (aggregate rating fetch), AC-W10-2 (independent loading states), AC-W10-3 (graceful iTunes failure), AC-W11-1 (paginated reviews), AC-W11-3 (opaque cursor), AC-W11-6 (sort/filter passthrough).
- **Test Scope:** Extend iTunesLookupServiceTests and WindowsRatingsReviewsModelTests to cover URL construction + percent-encoding, malformed/partial JSON resilience, single-storefront isolation, missing rating/review fields → notFound, per-bundleId cache isolation, dual-load atomicity, error clearing on retry, Load More plumbing, simultaneous dual failures.

**Implementation:**

Files modified/extended:
- NEW/EXTENDED: `Tests/WindowsAppCoreTests/ITunesLookupServiceTests.swift` — added tests for URL percent-encoding with result-level assertions, malformed JSON resilience, partial JSON robustness, per-storefront isolation (single storefront doesn't poison others), missing ratingCount/averageRating → notFound fallback.
- NEW/EXTENDED: `Tests/WindowsAppCoreTests/WindowsRatingsReviewsModelTests.swift` — added tests for dual-load flag atomicity (both loading flags reset after completion), error clearing on successful retry (ratingError/reviewsError → nil), Load More passthrough (sort/filter preserved on pagination), bundleId passthrough to lookup, cumulative multi-page append, simultaneous dual-failure resilience.

**Summary:**
- Net +14 tests (28 added across both test files; 1 deleted in correction round). Final WindowsAppCore suite: 284 tests, 0 failures.
- Gaps filled: URL construction + percent-encoding, malformed/partial JSON resilience, single-storefront-doesn't-poison-others, missing ratingCount/averageRating → notFound, per-bundleId cache isolation, dual loading-flag atomicity, error clearing on retry, Load More plumbing, bundleId passthrough, cumulative multi-page append, simultaneous dual failures.

**Commits:**
- Feature commit: `34fd4df` (add 28 comprehensive unit tests across both suites).
- Correction commit: `7b8a16e` (resolve Staff Code Review feedback: rewrote `testRatingErrorClearedOnRetry` to genuinely observe non-nil→nil transition on single SUT; deleted unreachable/duplicate `testLoadNextPageNoConnectionResetsLoadingMore`; corrected malformed-JSON test comments; added result-level assertions to percent-encoding test).
- **Merged into `experiment/windows`:** Merge commit `6372480` (--no-ff merge strategy). Worktree and branch removed.

**Gate verdicts:**
- **Staff Code Review:** CHANGES REQUESTED → APPROVE (1 correction: test structural coherence).
  - **Correction 1:** `testRatingErrorClearedOnRetry` was incoherent (had non-observable nil→nil on distinct SUT snapshots). Rewrote to assert single SUT before/after. Deleted duplicate `testLoadNextPageNoConnectionResetsLoadingMore` (unreachable code path). Corrected malformed-JSON comments. Added result-level assertions to percent-encoding test.
- **QA:** PASS (284 tests, 0 failures; all 6 supporting ACs verified; both test suites fully green).
- **PO:** ACCEPTED (all 6 supporting ACs covered: AC-W10-1, AC-W10-2, AC-W10-3, AC-W11-1, AC-W11-3, AC-W11-6; testing complete, no production behavior change).
- **Corrections:** 1.

**Wave 3 progress:** Test consolidation for T-W15/T-W16 complete. 284-test suite with zero failures. Critical path clear: T-W01 → T-W16 → T-W19 → **T-W22** (next). T-W21 is satisfied by T-W19 (verify-only side-effect; RootView pre-wired `.ratingsAndReviews` during T-W19 implementation).

**Non-blocking follow-ups for future sessions:** None for T-W20; full coverage achieved.

---

## Wave 4 Development — T-W22 (DONE)

**Task:** Build `WindowsReviewDetailModel` — the data model for the Review Detail screen (Feature 4), providing offline-first load with optional live refresh, mutable reply operations (send/edit/delete), clipboard integration with auto-dismiss, and full review detail state management.

**Specification:**

**Deliverables:**
- `StackConnectWindowsApp/Sources/WindowsAppCore/Ratings/WindowsReviewDetailModel.swift` — Main model with `@MainActor` concurrency protection, offline-first `loadReviewIfNeeded()` with cache fallback (`syncError`), reply operations (`sendReply`, `deleteReply` via `upsertReply` PATCH delete-then-create), clipboard integration with injectable `ClipboardProviding` + auto-dismiss via `Task<Void,Error>` + `try await`, and `ReviewDetailUiState` with `replyMode` (`.create` / `.edit(responseId:)`) to arbiter edit vs create.
- **Offline-first pattern:** Load from cache first, then sync from API. Show toast during sync; preserve `syncError` across mutations for resilience.
- **Reply state management:** `replyMode` enum-based (`.create` vs `.edit(responseId:)`) to prevent duplicate server POST on PENDING_PUBLISH reviews via atomicity with `responseId != nil` sole arbiter.
- **Clipboard integration:** Injected `ClipboardProviding` protocol for testability; "Copied!" toast with configurable auto-dismiss delay (injectable for T-W26 follow-up); fallback to host OS if provider unavailable.
- **Non-blocking follow-ups (documented, not blockers):** Cosmetic out-of-range rating star formatting (data-layer responsibility); injectable `clipboardAutoDismissDelay` for T-W26; single-page live-sync limitation documented; post-create local `local-*` placeholder responseId behavior documented.

**Commits:**
- Feature commit: `7d67789` (add WindowsReviewDetailModel with full feature scope).
- Correction commit: `044f124` (resolve Staff Code Review feedback: BLOCKING-1 `responseId != nil` as sole edit arbiter, BLOCKING-2 clipboard auto-dismiss via `Task<Void,Error>` + `try await`; SHOULD-FIX-1/2/3 injectable delay, live-sync docs, placeholder responseId docs).
- **Merged into `experiment/windows`:** Merge commit `a2765d0` (--no-ff merge strategy).

**Gate verdicts:**
- **Staff Code Review:** CHANGES REQUESTED → APPROVE (1 correction: atomicity + async patterns).
  - **BLOCKING-1:** `sendReply` on PENDING_PUBLISH reviews could POST duplicate if call repeated before local state reflects server response — fixed via `responseId != nil` as sole edit-mode arbiter (no longer relies on mutable `isEditingReply` flag). Ensures atomicity: once POST succeeds and `responseId` is set, subsequent calls see `isEditingReply == true` via `.edit(responseId)` branch, preventing duplicate POST.
  - **BLOCKING-2:** Clipboard auto-dismiss via `DispatchQueue.main.asyncAfter` with cancellation antipattern (could dismiss during user interaction) — fixed via `Task<Void,Error>` with explicit `try await Task.sleep(nanoseconds:)` + structured cancellation per Swift Concurrency best practices.
  - **SHOULD-FIX-1:** `clipboardAutoDismissDelay` hardcoded to 1.5 seconds — documented as injectable for T-W26 follow-up (currently sourced from `WindowsDateFormatting.defaultAnimationDuration` constant; will be abstracted in T-W26).
  - **SHOULD-FIX-2:** Single-page live-sync limitation (only syncs reviews on current review detail page, not background sync) — documented as known limitation; full background-sync architecture is T-W31+ scope.
  - **SHOULD-FIX-3:** Post-create local placeholder responseId with `local-*` prefix — documented in code comments; will be cleaned up on server response; prevents `nil` crashes if user immediately attempts edit before sync completes.
- **QA:** PASS (284 tests total, 0 failures; TC-032 model layer offline-first verification PASS by inspection; TC-034/035/036 reply send/edit/delete paths PASS by inspection; TC-038 clipboard "Copied!" toast + auto-dismiss PASS by inspection; TC-040/041/042 delete reply flows PASS by inspection; TC-043/044 cache fallback + syncError preservation PASS by inspection; TC-033/037/039 view-layer navigation routes deferred to T-W23/24/25/27).
- **PO:** ACCEPTED (all 14 model-layer acceptance criteria Met: AC-W12-1 offline-first load, AC-W12-2 cache fallback, AC-W12-3 syncError preservation; AC-W13-1 reply mode state, AC-W13-2 sendReply upsert, AC-W13-3 sendReply create path, AC-W13-4 sendReply PENDING_PUBLISH atomicity, AC-W13-5 sendReply optimistic local update, AC-W13-6 edit-reply create-then-update pattern, AC-W13-7 deleteReply, AC-W13-8 clipboard copy, AC-W13-9 clipboard auto-dismiss; AC-W14-1 ReviewDetailUiState, AC-W14-2 replyMode enum).
- **Corrections:** 1 (commit `044f124`).

**Files created/modified:**
- NEW: `WindowsAppCore/Ratings/WindowsReviewDetailModel.swift`.
- NOT modified (no view/route changes at this stage): `RootView`, `WindowsHomeCoordinator` (T-W27 will wire `.reviewDetail` route; T-W23 will build view).

**Wave 4 progress:** Review Detail model layer (T-W22) complete. 284-test suite with zero failures. Critical path progressing: T-W01 → T-W16 → T-W19 → T-W22 → **T-W23** (next, WindowsReviewDetailView view layer).

**Non-blocking follow-ups for T-W26 session:** Inject `clipboardAutoDismissDelay` from configurable source (currently hardcoded to `WindowsDateFormatting.defaultAnimationDuration` = 1.5s); document T-W26 ownership.

**Non-blocking follow-ups (documented, not for T-W23 session):** Cosmetic out-of-range rating star formatting (data-layer responsibility, not model); single-page live-sync limitation (full background-sync is T-W31+ scope); post-create `local-*` placeholder responseId (will be cleaned up on server response).

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
| 9 | **T-W09** | ✅ DONE (merged `216329f`) | Wave 1 — Comprehensive unit tests for `WindowsAppsListModel` |
| 10 | **T-W10** | ✅ DONE (merged `ad04ce6`) | Wave 1 — Wire `.appsList`/`.archivedApps` in RootView + navigate from accounts row |
| 11 | **T-W11** | ✅ DONE (merged `7186f9c`) | Wave 2 — `WindowsAppDetailModel` (F2 App Detail); 1 correction (buildSections, logging, syncError) |
| 12 | **T-W12** | ✅ DONE (merged `6e45f26`) | Wave 2 — `WindowsAppDetailView` (F2 UI layer); 1 correction (cache keying, invalidate wiring, logging/comments, toolbar consolidation) |
| 13 | **T-W13** | ✅ DONE (no diff) | Wave 2 — Unit tests for `WindowsAppDetailModel`; satisfied by 15 tests from T-W11; 0 corrections |
| 14 | **T-W14** | ✅ DONE (merged `6574aa1`) | Wave 2 — Wire `.appDetail`/`.comingSoon` in RootView (verify/finalize); 1 correction (ownership comments) |
| 15 | **T-W15** | ✅ DONE (merged `63b0e8a`) | Wave 3 — `iTunesLookupService` (M); commits `a8220f6`, `cf83c5f`; TC-079 formula authority (4.5225), cache resilience (SF-1/SF-2), concurrency/encoding comments (N-1/N-2/N-3); QA 235/235 suite + 21/21 ITunesLookupServiceTests green; 1 correction |
| 16 | **T-W16** | ✅ DONE (merged `fa757b6`) | Wave 3 — `WindowsRatingsReviewsModel` (M, critical path); commits `8c6ebcb`, `b49c908`; Staff APPROVE (SF-1/SF-2/Nit-1/Nit-2); QA 251/251 suite, 16/16 model tests; PO ACCEPTED (7 ACs, 7 TCs); 1 correction |
| 17 | **T-W17** | ✅ DONE (merged `b1f97dd`) | Wave 3 — `WindowsAggregateRatingCard` (S); commits `b4bb5ad`, `cd5ba13`; Staff APPROVE (BLOCKING-1 cached formatters, SHOULD-FIX-1/2 locale tests & empty state, NIT-1 redundant property); QA 257/257 suite + 6/6 formatter tests; PO ACCEPTED (AC-W10-1); 1 correction |
| 18 | **T-W18** | ✅ DONE (merged `493ddc7`) | Wave 3 — `WindowsReviewRow` (S); feature commit `8adf872`; Staff APPROVE (0 corrections; non-blocking follow-ups: SF-1 DateFormatter caching in T-W04, SF-2 variant default, Nit doc consistency); QA PASS 270/270 (TC-064 10 tests, TC-065 3 tests + 13 ReviewExcerptFormatterTests); PO ACCEPTED (AC-W11-1, AC-W11-6); 0 corrections |
| 19 | **T-W19** | ✅ DONE (merged `cb32d93`) | Wave 3 — `WindowsRatingsReviewsView` (M, critical path); feature commit `f9ae9c1`; Staff APPROVE (0 blocking; 1 should-fix, 2 nits on follow-up); QA PASS 270/270 (TC-064 10 tests, TC-065 3 tests, all 9 ACs verified); PO ACCEPTED (all 9 ACs: AC-W10-1/2/3, AC-W11-1..6); 0 corrections |
| 20 | **T-W20** | ✅ DONE (merged `6372480`) | Wave 3 — Test consolidation (S, deps T-W15+T-W16 DONE); commits `34fd4df`, `7b8a16e`; Staff APPROVE (1 correction: test coherence); QA PASS 284/284 tests, 0 failures; PO ACCEPTED (all 6 supporting ACs); 1 correction |
| 21 | **T-W21** | ✅ SATISFIED (by T-W19) | Wave 3 — Wire `.ratingsAndReviews` route (M); satisfied by T-W19 (RootView pre-wired `.ratingsAndReviews` → real `WindowsRatingsReviewsView` during T-W19). Verify-only task; complete as side-effect. |
| 22 | **T-W22** | ✅ DONE (merged `a2765d0`) | Wave 4 — `WindowsReviewDetailModel` (M, critical path); commits `7d67789`, `044f124`; Staff APPROVE (BLOCKING-1 `responseId` edit arbiter, BLOCKING-2 clipboard async, SHOULD-FIX-1/2/3 delay+docs); QA PASS 284/284 tests; PO ACCEPTED (14 model-layer ACs: AC-W12-1/2/3, AC-W13-1..9, AC-W14-1/2); 1 correction |
| 23 | **T-W23** | ⏳ NEXT (unblocked) | Wave 4 — `WindowsReviewDetailView` (S, critical path, deps T-W03+T-W22 DONE) |

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
