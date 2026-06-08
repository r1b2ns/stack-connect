# STACKCONNECT WINDOWS PORT — TEST CASES DOCUMENT

**Scope:** Windows v1 release — 5 features, 17 user stories (US-W01..US-W17)
**Prepared by:** QA Reviewer
**Date:** 2026-06-08
**Environment:** SwiftCrossUI + WinUI backend, Swift 6, LIVE App Store Connect API calls

---

## DOCUMENT OVERVIEW

This document defines test cases (Unit, Integration, UI, Manual) covering:
1. **Happy paths** — Every acceptance criterion in US-W01..W17
2. **Edge cases & negative scenarios** — Empty states, network errors, API failures, boundary conditions
3. **Platform constraints** — SwiftCrossUI rendering, no sheets/alerts, pagination reload behavior, clipboard on Windows vs macOS host
4. **Automatable vs manual** — Clear separation of unit/integration tests (ViewModels, services) from UI/rendering tests

**Test execution:** Unit and integration tests run via the `test-runner` agent (WindowsAppCore test suite). UI tests are manual or require SwiftCrossUI rendering verification on Windows. All non-code assertions (navigation push/pop, glyph rendering, in-app banners) are Manual/marked for visual verification.

---

## FEATURE & USER STORY BREAKDOWN

| Feature | User Stories | Description |
|---------|--------------|-------------|
| F1: Apps List | US-W01..W05 | List apps per account; search; Favorites; Archive; Users tab |
| F2: App Detail | US-W06..W09 | Detail card; sections (General, App Store, Analytics, TestFlight); Ratings navigates, others "Coming Soon" |
| F3: Ratings & Reviews | US-W10..W11 | Aggregate rating card + paginated reviews; tap row → Review Detail |
| F4: Review Detail | US-W12..W14 | Full review; reply upsert (create/edit); delete with confirmation; copy-to-clipboard |
| F5: Recent Reviews Widget | US-W15..W17 | Home card with up to 5 reviews (all accounts); count badge; auto-refresh + manual refresh |

---

## TEST CASES (PART 1: F1 APPS LIST)

### F1 Preconditions (all F1 test cases)
- WindowsAppCore MockStorage seeded with:
  - 1 account (id: "acct-001", name: "My Team", type: "asc")
  - 5 apps (cached): id/bundleId/name/status/version/icon (json blob)
  - 2 Favorite toggles (app-001, app-003)
  - 1 archived app (app-005)
- WindowsAppsListModel instance with MockStorage
- MockSecrets (credentials stored)
- Network layer mocked (fast response)

---

#### TC-001: Apps List — Load from Cache, Display All (Happy Path, US-W01 AC-1)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsAppsListModel with MockStorage seeded with 5 apps (cached)
  2. Call `loadAppsIfNeeded(accountId: "acct-001")`
  3. Verify `uiState.apps` contains exactly 5 items (in order)
  4. Verify each app has: id, bundleId, name, status (colored), version, icon
  5. Verify `uiState.isLoading` = false
  6. Verify no network call made (cache served)
- **Expected Result:** ✅ Apps loaded from cache, UI state populated, no network call
- **Preconditions:** Cache exists with 5 apps
- **Regression Risk:** Changes to cache loading, pagination logic

---

#### TC-002: Apps List — Live Sync Updates Cache (Happy Path, US-W01 AC-2)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsAppsListModel with cache containing 5 apps
  2. Call `loadAppsIfNeeded(accountId: "acct-001")` with network available
  3. Verify `uiState.isLoading` = true (banner shown during sync)
  4. Simulate network response: 6 apps (1 new app added: app-006)
  5. Verify `uiState.apps` updated to 6 items
  6. Verify cache updated (next load sees 6 apps)
  7. Verify `uiState.isLoading` = false (banner dismissed)
- **Expected Result:** ✅ Live sync merges, cache updated, banner shows/hides correctly
- **Preconditions:** Cache exists, network is available
- **Regression Risk:** Sync banner state, cache persistence

---

