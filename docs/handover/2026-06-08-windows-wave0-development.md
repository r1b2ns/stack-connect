# Handover — Windows Port Wave 0 Development

**Date:** 2026-06-08
**Skill:** `/personal-development` — **now SERIAL, ONE TASK PER SESSION** (the skill was rewritten: one agent at a time, foreground only; each session develops exactly one task end-to-end then ends).
**Base branch:** `experiment/windows`
**Artifact (source of truth):** `docs/refinements/2026-06-08-windows-apps-and-reviews.md`
**Test cases:** `docs/refinements/2026-06-08-windows-port-test-cases.md`
**Status:** T-W01 DONE (merged into `experiment/windows` as `7ef4617`); T-W02 DONE (accepted, committed `556c537`, not yet merged); next session begins with **T-W03**.

**Snapshot:** T-W01 went through the serial one-task-per-session pipeline, passed all gates (Staff APPROVE, QA PASS 98/98 tests, PO ACCEPTED all 5 acceptance criteria), and is merged to `experiment/windows`. T-W02 has been committed (556c537), passed all gates (Staff APPROVE, QA PASS 89 tests, PO ACCEPTED all ACs), but **not yet merged** (merge deferred to Wave 0 close-out). T-W03, T-W04 corrections/dev are green in worktrees but uncommitted. No pushes/merges to remote yet.

> **How to resume:** the next session begins with **T-W03** (parameterize WindowsRoute + wire RootView). Its correction is green & uncommitted in worktree `feat-T-W03-windows-route-enum` — the next session commits it (message in the T-W03 section below) → Staff Review → QA → PO. Start a fresh session, run `/personal-development`, pick T-W03, and follow the serial pipeline. Update handover and end.

---

## Session decisions (locked in)

- **Scope:** Wave 0 — Foundation only: **T-W01, T-W02, T-W03, T-W04** (no inter-dependencies among them).
- **Git authorization:** **Commit only.** `git-docs-manager` auto-commits each green task. **Push, PR, and all merges (to `experiment/windows` or `master`) stay gated** — ask the user before any of them.
- **No AI attribution** in any commit/PR (verified on all commits so far).
- Windows SwiftPM packages auto-discover files → **no `xcodegen` needed** for Windows package changes (only for iOS app-target file changes).
- All test execution → `test-runner` agent. All git/docs → `git-docs-manager` agent.

---

## Task board (current state)

| Task | Title | Branch | Commits (ahead of base) | Gate state |
|------|-------|--------|--------------------------|------------|
| **T-W01** | SDK + AppleConnectionProtocol for Windows GUI | `feat/T-W01-windows-apple-connection` | `7e5fbca` (feat) + `3eb047b` (correction) | DONE — merged into experiment/windows (7ef4617). Staff APPROVE / QA PASS 98/98 / PO ACCEPTED. 1 correction. |
| **T-W02** | `WindowsClipboard.setText()` | `feat/T-W02-windows-clipboard-settext` | `ab1f133` (feat) + `556c537` (correction) | DONE — PO ACCEPTED. Staff APPROVE / QA PASS (3 macOS-host tests pass, 5 clipboard tests, 89 total 0 fail) / 0 new corrections. Not yet merged (Wave 0 close-out). |
| **T-W03** | Parameterize `WindowsRoute` + wire RootView | `feat/T-W03-windows-route-enum` | `d40635e` (feat) | Staff review APPROVE w/ should-fix S-1. Correction agent `a72f606078658fd0d` **DONE green (86 tests, 0 fail)** — fix in worktree, **NOT yet committed**. Next: `git-docs-manager` commits → re-run Staff Review → QA → PO |
| **T-W04** | Shared Windows UI components | `feat/T-W04-windows-shared-components` | none yet | Developer agent `a9537749abaac23c7` **DONE green (104 tests, 0 fail)** — 9 files in worktree, **NOT yet committed**. Next: `git-docs-manager` commits → Staff Review → QA → PO |