#### TC-003: Apps List — Search Filter (All Apps & Favorites), US-W01 AC-3
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsAppsListModel with 5 cached apps (2 Favorites: app-001 "Foo", app-003 "Bar")
  2. Call `setSearchQuery("Foo")` on All Apps tab
  3. Verify `uiState.apps` filtered to 1 item (app-001)
  4. Switch to Favorites tab (manually via test)
  5. Verify Favorites shows only app-001 and app-003 (2 items total)
  6. Call `setSearchQuery("o")` on Favorites tab
  7. Verify Favorites filtered to app-001 "Foo" (matches name)
  8. Verify app-003 "Bar" removed (doesn't match)
  9. Call `setSearchQuery("")` → reset
  10. Verify All Apps shows 5 apps, Favorites shows 2 apps
- **Expected Result:** ✅ Search filters independently on All Apps & Favorites tabs, resets correctly
- **Preconditions:** Cache has mixed Favorite/non-Favorite apps
- **Regression Risk:** Search logic, tab state independence

---

#### TC-004: Apps List — Search by BundleId (Happy Path, US-W01 AC-3)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsAppsListModel with 5 cached apps
  2. App with id "app-002" has bundleId "com.example.myapp"
  3. Call `setSearchQuery("com.example")` on All Apps tab
  4. Verify `uiState.apps` filtered to 1 item (app-002)
  5. Call `setSearchQuery("example.myapp")` → substring still matches
  6. Verify app-002 still returned
  7. Call `setSearchQuery("xample.m")` → case-insensitive match
  8. Verify app-002 returned
- **Expected Result:** ✅ BundleId search works case-insensitive, substring match
- **Preconditions:** Cache has apps with bundleId data
- **Regression Risk:** Search algorithm, case sensitivity

---

#### TC-005: Apps List — Search No Match (Edge Case, US-W01 AC-3)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsAppsListModel with 5 cached apps
  2. Call `setSearchQuery("ZzzUnmatchable123")`
  3. Verify `uiState.apps` is empty
  4. Verify no error state (graceful empty list)
  5. Call `setSearchQuery("")` → reset
  6. Verify all 5 apps returned
- **Expected Result:** ✅ No-match search returns empty list gracefully, reset works
- **Preconditions:** Cache has apps
- **Regression Risk:** Empty state handling

---

#### TC-006: Apps List — Toggle Favorite (Persist Across Restart, US-W01 AC-4)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsAppsListModel with cache (5 apps, 2 Favorites: app-001, app-003)
  2. Call `toggleFavorite(appId: "app-002")` (non-favorite → favorite)
  3. Verify `uiState.apps[2].isFavorite` = true
  4. Verify favorite persisted to MockStorage
  5. **Restart simulation:** Create new WindowsAppsListModel instance, load cache
  6. Verify `uiState.apps[2].isFavorite` = true (persisted across "restart")
  7. Call `toggleFavorite(appId: "app-001")` (favorite → non-favorite)
  8. Verify `uiState.apps[0].isFavorite` = false
  9. Restart simulation → Verify app-001 non-favorite
- **Expected Result:** ✅ Favorite toggles persist across model restart (simulating app restart)
- **Preconditions:** Cache exists
- **Regression Risk:** Favorite persistence logic, cache update mechanism

---

#### TC-007: Apps List — Archive App (Happy Path, US-W01 AC-5)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsAppsListModel with 5 cached apps
  2. Call `archiveApp(appId: "app-004", showConfirmation: true)` → pushes deleteConfirm route with confirmation text
  3. **Verification:** Confirmation screen shown (manual UI assertion)
  4. User confirms → model calls `archiveAppConfirmed(appId: "app-004")`
  5. Verify app-004 removed from `uiState.apps` (4 items remain)
  6. Verify isArchived=true persisted to storage
  7. Verify navigation pops back to apps list (model state)
- **Expected Result:** ✅ Archive removes from All Apps, persists, pops back to list
- **Preconditions:** Cache has non-archived apps
- **Regression Risk:** Archive logic, confirmation flow, navigation state

---

#### TC-008: Apps List — Archive Confirmation Cancel (Edge Case, US-W01 AC-5)
- **Type:** UI/Manual
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsAppsListModel with 5 cached apps
  2. Call `archiveApp(appId: "app-003")` → pushes delete confirmation route
  3. **UI:** User navigates back (pops route) or taps Cancel button on confirmation screen
  4. Model receives cancellation (route popped, no archive action)
  5. Verify app-003 still in `uiState.apps` (5 items)
  6. Verify isArchived=false in storage
  7. Verify user returned to apps list
- **Expected Result:** ✅ Cancellation aborts archive, app remains in list
- **Preconditions:** Archive confirmation screen displayed
- **Regression Risk:** Navigation pop handling, cancel logic

---

#### TC-009: Apps List — Archived Apps Screen (Restore, US-W01 AC-5)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsArchivedAppsModel with MockStorage
  2. MockStorage has 1 archived app (app-005, isArchived=true)
  3. Call `loadArchivedApps(accountId: "acct-001")`
  4. Verify `uiState.archivedApps` contains 1 item
  5. Call `restoreApp(appId: "app-005")`
  6. Verify app-005 removed from `uiState.archivedApps` (0 items)
  7. Verify isArchived=false persisted to storage
  8. Verify navigation pops back (or manual pop UI action)
- **Expected Result:** ✅ Restore removes app from archived list, updates persistence
- **Preconditions:** Archived app exists in cache
- **Regression Risk:** Restore logic, archived apps list state

---

#### TC-010: Apps List — Empty Apps (No Apps, Edge Case, US-W01)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsAppsListModel with MockStorage (empty, no apps cached)
  2. Call `loadAppsIfNeeded(accountId: "acct-001")`
  3. Verify `uiState.apps` is empty
  4. Verify `uiState.isLoading` = false
  5. **UI assertion (manual):** Empty state message displayed (e.g., "No apps found")
- **Expected Result:** ✅ Empty apps handled gracefully, empty state shown
- **Preconditions:** Cache is empty
- **Regression Risk:** Empty state rendering

---

#### TC-011: Apps List — Network Failure, Fallback to Cache (Edge Case, US-W01 AC-2)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsAppsListModel with cache (5 apps)
  2. Simulate network error (NetworkError.offline or timeout)
  3. Call `loadAppsIfNeeded(accountId: "acct-001")`
  4. Verify `uiState.isLoading` = true initially
  5. Verify error caught, `uiState.isLoading` = false
  6. Verify `uiState.syncError` = error message (e.g., "Network unavailable")
  7. Verify `uiState.apps` still shows cached 5 apps (no data loss)
  8. Verify **sync banner** shows error state (manual UI assertion)
- **Expected Result:** ✅ Network failure shows error in banner, cache still displayed
- **Preconditions:** Cache exists, network mocked to fail
- **Regression Risk:** Error handling, banner state

---

#### TC-012: Apps List — Users Tab (Display Users per App, US-W01 AC-5)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsUsersListModel with MockStorage
  2. MockStorage has 1 app with 3 users (id/name/role/email):
     - User1 (name: "Alice", role: "Admin")
     - User2 (name: "Bob", role: "Developer")
     - User3 (name: "Charlie", role: "Marketing")
  3. Call `loadUsersForApp(appId: "app-001", accountId: "acct-001")`
  4. Verify `uiState.users` contains 3 items (in order)
  5. Verify each user has: name, role (no row navigation in v1)
  6. Verify no tapping row triggers anything (no route pushed)
- **Expected Result:** ✅ Users listed with name + role, no row interaction
- **Preconditions:** Cache has app with users data
- **Regression Risk:** User list loading, data structure mapping

---

#### TC-013: Apps List — Users Tab Empty (No Users, Edge Case, US-W01 AC-5)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsUsersListModel with MockStorage
  2. MockStorage has app with 0 users
  3. Call `loadUsersForApp(appId: "app-002", accountId: "acct-001")`
  4. Verify `uiState.users` is empty
  5. **UI assertion:** Empty state shown
- **Expected Result:** ✅ Empty users list handled gracefully
- **Preconditions:** Cache has app with no users
- **Regression Risk:** Empty state handling

---

## TEST CASES (PART 2: F2 APP DETAIL)

### F2 Preconditions (all F2 test cases)
- WindowsAppCore MockStorage seeded with:
  - 1 account (id: "acct-001")
  - 1 app (id: "app-001", name: "MyApp", bundleId: "com.example", status: "Ready for Sale", version: "2.1.0", icon: url, isFavorite: false, isArchived: false)
  - App detail JSON blob with: General (Name, BundleId, Status, Version), App Store (Privacy, Accessibility, Ratings), Analytics, TestFlight
- WindowsAppDetailModel instance with MockStorage, app id, account id

---

#### TC-014: App Detail — Load & Display Header Card (Happy Path, US-W06 AC-1)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsAppDetailModel with app-001 detail cached
  2. Call `loadAppIfNeeded(appId: "app-001", accountId: "acct-001")`
  3. Verify header card contains:
     - App icon (from URL)
     - App name ("MyApp")
     - Bundle ID ("com.example")
     - Status ("Ready for Sale", with color code)
     - Version ("2.1.0")
  4. Verify `uiState.isLoading` = false
  5. **UI assertion (manual):** Header card rendered with all fields visible
- **Expected Result:** ✅ Header card fully populated with correct data
- **Preconditions:** App detail cached
- **Regression Risk:** Detail loading, card data binding

---

#### TC-015: App Detail — Sections General/App Store/Analytics/TestFlight (US-W06 AC-2)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsAppDetailModel with app-001 detail cached
  2. Verify `uiState.sections` contains 4 items:
     - "General" (App Information, App Review, History)
     - "App Store" (App Privacy, App Accessibility, Ratings and Reviews)
     - "Analytics"
     - "TestFlight"
  3. **UI assertion (manual):** All 4 sections visible in ScrollView/List
- **Expected Result:** ✅ All 4 sections displayed
- **Preconditions:** App detail cached
- **Regression Risk:** Section structure, rendering

---

#### TC-016: App Detail — Ratings & Reviews Navigation (Happy Path, US-W06 AC-3)
- **Type:** UI/Manual
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsAppDetailModel with app-001
  2. **UI:** Tap "Ratings and Reviews" option
  3. Verify navigation route pushed: `appDetail.ratingsAndReviews(appId: "app-001", bundleId: "com.example", accountId: "acct-001")`
  4. Verify WindowsRatingsReviewsModel screen loads
- **Expected Result:** ✅ Navigation to Ratings & Reviews screen
- **Preconditions:** App Detail screen displayed
- **Regression Risk:** Navigation routing, route parameters

---

#### TC-017: App Detail — All Other Options "Coming Soon" (Happy Path, US-W06 AC-3)
- **Type:** UI/Manual
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsAppDetailModel with app-001
  2. **UI:** Tap each of the following (6 options):
     - "App Information" (General section)
     - "App Review" (General section)
     - "History" (General section)
     - "App Privacy" (App Store section)
     - "App Accessibility" (App Store section)
     - "Analytics"
     - "TestFlight"
  3. For each, verify route pushed: `appDetail.comingSoon(title: "...")`
  4. **UI assertion (manual):** ComingSoon placeholder screen displays title + back button
- **Expected Result:** ✅ All 7 options (except Ratings) route to ComingSoon with appropriate title
- **Preconditions:** App Detail screen displayed
- **Regression Risk:** Navigation routing, Coming Soon placeholder

---

#### TC-018: App Detail — Coming Soon Placeholder (Verify All 7 Titles, US-W06 AC-3)
- **Type:** UI/Manual
- **Priority:** P1
- **Steps:**
  1. Navigate to each Coming Soon placeholder (7 total)
  2. Verify title displayed matches option:
     1. "App Information"
     2. "App Review"
     3. "History"
     4. "App Privacy"
     5. "App Accessibility"
     6. "Analytics"
     7. "TestFlight"
  3. Verify back button pops to App Detail
  4. **UI assertion:** All titles correct, back navigation works
- **Expected Result:** ✅ All Coming Soon screens have correct titles, back navigation works
- **Preconditions:** App Detail displayed, routes navigable
- **Regression Risk:** Route titles, back navigation

---

#### TC-019: App Detail — Platform "iOS" Tap → Coming Soon (Edge Case, US-W06 AC-4)
- **Type:** UI/Manual
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsAppDetailModel (assume platform section exists, iOS v1 hidden)
  2. **UI:** Look for "iOS" link / "See All" link (if visible)
  3. If visible, tap "iOS" or "See All" → should push `comingSoon(title: "Platforms")`
  4. **UI assertion:** ComingSoon screen shown with "Platforms" title
- **Expected Result:** ✅ Platform "iOS" / "See All" routes to Coming Soon
- **Preconditions:** Platform section visible in detail
- **Regression Risk:** Platform section routing

---

#### TC-020: App Detail — Favorite Toggle (Happy Path, US-W06 AC-5)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsAppDetailModel with app-001 (isFavorite: false)
  2. Verify favorite button state (outline/inactive)
  3. Call `toggleFavorite(appId: "app-001")`
  4. Verify `uiState.app.isFavorite` = true
  5. Verify button state changed (filled/active)
  6. Verify persisted to storage
  7. Call `toggleFavorite(appId: "app-001")` again
  8. Verify isFavorite = false, button state reverted
- **Expected Result:** ✅ Favorite toggle works, persists
- **Preconditions:** App Detail screen
- **Regression Risk:** Toggle logic, persistence

---

#### TC-021: App Detail — Archive (Pop Back to List, US-W06 AC-6)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsAppDetailModel with app-001
  2. Call `archiveApp(appId: "app-001", accountId: "acct-001")`
  3. Verify confirmation route pushed (manual UI assertion)
  4. User confirms delete
  5. Verify model calls archive API/storage
  6. Verify `uiState.app.isArchived` = true
  7. Verify navigation pops back to apps list (coordinate with parent navigation stack)
  8. **UI assertion (manual):** App Detail screen dismissed, Apps List shown
- **Expected Result:** ✅ Archive confirmed, detail screen pops back to list
- **Preconditions:** App Detail displayed
- **Regression Risk:** Archive flow, navigation coordination

---

#### TC-022: App Detail — Network Failure Fallback (Edge Case, US-W06)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsAppDetailModel with cache (detail cached)
  2. Simulate network error
  3. Call `loadAppIfNeeded(...)`
  4. Verify error caught, detail still shown from cache
  5. Verify `uiState.error` set (banner may show)
- **Expected Result:** ✅ Network error, cache fallback shown
- **Preconditions:** Detail cached, network mocked to fail
- **Regression Risk:** Error handling, cache fallback

---

(Test cases continue in next section...)

**Document saved to:** `/Users/rubensmachion/repos/Open/stack-connect/docs/refinements/2026-06-08-windows-port-test-cases.md`

Let me continue with the remaining test cases:

## TEST CASES (PART 3: F3 RATINGS & REVIEWS LIST)

### F3 Preconditions (all F3 test cases)
- WindowsAppCore MockStorage seeded with:
  - 1 app (id: "app-001", bundleId: "com.example.myapp")
  - 1 cached aggregated rating: avg=4.8, count=42308, 5-star=30000, 4-star=8000, 3-star=2000, 2-star=1000, 1-star=1308
  - 3 cached reviews (page 1): id/stars/date/title/body/nickname
  - Pagination token (opaque, mocked)
- WindowsRatingsReviewsModel with MockStorage, app id, bundleId, account id
- iTunes Lookup Service with cached rating (or mocked to return rating)

---

#### TC-023: Ratings List — Load Aggregate Rating Card (Happy Path, US-W10 AC-1)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsRatingsReviewsModel with app-001
  2. Call `loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.myapp", accountId: "acct-001")`
  3. Verify iTunes Lookup fires (or cached response returned)
  4. Verify `uiState.aggregateRating` contains:
     - Average rating: "4.8"
     - Star count (5 filled stars + fraction)
     - Total ratings: "42,308 ratings"
  5. Verify card displayed (manual UI assertion)
  6. Verify `uiState.isLoading` = false
- **Expected Result:** ✅ Aggregate rating card loaded & displayed with correct data
- **Preconditions:** iTunes Lookup returns rating
- **Regression Risk:** Rating fetching, card rendering

---

#### TC-024: Ratings List — iTunes Lookup Failure Graceful Fallback (Edge Case, US-W10 AC-1)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsRatingsReviewsModel with app-001
  2. Simulate iTunes Lookup failure (network error or invalid bundleId)
  3. Call `loadRatingsIfNeeded(...)`
  4. Verify error caught gracefully
  5. Verify `uiState.aggregateRating` = nil or empty placeholder
  6. Verify `uiState.error` set (optional message to user)
  7. Verify rest of screen (reviews list) still loads if available from cache
- **Expected Result:** ✅ iTunes Lookup failure graceful, rating card skipped/empty, reviews still shown
- **Preconditions:** iTunes Lookup mocked to fail
- **Regression Risk:** Error handling, partial data display

---

#### TC-025: Ratings List — Paginated Reviews (Page 1, Load More, US-W10 AC-2)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsRatingsReviewsModel with cached page 1 (3 reviews)
  2. Call `loadReviewsPage(appId: "app-001", accountId: "acct-001", pageToken: nil)`
  3. Verify `uiState.reviews` contains 3 items (page 1)
  4. Verify each review row shows:
     - Star rating (e.g., 5 stars)
     - Date (e.g., "June 1, 2026")
     - Title (e.g., "Great app!")
     - Body excerpt (e.g., first 100 chars + "...")
     - Nickname (e.g., "Jane_Doe")
     - Chevron (right arrow, manual UI assertion)
  5. Verify `uiState.pageToken` = opaque token for next page
  6. Verify "Load More" button visible (if more pages exist)
  7. **UI assertion (manual):** All review rows rendered correctly
- **Expected Result:** ✅ Page 1 reviews loaded & displayed with all fields
- **Preconditions:** Cached reviews exist
- **Regression Risk:** Review list structure, pagination token

---

#### TC-026: Ratings List — Load More (Next Page, US-W10 AC-2)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsRatingsReviewsModel with page 1 loaded (3 reviews, pageToken set)
  2. MockStorage has page 2 cached (2 more reviews)
  3. **UI:** Tap "Load More" button
  4. Call `loadNextPage()` with current pageToken
  5. Verify `uiState.isLoadingMore` = true (loading indicator shown, manual UI)
  6. Verify API call made with correct pageToken
  7. Verify response merged: `uiState.reviews` now has 5 items (3 + 2)
  8. Verify `uiState.pageToken` updated to next token
  9. Verify `uiState.isLoadingMore` = false
  10. If page 2 is final, "Load More" button hidden
- **Expected Result:** ✅ Load More appends next page, pagination continues, button state updates
- **Preconditions:** Page 1 loaded, page 2 available
- **Regression Risk:** Pagination append logic, button visibility, loading state

---

#### TC-027: Ratings List — Load More Button End of Pagination (Edge Case, US-W10 AC-2)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsRatingsReviewsModel with page 2 loaded (final page, pageToken = nil)
  2. Verify `uiState.pageToken` = nil (no more pages)
  3. Verify "Load More" button **not visible** (or disabled)
  4. **UI assertion (manual):** End of list reached, no pagination button shown
- **Expected Result:** ✅ Final page reached, Load More button hidden
- **Preconditions:** Final page loaded
- **Regression Risk:** Button visibility logic

---

#### TC-028: Ratings List — Tap Review Row → Review Detail (US-W10 AC-3)
- **Type:** UI/Manual
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsRatingsReviewsModel with page 1 reviews loaded
  2. **UI:** Tap first review row
  3. Verify navigation route pushed: `ratingsAndReviews.reviewDetail(reviewId: "review-001", appId: "app-001", accountId: "acct-001")`
  4. Verify WindowsReviewDetailModel screen loads
- **Expected Result:** ✅ Tap review row navigates to Review Detail
- **Preconditions:** Review list displayed
- **Regression Risk:** Row tap routing, route parameters

---

#### TC-029: Ratings List — Empty Reviews (No Reviews, Edge Case, US-W10)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsRatingsReviewsModel with app-001 (no reviews cached)
  2. Call `loadReviewsPage(...)`
  3. Verify `uiState.reviews` is empty
  4. Verify `uiState.pageToken` = nil
  5. Verify "Load More" button not visible
  6. **UI assertion (manual):** Empty state message shown (e.g., "No reviews yet")
- **Expected Result:** ✅ Empty reviews handled gracefully, empty state shown
- **Preconditions:** Cache has no reviews
- **Regression Risk:** Empty state rendering

---

#### TC-030: Ratings List — Reload Page 1 on Re-entry (Pagination State Reset, US-W10)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Load Ratings List, view page 1 (3 reviews), load page 2 (5 reviews total shown)
  2. **Navigation:** Pop route back to App Detail
  3. **Navigation:** Re-enter Ratings List screen
  4. Initialize new WindowsRatingsReviewsModel instance
  5. Call `loadReviewsPage(pageToken: nil)` → forces page 1 reload
  6. Verify `uiState.reviews` = page 1 only (3 items, not 5)
  7. Verify `uiState.pageToken` = fresh token for page 2
  8. Verify "Load More" button visible
- **Expected Result:** ✅ Re-entering Ratings List resets pagination to page 1
- **Preconditions:** Navigation allows pop/re-entry
- **Regression Risk:** Pagination state reset on screen re-entry

---

#### TC-031: Ratings List — Network Error, Fallback to Cache (Edge Case, US-W10)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsRatingsReviewsModel with cached reviews (page 1)
  2. Simulate network error
  3. Call `loadReviewsPage(...)`
  4. Verify error caught, cached reviews still displayed
  5. Verify `uiState.error` set (banner or message)
  6. Verify "Load More" disabled or hidden (network unavailable)
- **Expected Result:** ✅ Network error, cache shown, Load More disabled
- **Preconditions:** Cache exists, network mocked to fail
- **Regression Risk:** Error handling, Load More state

---

## TEST CASES (PART 4: F4 REVIEW DETAIL)

### F4 Preconditions (all F4 test cases)
- WindowsAppCore MockStorage seeded with:
  - 1 review (id: "review-001", appId: "app-001", stars: 4, date: "2026-05-15T14:30:00Z", title: "Good app", body: "Works well, minor bugs", nickname: "JohnD", territory: "US", existingReply: null)
  - 1 cached review with reply (id: "review-002", existingReply: {body: "Thanks!", date: "2026-05-16T10:00:00Z"})
- WindowsReviewDetailModel with MockStorage, review id, app id, account id
- MockSecrets with stored credentials

---

#### TC-032: Review Detail — Load & Display Full Review (Happy Path, US-W12 AC-1)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsReviewDetailModel with review-001 cached
  2. Call `loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acct-001")`
  3. Verify `uiState.review` contains:
     - Stars (4 stars, rendered visually)
     - Date + time ("May 15, 2026 at 2:30 PM")
     - Title ("Good app")
     - Full body ("Works well, minor bugs")
     - Nickname ("JohnD")
     - Territory ("US")
  4. Verify `uiState.isLoading` = false
  5. **UI assertion (manual):** Full review displayed with all fields visible
- **Expected Result:** ✅ Full review loaded & displayed
- **Preconditions:** Review cached
- **Regression Risk:** Review loading, field rendering

---

#### TC-033: Review Detail — Create Reply (First Time, Write a Reply, US-W12 AC-2)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsReviewDetailModel with review-001 (existingReply: null)
  2. Verify "Write a Reply" button visible (label indicates create mode)
  3. **UI:** Tap "Write a Reply"
  4. Verify route pushed: `reviewDetail.replyComposer(reviewId: "review-001", accountId: "acct-001", existingReplyBody: nil)`
  5. Verify WindowsReplyComposerModel screen loads
- **Expected Result:** ✅ Write Reply button routes to reply composer
- **Preconditions:** Review Detail displayed, no existing reply
- **Regression Risk:** Route pushing, label/button state

---

#### TC-034: Review Detail — Create Reply (Composer, Submit, US-W12 AC-2)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsReplyComposerModel with review-001, no existing reply
  2. **UI:** Enter text in textarea: "Thank you for the feedback!"
  3. Call `submitReply(responseBody: "Thank you for the feedback!")`
  4. Verify API call made (upsert endpoint, responseId=nil for create)
  5. Verify `uiState.isPending` = true (loading/pending state shown during submit)
  6. Mock API response: responseId="resp-001" returned
  7. Verify `uiState.isPending` = false
  8. Verify reply persisted to storage
  9. Verify navigation pops back to Review Detail
  10. Verify Review Detail now shows reply: body="Thank you for the feedback!", date=now
- **Expected Result:** ✅ Reply created, pending state shown, popped back to detail with reply displayed
- **Preconditions:** Composer screen displayed
- **Regression Risk:** Reply submission, pending state, navigation pop

---

#### TC-035: Review Detail — Edit Reply (Second Time, Edit Reply Label, US-W12 AC-2)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsReviewDetailModel with review-002 (existingReply: {body: "Thanks!", date: "2026-05-16..."})
  2. Verify reply displayed in detail
  3. Verify "Edit Reply" button visible (label indicates edit mode, different from "Write a Reply")
  4. **UI:** Tap "Edit Reply"
  5. Verify route pushed: `reviewDetail.replyComposer(reviewId: "review-002", accountId: "acct-001", existingReplyBody: "Thanks!")`
  6. Verify composer loads with existing reply text populated in textarea
- **Expected Result:** ✅ Edit Reply button shows, routes to composer with existing reply body
- **Preconditions:** Review has existing reply
- **Regression Risk:** Button label, existing reply population

---

#### TC-036: Review Detail — Edit Reply (Composer, Update, US-W12 AC-2)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsReplyComposerModel with review-002, existingReplyBody: "Thanks!"
  2. Verify textarea populated with "Thanks!"
  3. **UI:** Clear and enter new text: "Thanks a lot for your patience!"
  4. Call `submitReply(responseBody: "Thanks a lot for your patience!")`
  5. Verify API call made (upsert endpoint, responseId="resp-002" — same reply being updated)
  6. Verify `uiState.isPending` = true
  7. Mock API response: updated reply returned
  8. Verify `uiState.isPending` = false
  9. Verify reply updated in storage
  10. Verify navigation pops back to Review Detail
  11. Verify Review Detail shows updated reply: body="Thanks a lot for your patience!"
- **Expected Result:** ✅ Reply updated, pending state shown, popped back with updated reply
- **Preconditions:** Composer screen with existing reply
- **Regression Risk:** Reply update, pending state, navigation

---

#### TC-037: Review Detail — Delete Reply (Confirmation, US-W12 AC-3)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsReviewDetailModel with review-002 (has reply)
  2. Verify "Delete Reply" button visible
  3. **UI:** Tap "Delete Reply"
  4. Verify route pushed: `reviewDetail.deleteReplyConfirm(reviewId: "review-002", responseId: "resp-002", accountId: "acct-001")`
  5. Verify delete confirmation screen displayed (manual UI assertion)
  6. Confirmation text shown: "Are you sure you want to delete this reply?"
- **Expected Result:** ✅ Delete button routes to confirmation screen
- **Preconditions:** Review has reply, detail displayed
- **Regression Risk:** Delete routing, confirmation screen

---

#### TC-038: Review Detail — Delete Reply Confirmation (Confirm Delete, US-W12 AC-3)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. WindowsDeleteReplyConfirmModel loaded with review-002, responseId: "resp-002"
  2. **UI:** Tap "Delete" / "Confirm" button
  3. Call `deleteReplyConfirmed()`
  4. Verify `uiState.isPending` = true (delete in progress)
  5. Mock API response: deletion successful
  6. Verify `uiState.isPending` = false
  7. Verify reply deleted from storage
  8. Verify navigation pops back to Review Detail (through confirmation screen)
  9. Verify Review Detail no longer shows reply (existingReply: null)
  10. Verify "Write a Reply" button visible again
- **Expected Result:** ✅ Reply deleted, pending shown, popped back to detail without reply
- **Preconditions:** Confirmation screen displayed
- **Regression Risk:** Delete API call, pending state, navigation pop-to-parent

---

#### TC-039: Review Detail — Delete Reply Confirmation Cancel (US-W12 AC-3)
- **Type:** UI/Manual
- **Priority:** P1
- **Steps:**
  1. WindowsDeleteReplyConfirmModel displayed
  2. **UI:** Tap "Cancel" button or pop route
  3. Verify navigation pops back to Review Detail
  4. Verify reply still exists in storage
  5. Verify reply still displayed in detail
- **Expected Result:** ✅ Cancel aborts delete, reply remains
- **Preconditions:** Confirmation screen displayed
- **Regression Risk:** Cancel logic, route pop

---

#### TC-040: Review Detail — Copy Reply to Clipboard (Windows, US-W12 AC-4)
- **Type:** Manual / Platform-specific
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsReviewDetailModel with review-001 (or any review)
  2. Verify "Copy" button visible (or option in context menu)
  3. **Windows device:** Tap "Copy" button
  4. Mock WindowsClipboard.setText(reviewText) returns true
  5. Verify `uiState.clipboardMessage` = "Copied!" (or banner shown, manual UI assertion)
  6. Verify system clipboard contains full review text (manual verification on Windows)
  7. Wait 2-3 seconds, verify banner auto-dismisses
- **Expected Result:** ✅ Copy button copies review text to clipboard, "Copied!" shown
- **Preconditions:** Windows device (or mock clipboard)
- **Regression Risk:** Clipboard API, banner display/dismiss

---

#### TC-041: Review Detail — Copy Reply to Clipboard (macOS Host Fallback, US-W12 AC-4)
- **Type:** Manual / Platform-specific
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsReviewDetailModel on macOS host
  2. **UI:** Tap "Copy" button
  3. Verify WindowsClipboard.setText(...) called, returns false (macOS unsupported)
  4. Verify `uiState.clipboardMessage` = "Clipboard not available on this host" (graceful fallback)
  5. Verify no crash, error handled gracefully
- **Expected Result:** ✅ Copy gracefully handles macOS host, no clipboard support message shown
- **Preconditions:** macOS host, WindowsClipboard returns false
- **Regression Risk:** Platform-specific error handling

---

#### TC-042: Review Detail — Network Error Fallback (Edge Case, US-W12)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsReviewDetailModel with cached review
  2. Simulate network error
  3. Call `loadReviewIfNeeded(...)`
  4. Verify cached review still displayed
  5. Verify error banner shown
- **Expected Result:** ✅ Network error, cache fallback shown
- **Preconditions:** Review cached, network mocked to fail
- **Regression Risk:** Error handling, cache fallback

---

#### TC-043: Review Detail — Reply Create API Error (Edge Case, US-W12 AC-2)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsReplyComposerModel with review-001
  2. **UI:** Enter reply text: "Test reply"
  3. Simulate API error (500 or 400 Bad Request)
  4. Call `submitReply(...)`
  5. Verify `uiState.isPending` = true initially
  6. Verify error caught, `uiState.isPending` = false
  7. Verify `uiState.error` set (error message shown, manual UI assertion)
  8. Verify reply **not** submitted to storage
  9. Verify navigation **does not pop** (user can edit/retry)
- **Expected Result:** ✅ API error handled, message shown, composer stays open for retry
- **Preconditions:** Composer displayed, API mocked to fail
- **Regression Risk:** Error handling, composer state

---

#### TC-044: Review Detail — Reply Delete API Error (Edge Case, US-W12 AC-3)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. WindowsDeleteReplyConfirmModel displayed
  2. Simulate API error (500 or 403 Forbidden)
  3. Call `deleteReplyConfirmed()`
  4. Verify `uiState.isPending` = true, then false after error
  5. Verify error shown to user
  6. Verify reply **not** deleted from storage
  7. Verify navigation **does not pop** (can retry)
- **Expected Result:** ✅ Delete error handled, message shown, confirmation stays open
- **Preconditions:** Confirmation displayed, API mocked to fail
- **Regression Risk:** Error handling, confirmation state

---

## TEST CASES (PART 5: F5 RECENT REVIEWS WIDGET)

### F5 Preconditions (all F5 test cases)
- WindowsAppCore MockStorage seeded with:
  - 3 accounts (acct-001, acct-002, acct-003)
  - 2 apps under acct-001 (app-001, app-002), 1 app under acct-002 (app-003), 1 app under acct-003 (app-004)
  - 5 recent reviews cached (5 total across all accounts, sorted by date descending):
    - review-A (acct-001, app-001, date: 2026-06-07 10:00)
    - review-B (acct-001, app-002, date: 2026-06-07 09:00)
    - review-C (acct-002, app-003, date: 2026-06-06 20:00)
    - review-D (acct-003, app-004, date: 2026-06-06 18:00)
    - review-E (acct-001, app-001, date: 2026-06-05 15:00)
  - Cache timestamps for each review (TTL ~1 hour assumed)
- WindowsHomeModel + WindowsRecentReviewsWidgetModel with MockStorage, all 3 accounts loaded
- iTunes Lookup Service mocked (for review ratings)

---

#### TC-045: Recent Reviews Widget — Load & Display Up to 5 Reviews (Happy Path, US-W15 AC-1)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsRecentReviewsWidgetModel with all 3 accounts
  2. Call `loadRecentReviewsAggregated(accountIds: ["acct-001", "acct-002", "acct-003"])`
  3. Verify API calls made to fetch latest reviews from all accounts
  4. Mock responses: 5 reviews aggregated
  5. Verify `uiState.reviews` sorted by date descending (review-A first, review-E last)
  6. Verify exactly 5 reviews in list (capped at 5, not 6+)
  7. **UI assertion (manual):** Widget displays 5 rows with stars, date, title excerpt, nickname, chevron
- **Expected Result:** ✅ Up to 5 reviews loaded, sorted by date desc, displayed
- **Preconditions:** All 3 accounts have cached reviews
- **Regression Risk:** Multi-account aggregation, review sorting, cap at 5

---

#### TC-046: Recent Reviews Widget — Count Badge (US-W15 AC-2)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsRecentReviewsWidgetModel with 5 reviews
  2. Verify widget header shows badge: "(5)" or similar indicator
  3. Update MockStorage to add 1 more review (6 total)
  4. Call `refresh()`
  5. Verify badge updates to "(5)" (still capped)
  6. Update to 2 reviews
  7. Verify badge shows "(2)"
  8. **UI assertion (manual):** Badge rendered and updated correctly
- **Expected Result:** ✅ Count badge shows number of reviews (capped at 5)
- **Preconditions:** Widget displayed
- **Regression Risk:** Badge rendering, count accuracy

---

#### TC-047: Recent Reviews Widget — Tap Review Row → Review Detail (US-W15 AC-3)
- **Type:** UI/Manual
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsRecentReviewsWidgetModel with 5 reviews
  2. **UI:** Tap third review row (review-C)
  3. Verify navigation route pushed: `home.reviewDetail(reviewId: "review-C", appId: "app-003", accountId: "acct-002")`
  4. Verify WindowsReviewDetailModel screen loads with correct app/account context
  5. Verify review detail populated with review-C data
- **Expected Result:** ✅ Tap review routes to Review Detail with correct app/account
- **Preconditions:** Widget displayed, reviews loaded
- **Regression Risk:** Row tap routing, route parameters

---

#### TC-048: Recent Reviews Widget — "See More" Link (US-W15 AC-3)
- **Type:** UI/Manual
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsRecentReviewsWidgetModel with 5 reviews
  2. Verify "See More" link visible below reviews (or next to count badge)
  3. **UI:** Tap "See More"
  4. Verify navigation route pushed: `home.ratingsAndReviews(appId: <app-of-first-review>, bundleId: <...>, accountId: <acct-of-first-review>)`
  5. Verify Ratings & Reviews screen loads for the first review's app (review-A → app-001, acct-001)
  6. Verify paged reviews shown (page 1)
- **Expected Result:** ✅ See More routes to Ratings & Reviews of first review's app
- **Preconditions:** Widget displayed
- **Regression Risk:** Link routing, route parameters

---

#### TC-049: Recent Reviews Widget — Auto-Refresh on Home Load (US-W15 AC-4)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsHomeModel with all accounts
  2. Call `loadHomeWidgets()`
  3. Verify WindowsRecentReviewsWidgetModel.loadRecentReviewsAggregated(...) called automatically
  4. Verify API calls fire to fetch latest reviews
  5. Verify widget data refreshed in `uiState.recentReviews`
- **Expected Result:** ✅ Widget auto-refreshes on Home load
- **Preconditions:** Home screen loading
- **Regression Risk:** Auto-refresh trigger, widget lifecycle

---

#### TC-050: Recent Reviews Widget — Manual Refresh Button (US-W15 AC-4)
- **Type:** UI/Manual
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsHomeModel with widget displayed
  2. **UI:** Tap "Refresh" button on widget (or Home's global refresh)
  3. Verify `uiState.isRefreshing` = true (loading indicator shown)
  4. Verify API calls made to fetch fresh reviews
  5. Verify widget data updated
  6. Verify `uiState.isRefreshing` = false (loading indicator dismissed)
- **Expected Result:** ✅ Manual refresh fetches latest reviews, loading indicator shown/hidden
- **Preconditions:** Widget displayed, Home screen
- **Regression Risk:** Refresh trigger, loading state

---

#### TC-051: Recent Reviews Widget — Empty State (No Reviews, Edge Case, US-W15)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsRecentReviewsWidgetModel with all 3 accounts (no reviews cached)
  2. Call `loadRecentReviewsAggregated(...)`
  3. Verify API returns 0 reviews (or errors)
  4. Verify `uiState.reviews` is empty
  5. Verify `uiState.isEmpty` = true
  6. **UI assertion (manual):** Empty state message shown (e.g., "No recent reviews")
  7. Verify "See More" link still visible (optional)
  8. Verify count badge shows "(0)" or hidden
- **Expected Result:** ✅ Empty reviews handled gracefully, empty state shown
- **Preconditions:** No reviews cached, all accounts synced
- **Regression Risk:** Empty state rendering

---

#### TC-052: Recent Reviews Widget — Network Error Fallback (Cached Data, US-W15 AC-5)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsRecentReviewsWidgetModel with previously cached reviews (5 items)
  2. Simulate network error (all accounts offline)
  3. Call `loadRecentReviewsAggregated(...)` or `refresh()`
  4. Verify error caught gracefully
  5. Verify `uiState.reviews` still shows cached 5 reviews
  6. Verify `uiState.error` = error message (e.g., "Unable to refresh, showing cached reviews")
  7. Verify `uiState.isRefreshing` = false
  8. **UI assertion (manual):** Cached reviews displayed with error banner
- **Expected Result:** ✅ Network error, cached reviews shown, error banner displayed
- **Preconditions:** Cache exists, network mocked to fail
- **Regression Risk:** Error handling, cache fallback, banner state

---

#### TC-053: Recent Reviews Widget — Multi-Account Aggregation > 5 (Cap at 5, US-W15 AC-1)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsRecentReviewsWidgetModel with 3 accounts
  2. MockStorage seeded with 8 recent reviews total (acct-001: 4, acct-002: 2, acct-003: 2)
  3. Call `loadRecentReviewsAggregated(...)`
  4. Verify API returns 8 reviews aggregated
  5. Verify `uiState.reviews` sorted by date descending
  6. Verify **only top 5** reviews shown (6th–8th hidden)
  7. Verify count badge shows "(5)"
  8. Verify 6th review (oldest of top 8) **not displayed**
- **Expected Result:** ✅ Widget caps at 5 reviews, oldest beyond 5 hidden
- **Preconditions:** Multiple accounts with many reviews
- **Regression Risk:** Capping logic, sorting accuracy

---

#### TC-054: Recent Reviews Widget — Sort by Date Descending (Latest First, US-W15 AC-1)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsRecentReviewsWidgetModel with 5 reviews out of chronological order in cache
  2. Mock API response with reviews in random order:
     - review-1: 2026-06-05
     - review-2: 2026-06-07
     - review-3: 2026-06-06
     - review-4: 2026-06-04
     - review-5: 2026-06-08
  3. Call `loadRecentReviewsAggregated(...)`
  4. Verify `uiState.reviews` sorted: review-5 (June 8) first, review-4 (June 4) last
  5. **UI assertion (manual):** Reviews displayed top-to-bottom by date (latest first)
- **Expected Result:** ✅ Reviews sorted by date descending, latest first
- **Preconditions:** Mixed-order reviews in API response
- **Regression Risk:** Sorting algorithm

---

#### TC-055: Recent Reviews Widget — Cached TTL Expiration (Refresh on Load, Edge Case, US-W15 AC-4)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsRecentReviewsWidgetModel with cached reviews (timestamp: 1 hour old)
  2. Assume TTL = 1 hour (cache expires after 1 hour)
  3. Call `loadRecentReviewsAggregated(...)` with current time > cache timestamp + 1 hour
  4. Verify cache detected as stale
  5. Verify API called to fetch fresh reviews (not returned from cache)
  6. Verify fresh reviews loaded into `uiState.reviews`
  7. Verify cache timestamp updated
- **Expected Result:** ✅ Expired cache refreshed on load
- **Preconditions:** Cached data with old timestamp, TTL logic implemented
- **Regression Risk:** TTL calculation, cache invalidation

---

## CROSS-FEATURE: ACCOUNT INTEGRATION & STATE MANAGEMENT

#### TC-056: Re-import .scexport Merge (Preserve isFavorite/isArchived, US-W31 equivalent)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initial state: Account "acct-001" with 5 apps, 2 Favorites (app-001, app-003), 1 archived (app-005)
  2. Export account state to .scexport file (via iOS or export API)
  3. Simulate re-import: load .scexport into WindowsImportAccountModel
  4. Parse account data: 5 apps (same as before, but re-import treats as fresh merge)
  5. Call `importAccount(...)` with merge strategy
  6. Verify:
     - All 5 apps present in cache
     - app-001 **still marked Favorite** (local flag preserved)
     - app-003 **still marked Favorite**
     - app-005 **still marked archived**
     - New apps (if any in .scexport) added without local flags set
  7. Verify storage updated with merged state
- **Expected Result:** ✅ Re-import merges data, preserves local isFavorite/isArchived flags
- **Preconditions:** Account previously imported, .scexport available
- **Regression Risk:** Import merge logic, flag preservation

---

#### TC-057: Favorite Persistence Across App Restart (Simulated, US-W01 AC-4, US-W06 AC-5)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsAppsListModel, load app-001 (isFavorite: false)
  2. Call `toggleFavorite(appId: "app-001")` → isFavorite: true
  3. Verify persisted to MockStorage
  4. **Simulate restart:** Destroy model, create new WindowsAppsListModel instance
  5. Load cache, verify app-001 still isFavorite: true
  6. Toggle again → isFavorite: false
  7. **Restart again**, verify isFavorite: false
- **Expected Result:** ✅ Favorite toggles persist across model restart (app restart)
- **Preconditions:** MockStorage persistent across model instances
- **Regression Risk:** Persistence layer, model initialization

---

#### TC-058: Archive Persistence Across App Restart (Simulated, US-W01 AC-5)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize WindowsAppsListModel, load 5 apps (none archived)
  2. Call `archiveApp(appId: "app-004")` → confirmation, confirm delete
  3. Verify app-004 removed from `uiState.apps` (4 items)
  4. Verify isArchived=true persisted
  5. **Simulate restart:** Create new WindowsAppsListModel instance
  6. Load cache, verify `uiState.apps` = 4 items (app-004 not included)
  7. Load archived apps screen, verify app-004 shown in archived list
- **Expected Result:** ✅ Archive toggles persist across model restart
- **Preconditions:** MockStorage persistent
- **Regression Risk:** Archive persistence

---

## EDGE CASES: NEGATIVE SCENARIOS & BOUNDARY CONDITIONS

#### TC-059: Empty Account (No Apps, All Screens, Edge Case)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Create account with 0 apps
  2. Initialize WindowsAppsListModel
  3. Call `loadAppsIfNeeded(accountId: "empty-acct")`
  4. Verify `uiState.apps` is empty
  5. Verify Favorites tab shows empty
  6. Verify Users tab shows empty (or N/A)
  7. Verify "See All Apps" / "Browse Store" placeholder shown (if applicable)
- **Expected Result:** ✅ Empty account handled gracefully across all screens
- **Preconditions:** Empty account in cache
- **Regression Risk:** Empty state handling

---

#### TC-060: API Timeout (Slow Network, US-W01/W10, Edge Case)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize WindowsAppsListModel with cache
  2. Simulate network timeout (>30s delay)
  3. Call `loadAppsIfNeeded(...)`
  4. Verify request times out (after ~10-30s threshold)
  5. Verify error caught, `uiState.error` set
  6. Verify cached apps still displayed
  7. Verify `uiState.isLoading` = false
- **Expected Result:** ✅ Timeout handled, cache shown, error displayed
- **Preconditions:** Network mocked to timeout
- **Regression Risk:** Timeout handling, error state

---

#### TC-061: API 500 Error (Server Error, US-W01/W10/W12, Edge Case)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Initialize model with cache
  2. Simulate API 500 error
  3. Call load/refresh
  4. Verify error caught, `uiState.error` = "Server error" or similar
  5. Verify cache still shown
  6. **UI assertion:** Error banner displayed
- **Expected Result:** ✅ 500 error handled, cache shown, user notified
- **Preconditions:** API mocked to return 500
- **Regression Risk:** Error handling

---

#### TC-062: API 401 Unauthorized (Expired Credentials, Edge Case)
- **Type:** Integration
- **Priority:** P0
- **Steps:**
  1. Initialize model with cached data
  2. Store credentials in MockSecrets (mocked expired)
  3. Simulate API 401 Unauthorized
  4. Call load/refresh
  5. Verify error caught
  6. Verify `uiState.error` indicates auth failure
  7. **UI assertion (manual):** User prompted to re-authenticate (route to login, if applicable)
- **Expected Result:** ✅ 401 handled, user redirected to login
- **Preconditions:** API returns 401
- **Regression Risk:** Auth error handling, login redirect

---

#### TC-063: Search with Special Characters (Boundary, US-W01 AC-3)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Cache has app with bundleId: "com.example.app@2.0"
  2. Call `setSearchQuery("@2")`
  3. Verify app found (special char search works)
  4. Call `setSearchQuery("com..example")` (double dot)
  5. Verify no match (or gracefully handled)
  6. Call `setSearchQuery("")` → reset
- **Expected Result:** ✅ Special char search handled safely
- **Preconditions:** Cache has special char bundleId
- **Regression Risk:** Search algorithm, string handling

---

#### TC-064: Long Review Title & Body (Text Overflow, Boundary, US-W10/W12)
- **Type:** UI/Manual
- **Priority:** P1
- **Steps:**
  1. Mock review with:
     - Title: 200+ characters
     - Body: 5000+ characters
  2. Load review detail
  3. **UI assertion (manual):** Title truncated or wrapped, readable
  4. **UI assertion:** Body displayed in scrollable container, no layout break
  5. Verify excerpt in list shows "..." after ~100 chars
- **Expected Result:** ✅ Long text handled gracefully, no layout breaks
- **Preconditions:** Review with long text
- **Regression Risk:** Text truncation, layout constraints

---

#### TC-065: Nickname with Emoji & Unicode (Boundary, US-W10/W12)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Mock review with nickname: "User👍😂 / 用户"
  2. Load review
  3. Verify nickname displayed correctly (emoji + unicode rendered)
  4. Verify no parsing errors
- **Expected Result:** ✅ Emoji & unicode handled correctly
- **Preconditions:** Review with emoji/unicode nickname
- **Regression Risk:** Text encoding, rendering

---

#### TC-066: Very Old Review Date (Boundary, US-W10/W12)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Mock review with date: 2012-01-01 (very old)
  2. Load review list
  3. Verify date formatted correctly: "January 1, 2012" (or relative format)
  4. **UI assertion:** Date rendered without errors
- **Expected Result:** ✅ Old date handled, formatted correctly
- **Preconditions:** Review with old date
- **Regression Risk:** Date formatting

---

#### TC-067: Future Date (Current Date > Review Date + 1 year, Boundary)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Mock review with date: 2027-01-01 (future, if current date < that)
  2. Load review
  3. Verify date formatted (even if future)
  4. **UI assertion:** No errors, graceful handling
- **Expected Result:** ✅ Future date handled gracefully
- **Preconditions:** Review with future date (mocked)
- **Regression Risk:** Date comparison, formatting

---

## PLATFORM-SPECIFIC: SWIFTCROSSUI CONSTRAINTS

#### TC-068: No Sheets — Composers as Pushed Routes (Architecture Constraint, US-W12/W14)
- **Type:** UI/Manual
- **Priority:** P0
- **Steps:**
  1. Tap "Write a Reply" on Review Detail
  2. **Verify:** Composer pushed as new route (not modal sheet)
  3. **Verify:** Back/pop navigation returns to Review Detail
  4. Verify no SwiftUI `.sheet()` syntax used (SwiftCrossUI limitation)
- **Expected Result:** ✅ Composer is pushed route, not sheet
- **Preconditions:** Review Detail displayed
- **Regression Risk:** SwiftCrossUI architecture

---

#### TC-069: No Swipe to Archive — Explicit Button (Architecture Constraint, US-W01 AC-5)
- **Type:** UI/Manual
- **Priority:** P0
- **Steps:**
  1. **UI:** Attempt swipe-left on app row (native iOS pattern)
  2. **Verify:** No swipe action triggered (SwiftCrossUI limitation)
  3. Verify explicit "Archive" button visible on app row (or long-press context menu, if implemented)
  4. Tap "Archive" button
  5. Verify archive flow initiated
- **Expected Result:** ✅ No swipe, explicit button for archive
- **Preconditions:** Apps list displayed
- **Regression Risk:** SwiftCrossUI constraints

---

#### TC-070: No Pull-to-Refresh — Explicit Refresh Button (Architecture Constraint, US-W01/W10/W15)
- **Type:** UI/Manual
- **Priority:** P0
- **Steps:**
  1. **UI:** Attempt pull-down on list (native iOS pattern)
  2. **Verify:** No pull-to-refresh triggered (SwiftCrossUI limitation)
  3. Verify explicit "Refresh" button visible (top of screen or in toolbar)
  4. Tap "Refresh" button
  5. Verify sync/refresh initiated
- **Expected Result:** ✅ No pull-to-refresh, explicit button
- **Preconditions:** List/widget screen
- **Regression Risk:** SwiftCrossUI constraints

---

#### TC-071: Pagination Load More Button (Not Infinite Scroll, Architecture Constraint, US-W10 AC-2)
- **Type:** UI/Manual
- **Priority:** P0
- **Steps:**
  1. Load Ratings & Reviews list (page 1, 3 reviews visible)
  2. **Verify:** No automatic infinite scroll when scrolling to bottom
  3. Verify explicit "Load More" button visible at bottom of list
  4. Tap "Load More"
  5. Verify page 2 appended to list
- **Expected Result:** ✅ Load More button, not infinite scroll
- **Preconditions:** Reviews list with pagination
- **Regression Risk:** SwiftCrossUI constraints

---

#### TC-072: No Alerts/Sheets — Confirmation as Pushed Route (Architecture Constraint, US-W01/W12)
- **Type:** UI/Manual
- **Priority:** P0
- **Steps:**
  1. Tap "Archive" app → should show confirmation
  2. **Verify:** Confirmation pushed as new route (not alert dialog)
  3. Verify back/pop dismisses confirmation
  4. Verify "Confirm" button executes action on that route
- **Expected Result:** ✅ Confirmation is pushed route, not alert
- **Preconditions:** Archive or delete action triggered
- **Regression Risk:** SwiftCrossUI constraints

---

#### TC-073: Clipboard Windows-only (Returns False on macOS Host, US-W12 AC-4)
- **Type:** Platform-specific, Manual
- **Priority:** P1
- **Steps:**
  1. On Windows device: Tap "Copy" on review
  2. Verify WindowsClipboard.setText(...) returns true
  3. Verify "Copied!" confirmation shown
  4. On macOS host (if app runs there): Tap "Copy"
  5. Verify WindowsClipboard.setText(...) returns false
  6. Verify graceful error message shown (no crash)
- **Expected Result:** ✅ Clipboard works on Windows, handles false gracefully on macOS
- **Preconditions:** Cross-platform testing
- **Regression Risk:** Platform-specific clipboard

---

## REGRESSION & CROSS-FEATURE SCENARIOS

#### TC-074: Navigation Stack Consistency (Push/Pop, Multi-level Routes, Edge Case)
- **Type:** UI/Manual
- **Priority:** P1
- **Steps:**
  1. Start at Home screen
  2. Tap account → Apps List
  3. Tap app → App Detail
  4. Tap "Ratings and Reviews" → Ratings List
  5. Tap review → Review Detail
  6. Tap "See All Reviews" → back to Ratings List
  7. Pop back → Review Detail should show (or close if modal)
  8. Pop back → Ratings List
  9. Pop back → App Detail
  10. Pop back → Apps List
  11. Verify each level correct, no state corruption
- **Expected Result:** ✅ Navigation stack consistent, state preserved across levels
- **Preconditions:** All screens accessible
- **Regression Risk:** Navigation stack management, state coordination

---

#### TC-075: Model State After Navigation Pop (Review Detail ← Reply Composer, US-W12 AC-2)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Load Review Detail with review-001 (no reply)
  2. Tap "Write a Reply" → push replyComposer route
  3. User enters reply text, submits
  4. API returns: responseId="resp-001", reply stored
  5. Composer pops back to Review Detail
  6. Verify Review Detail model's `uiState.review.existingReply` updated to show new reply
  7. Verify "Write a Reply" changed to "Edit Reply"
- **Expected Result:** ✅ Popped screen reflects changes from child screen
- **Preconditions:** Reply submitted successfully
- **Regression Risk:** State sync between parent/child screens, pop coordination

---

#### TC-076: Multi-Account Badge/Count Accuracy (Recent Reviews Widget, US-W15 AC-2)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Load Home with 3 accounts, each with cached reviews:
     - acct-001: 2 reviews
     - acct-002: 1 review
     - acct-003: 3 reviews
  2. Total: 6 reviews (but capped at 5 in widget)
  3. Verify count badge shows "(5)" not "(6)"
  4. Update MockStorage: remove 1 review from acct-001
  5. Call refresh
  6. Verify badge updates to "(4)"
  7. Verify count matches displayed items
- **Expected Result:** ✅ Badge count accurate (capped at 5)
- **Preconditions:** Multi-account aggregation
- **Regression Risk:** Count calculation, capping logic

---

#### TC-077: App Detail Favorite & Archive Together (State Consistency, US-W06)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Load App Detail with app-001 (isFavorite: false, isArchived: false)
  2. Toggle Favorite → isFavorite: true
  3. Verify button state, persisted
  4. Archive app → confirmation, confirm
  5. App archived, detail pops
  6. Re-enter app (if still cached): verify isFavorite still true (not lost during archive)
  7. Load archived apps screen: verify app-001 shown, isFavorite still true
- **Expected Result:** ✅ Favorite flag preserved during archive
- **Preconditions:** App Detail displayed
- **Regression Risk:** State isolation, archive logic

---

## DATA MODEL & ENCODING VALIDATION

#### TC-078: Search Filter Logic Case-Insensitive, Substring Match (Unit, US-W01 AC-3)
- **Type:** Unit
- **Priority:** P1
- **Steps:**
  1. Test helper function: `appMatchesSearch(app, query)`
  2. Query: "FOO" (uppercase)
  3. App name: "Foobar" → should match
  4. Query: "oobar" (substring)
  5. App name: "Foobar" → should match
  6. Query: "baz"
  7. App name: "Foobar" → should NOT match
- **Expected Result:** ✅ Search logic case-insensitive, substring matching
- **Preconditions:** Search function isolated, unit testable
- **Regression Risk:** Search algorithm

---

#### TC-079: iTunes Lookup computeWeightedAverage (Unit, US-W10 AC-1)
- **Type:** Unit
- **Priority:** P0
- **Steps:**
  1. Test iTunesLookupService.computeWeightedAverage(ratings: [5: 30k, 4: 8k, 3: 2k, 2: 1k, 1: 1.3k])
  2. Expected: (5*30k + 4*8k + 3*2k + 2*1k + 1*1.3k) / (30k+8k+2k+1k+1.3k) ≈ 4.8
  3. Verify calculation ±0.01
- **Expected Result:** ✅ Weighted average calculated correctly
- **Preconditions:** Pure function, unit testable
- **Regression Risk:** Rating calculation accuracy

---

#### TC-080: Review Pagination Token Opaque (State Lost on Exit, US-W10, Edge Case)
- **Type:** Integration
- **Priority:** P1
- **Steps:**
  1. Load Ratings List page 1, pagination token: "opaque-token-abc123"
  2. Navigate to Review Detail
  3. Pop back to Ratings List (creates new model instance)
  4. Verify `uiState.pageToken` = nil (state lost, not persisted)
  5. Call `loadReviewsPage(pageToken: nil)` → reloads page 1 (not page 2)
  6. Verify pagination resets
- **Expected Result:** ✅ Pagination token lost on exit, page 1 reloaded on re-entry
- **Preconditions:** Pagination token opaque, not persisted in storage
- **Regression Risk:** Pagination state, model re-initialization

---

## COVERAGE MATRIX: USER STORIES ↔ TEST CASES

| User Story | Acceptance Criteria | Test Cases | Status |
|------------|-------------------|-----------|--------|
| US-W01: Apps List — Load & Cache | AC-1: Load from cache | TC-001, TC-010 | Happy path + edge case |
| | AC-2: Live sync updates | TC-002, TC-011 | Happy path + error fallback |
| US-W02: Search | AC-3: Search by name/bundleId, independent filters | TC-003, TC-004, TC-005 | Happy path + no-match + boundary |
| US-W03: Favorites | AC-4: Toggle favorite, persist across restart | TC-006, TC-057 | Happy path + restart simulation |
| US-W04: Archive | AC-5: Archive with confirmation, Archived Apps screen, Restore | TC-007, TC-008, TC-009 | Happy path + cancel + restore |
| US-W05: Users Tab | AC-5: Users list (name + role, no navigation) | TC-012, TC-013 | Happy path + empty |
| US-W06: App Detail — Header | AC-1: Display header card | TC-014 | Happy path |
| US-W07: App Detail — Sections | AC-2: Show 4 sections | TC-015 | Happy path |
| US-W08: Detail Navigation | AC-3: Ratings navigates, others "Coming Soon" | TC-016, TC-017, TC-018, TC-019 | Happy path + all 7 placeholders |
| US-W09: Detail Favorite & Archive | AC-5, AC-6: Favorite + Archive with pop | TC-020, TC-021 | Happy path + pop-back |
| US-W10: Ratings & Reviews | AC-1: Aggregate rating card + iTunes Lookup | TC-023, TC-024 | Happy path + error fallback |
| | AC-2: Paginated reviews + Load More | TC-025, TC-026, TC-027, TC-030 | Happy path + final page + reload on re-entry |
| | AC-3: Tap review → Review Detail | TC-028 | Happy path |
| US-W11: Ratings Empty/Error | — | TC-029, TC-031 | Edge cases |
| US-W12: Review Detail — Full Review & Reply Create | AC-1: Load full review | TC-032 | Happy path |
| | AC-2: Write Reply (create mode) | TC-033, TC-034 | Happy path + composer submit |
| | AC-2: Edit Reply (edit mode) | TC-035, TC-036 | Happy path + label + composer update |
| US-W13: Reply Delete | AC-3: Delete confirmation | TC-037, TC-038, TC-039 | Happy path + confirm + cancel |
| US-W14: Copy to Clipboard | AC-4: Copy with "Copied!" confirmation | TC-040, TC-041 | Windows + macOS fallback |
| US-W15: Recent Reviews Widget — Load | AC-1: Load up to 5, aggregated | TC-045, TC-053, TC-054 | Happy path + cap-at-5 + sorting |
| | AC-2: Count badge | TC-046 | Happy path |
| US-W16: Recent Reviews Navigation | AC-3: Tap row → Detail, See More → Ratings List | TC-047, TC-048 | Happy path + See More |
| US-W17: Recent Reviews Refresh | AC-4: Auto-refresh on Home load + manual refresh | TC-049, TC-050 | Happy path + manual |
| | AC-5: Empty/error states with cache fallback | TC-051, TC-052 | Edge cases |

---

## SUMMARY OF AUTOMATABLE VS MANUAL TESTS

### Automatable (Unit/Integration, WindowsAppCore test suite)
- TC-001..TC-055 (logic + state validation, except UI assertions marked manual)
- TC-056..TC-080 (data validation, unit/integration)
- **Total automatable:** ~60 test cases (logic + state)

### Manual/UI-Only (SwiftCrossUI Rendering, Navigation, Visual)
- TC-016, TC-017, TC-018, TC-019 (Coming Soon placeholder, routing verification)
- TC-027 (Load More button visibility, pagination UI)
- Parts of TC-045..TC-055 (visual rendering, badge, layout)
- TC-068..TC-072 (SwiftCrossUI constraints, navigation patterns)
- TC-074 (multi-level navigation stack consistency)
- **Total manual:** ~25 test cases (UI/rendering/navigation)

---

## NOTES FOR TEST EXECUTION

### Phase 1: Unit Tests (WindowsAppCore)
Run the full unit/integration suite:
```bash
swift test --package StackConnectWindowsApp --test-product WindowsAppCoreTests
```

Expected: All 60 automatable tests pass.

### Phase 2: Manual/UI Verification
- Deploy app to Windows device (via WinUI backend)
- Follow manual test steps for TC-016..TC-019, TC-068..TC-072
- Verify SwiftCrossUI-specific constraints (no sheets, no swipe, no pull-to-refresh, etc.)
- Validate clipboard behavior on Windows vs. macOS host

### Phase 3: Integration on VM
- Run complete end-to-end flow: create account → apps list → detail → ratings → review detail → reply create/edit/delete
- Verify Recent Reviews widget on Home
- Test navigation push/pop consistency, state preservation
- Validate error handling (network offline, API 500, 401, timeout)

---

## CRITICAL PATHS (Priority P0 tests)

These must pass for feature sign-off:

1. **TC-001, TC-002:** Apps list load & sync
2. **TC-006:** Favorite persistence
3. **TC-007:** Archive with confirmation
4. **TC-014:** App detail header
5. **TC-023, TC-024:** Ratings aggregate card + iTunes Lookup fallback
6. **TC-025, TC-026:** Pagination + Load More
7. **TC-032:** Review detail load
8. **TC-033, TC-034:** Reply create
9. **TC-035, TC-036:** Reply edit
10. **TC-037, TC-038:** Reply delete + confirmation
11. **TC-045, TC-052:** Recent reviews widget load + error fallback
12. **TC-049:** Widget auto-refresh on Home load
13. **TC-056:** Re-import merge preserves flags
14. **TC-057, TC-058:** Persistence across restart

All P0 tests must be automated and passing before launch.

---

**End of Test Cases Document**