**No QA (mobile-qa-reviewer) or PO (product-owner) gate has run for any task yet. No pushes, no merges.**

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
Correction agent `a72f606078658fd0d` **finished green** (86 tests, 0 fail). Changed `onSeeMore`/`onSeeMoreReviews` signature `() -> Void` → `(AppModel?) -> Void` across `WindowsRecentReviewsWidgetView.swift`, `WindowsWidgetContainerView.swift`, `WindowsHomeView.swift`; widget passes `data.reviews.first?.app`; `widgetsSlot` routes to `.ratingsAndReviews(appId:bundleId:accountId:)` (falls back to `.comingSoon` only when nil). **Not yet committed.** Proposed commit message:
```
fix(T-W03): route "See more" reviews to ratingsAndReviews (S-1)

Thread the first review's AppModel through the onSeeMoreReviews
callback chain so the Recent Reviews widget's "See more" action
pushes .ratingsAndReviews(appId:bundleId:accountId:) instead of
.comingSoon. Falls back to .comingSoon only when the widget has no
reviews (nil app). Corrects the comment that wrongly claimed there
was no single-app context available.
```

### T-W04 (branch `feat/T-W04-windows-shared-components`)
Developer `a9537749abaac23c7` **finished green** (104 tests, 0 fail). 9 files created, **not yet committed**:
- `.../StackConnectWindowsApp/Shared/WindowsStatusBadge.swift` (uses `AppStoreState.color`; Ready for Sale=green, Pending Developer Release=yellow, Prepare for Submission=blue; colored-text fallback per A-04)
- `.../StackConnectWindowsApp/Shared/WindowsSectionHeader.swift` (title + optional `onSeeAll`)
- `.../StackConnectWindowsApp/Shared/WindowsOptionRow.swift` (glyph/label + chevron; `.onTapGesture`)
- `.../StackConnectWindowsApp/Shared/WindowsRatingStarsView.swift` (delegates to `StarRatingFormatter.starString(for:)`)
- `.../StackConnectWindowsApp/Shared/WindowsLoadMoreButton.swift` (`isLoading` → `ProgressView()`)
- `.../StackConnectWindowsApp/Shared/WindowsCountBadge.swift` (hidden when count 0)
- `.../StackConnectWindowsApp/Shared/WindowsComingSoonView.swift` (centered glyph + title + message; plain literals)
- `.../WindowsAppCore/Shared/WindowsDateFormatting.swift` (Foundation-pure: `relativeDate(_:relativeTo:)` time-ago + `absoluteDate(_:timeZone:)` "d MMM yyyy"; injectable `now`)
- `.../Tests/WindowsAppCoreTests/WindowsDateFormattingTests.swift` (18 tests)

Proposed commit message:
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

---

## Resume checklist — ONE TASK PER SESSION (serial)

The four agents from the old parallel run all finished green. The remaining work is now done **one task per session** (the new skill model). **Do exactly one task per session**, in this order, then update this handover and end the session.

### Session order (next session starts at the top non-done task)

| Order | Task | Starting point this session | Steps to run (serial, one agent at a time) |
|-------|------|------------------------------|---------------------------------------------|
| 1 | **T-W01** | ✅ DONE (merged `7ef4617`) | — |
| 2 | **T-W02** | ✅ DONE (committed `556c537`, not yet merged) | — |
| 3 | **T-W03** | Correction green, **uncommitted** | `git-docs-manager` commits (msg below) → Staff Review (S-1 was should-fix; APPROVE expected) → QA → PO → done → update handover → END |
| 4 | **T-W04** | Dev green, **uncommitted** (no prior review) | `git-docs-manager` commits (msg below) → first Staff Review → QA → PO → done → update handover → END |

### Per-session rules (from the rewritten skill)
- **One agent at a time, foreground only** — never `run_in_background`; wait for each agent before the next.
- **Git auth is per session, commit-only** — confirm at session start. Push/PR stay gated. **Merges into `experiment/windows` need explicit user OK; never merge to `master` automatically.**
- After the task is **PO-ACCEPTED**, `git-docs-manager` updates this handover (mark done, record SHA/verdicts, set next-task pointer) and the session **ends** — the next task is a **fresh session** to save tokens.

### Wave 0 close-out (after all 4 tasks are done)
Ask the user for explicit authorization to merge the approved Wave 0 branches into `experiment/windows`. Never merge to `master` without explicit authorization.

## Key facts for gate agents
- Pass per-task slice of: Task Breakdown (artifact §3.2), Acceptance Criteria, Test Cases — keyed by task id.
- Package split: `WindowsAppCore` (testable, Foundation-pure, SDK-free) vs `StackConnectWindowsApp` (executable, SDK adapter lives here). SDK `appstoreconnect-swift-sdk` branch `windows-support` (fork `r1b2ns`) added to **executable target only**.
- Test-runner is the only agent that runs tests; git-docs-manager is the only agent that commits/pushes/PRs/merges/docs.
