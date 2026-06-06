# Refinement: Windows Home Screen

**Date:** 2026-06-06
**Status:** Refined
**Feature:** Port the StackConnect **Home screen** to Windows (SwiftCrossUI / WinUI), at full iOS parity, reusing the logic via a shared Foundation-pure package.
**Branch:** `experiment/windows`

---

## 0. Scope Decisions (set with the Product Owner / user before refinement)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Home scope for this delivery | **Full parity with iOS** — provider cards + navigation, sync banner, manual sync, expiration alerts, AND the customizable widgets system |
| 2 | Logic reuse strategy | **Extract a shared Foundation-pure core** package (`StackHomeCore`) consumed by both iOS and Windows |
| 3 | Deliverable | **Refinement artifact + updated project docs** (planning only, no implementation code this session) |

### Doubt resolutions (raised by the developer in Phase 3, answered by the user)

| # | Doubt | Resolution |
|---|-------|------------|
| **D1** | Where to persist non-secret prefs on Windows (widget config, today via `KeyStorable`)? | **New file-based prefs `KeyStorable`** (JSON under `%APPDATA%`); Windows Credential Manager stays **secrets-only**. Adds task **T-A12** (below) and changes the DI in T-B2. |
| **D2** | Responsive reflow scope? | **Fixed 2-column grid that collapses to 1 column on narrow widths** (acceptable v1 delta). *(Default applied by orchestrator.)* |
| **D3** | How deep do v1 navigation targets go? | **Home only.** All destination routes (`accountsList`, `settings`, `appDetail`, `reviewDetail`, `allReviews`, `reimport`) are **placeholder screens with a working Back**. Only the Home screen and the Customize Widgets panel are fully built. Shrinks Block D (T-D3). |
| **D4** | App icons in widgets? | **Gray placeholders in v1.** No image fetch/cache. |
| **D5** | `ProgressView`/`Divider` availability decision owner? | **Engineering decides per-primitive** — use it if SwiftCrossUI 0.7 exposes it, else the text/`Rectangle` fallback. *(Default applied by orchestrator.)* |
| **D6** | Is iOS regression test parity a hard gate? | **Yes** — iOS build + the existing Home/SyncService/ViewModel test suite must still pass as an acceptance gate for Block A (T-A11 / TC-059). *(Default applied by orchestrator.)* |
| **D7** | Re-import flow on Windows? | **Disabled placeholder in v1.** The expiration alert appears with correct content; "Re-import File" pushes a disabled placeholder route (no live Apple sync on Windows v1). |

---

## 1. Requirements (Product Owner)

### 1.1 Summary

Port the StackConnect Home screen — the app's single landing surface — to the Windows target with full feature parity to the iOS implementation. The Windows UI is written in SwiftCrossUI (WinUI backend). All business logic (`HomeViewModel`, `SyncService`, the three widget data classes, and their supporting models) is extracted into a new Foundation-pure shared package (`StackHomeCore`) consumed by both the iOS Xcode project and the Windows SPM package; no logic is duplicated.

**Scope boundary:** everything a user sees and does on the iOS Home screen is reproduced on Windows, except features that are structurally impossible or meaningless on Windows in v1 (deep links, WidgetKit/home-screen widgets, background sync, local push notifications, pull-to-refresh as a gesture, and `@MainActor`/Combine patterns that require Combine/SwiftUI).

### 1.2 Epics

- **E-1 — Shared Home Logic Core (`StackHomeCore` package).** Extract `HomeViewModel`, `HomeUiState`, `SyncService` (Windows-safe subset), `HomeWidget` protocol, the three widget implementations, `HomeWidgetRegistry`, `HomeWidgetConfiguration/Kind/Size`, supporting models, and the widget data loader into a new local SPM package that compiles on Apple **and** Windows with zero UIKit/SwiftUI/WidgetKit/UserNotifications imports.
- **E-2 — Windows Home Screen UI.** Implement the Windows Home screen in SwiftCrossUI consuming `StackHomeCore`, replacing the current smoke-test counter in `StackConnectWindowsApp`.

### 1.3 User Stories & Acceptance Criteria

> Format: Given / When / Then. Priorities: Must / Should.

#### US-001 — Provider Cards Grid (Must, M) — depends on US-010
- **AC-1** Given the Home screen, When viewing the content, Then exactly two provider cards appear ("App Store Connect", "Firebase") in a 2-column grid; **no Google Play** card.
- **AC-2** When the user clicks "App Store Connect", Then navigate to the App Store Connect accounts list.
- **AC-3** When the user clicks "Firebase", Then navigate to the Firebase accounts list.
- **AC-4** Each card shows the provider icon (or text/glyph substitute), display name, and tinted styling distinguishing the two.
- **AC-5** Both provider cards are **always visible** and never replaced by an empty state.

#### US-002 — Settings Card (Must, S) — depends on US-001
- **AC-1** A Settings card is rendered as the **third cell** of the grid, after the two providers.
- **AC-2** Clicking it navigates to Settings.
- **AC-3** It shows a gear icon + "Settings", styled like the provider cards (same height, radius, light gray background).

#### US-003 — Sync Banner (Must, S) — depends on US-010
- **AC-1** When not syncing, no banner is visible.
- **AC-2** When syncing with N accounts in progress, a top banner shows a progress indicator + "Syncing N account(s)…".
- **AC-3** When syncing with 0 accounts in progress, the banner shows "Syncing…".
- **AC-4** When sync ends, the banner disappears with no user action.
- **AC-5** The banner does not block interaction with other UI.

#### US-004 — Manual Sync Trigger (Must, S) — depends on US-003
- **AC-1** Clicking the "Sync" toolbar button calls `triggerSync()` and shows the banner (US-003 AC-2).
- **AC-2** When a sync is in progress, a second click starts **no duplicate** (coalesced) and the button is disabled/loading.
- **AC-3** On first appearance the app auto-calls `triggerSync()` + `loadDashboard()` (mirrors iOS `.task`).

#### US-005 — Account Expiration Alerts (Must, M) — depends on US-010
- **AC-1** On load, if an account `isExpired`, show "Account Expired" with message *"The account '[name]' has expired. Re-import its file to keep using it, or it will stay locked."* + actions **Re-import / Cancel**.
- **AC-2** Re-import → close + navigate to the (v1 placeholder) re-import flow for that account.
- **AC-3** Cancel → close; not shown again for that account this session.
- **AC-4** Else if an account `isExpiringSoon` and not warned this session, show "Account Expiring Soon" with a date-aware message + **Re-import / OK**.
- **AC-5** Re-import (expiring) → close + navigate to re-import.
- **AC-6** OK → close, add account to `warnedAccountIds`, no repeat this session.
- **AC-7** If both expired and expiring, **Expired takes precedence**.

#### US-006 — Widgets Empty State (Must, S) — depends on US-010
- **AC-1** When `widgets` is empty, show a single empty-state card: grid-icon substitute, "No widgets yet", "Add widgets to keep an eye on your apps right from here.", and an "Add Widgets" button.
- **AC-2** "Add Widgets" opens the Customize Widgets panel.
- **AC-3** Provider cards + Settings remain visible above; the empty state applies only to the widgets section.

#### US-007 — Widget Display (Must, L) — depends on US-010, US-006
- **AC-1** When widgets exist, each renders in stored order in a card container; no empty state.
- **AC-2** "In Review" widget: header "In Review" + count, app rows (name/status/version/platform) or "No apps in review".
- **AC-3** "Awaiting Release": header + count, rows with optional "Day N of 7" phased text / paused indicator, or "Nothing awaiting release".
- **AC-4** "Recent Reviews": header + count (up to 5), review rows (app, ★ rating, title, excerpt, relative date) or "Reviews will appear after the next sync", plus a "See more" link.
- **AC-5** While `widget.isLoading`, show a loading indicator in place of content.
- **AC-6** Tappable rows navigate to App Detail / Review Detail (v1 placeholders).
- **AC-7** "See more" navigates to All Reviews (v1 placeholder).

#### US-008 — Customize Widgets Panel (Must, M) — depends on US-007
- **AC-1** The "Customize Widgets" toolbar button opens the panel.
- **AC-2** Active section lists each active widget (icon, name, summary) in order.
- **AC-3** Add Widgets section lists available kinds (icon, name, summary, Add).
- **AC-4** Add → `addWidget(kind)`, widget moves to Active, leaves Add.
- **AC-5** Remove → `removeWidget(id:)`, widget leaves Active, returns to Add.
- **AC-6** Reorder via Up/Down buttons → `moveWidgets(from:to:)`, order updates immediately.
- **AC-7** Empty Active shows "No active widgets".
- **AC-8** Close/Back returns to Home reflecting the current state.
- **AC-9** Configuration **persists across restart** (`home.widget.configurations` via the file-based Windows prefs `KeyStorable`).

#### US-009 — Toolbar / Customize Widgets Entry Point (Must, S) — depends on US-008
- **AC-1** A grid button (or "Customize Widgets" label) is always visible in the toolbar.
- **AC-2** Clicking it opens the panel (US-008).
- **AC-3** Re-clicking when open focuses rather than duplicating.

#### US-010 — `StackHomeCore` Package Extraction (Must, XL) — foundational
- **AC-1** Compiles targeting Windows with no UIKit/SwiftUI/WidgetKit/UserNotifications (Combine only feature-flagged).
- **AC-2** iOS app still compiles; existing `HomeViewModel`/widget tests pass; runtime behavior identical to baseline.
- **AC-3** Compiles when imported by `StackConnectWindowsApp` on macOS host and Windows VM.
- **AC-4** `HomeViewModel`/`SyncService` have no `SwiftUI`/`UIKit`/`WidgetKit`/`UserNotifications`/`AppKit` imports; Combine only under `#if canImport(Combine)` with a callback/async fallback.
- **AC-5** `HomeWidget.makeView()` removed from the shared protocol; view-building is platform-specific.
- **AC-6** Widget config serializes/deserializes via `KeyStorable` on Windows and survives restart.
- **AC-7** `xcodegen generate` regenerates the iOS project cleanly with the new package.

#### US-011 — Navigation Foundation (Windows Coordinator) (Must, M) — depends on US-010
- **AC-1** All navigation (cards, Settings, widget rows, alert actions) routes through SwiftCrossUI navigation.
- **AC-2** Back returns to Home with prior state intact (widgets loaded, sync banner state preserved).
- **AC-3** The coordinator declares only the v1 routes: `accountsList(ProviderType)`, `settings`, `appDetail`, `reviewDetail`, `allReviews`, `reimport`, `customizeWidgets`.

#### US-012 — Cold Start & Loading State (Must, S) — depends on US-010, US-011
- **AC-1** While `loadDashboard()` runs, show a loading indicator.
- **AC-2** When `isLoading` flips to false, the indicator disappears and content shows.
- **AC-3** With no accounts, no crash; provider + Settings cards show; widgets area shows the empty state.

### 1.4 Assumptions

- **A-1** SwiftCrossUI 0.7 supports `VStack`/`HStack`/`Button`/`Text`/scrollable lists; if a 2-col grid primitive is missing, a manual HStack/VStack grid (or single-column list on narrow widths) is acceptable.
- **A-2** Modal dialog/sheet may be absent → fallback is a pushed full-screen view (Customize Widgets) and an inline banner (alerts).
- **A-3** Combine is unavailable on Windows → replace `syncService.$state.sink` with a callback closure / `AsyncStream<SyncState>`.
- **A-4** `KeyStorable` handles small `Codable` widget config arrays — but per **D1**, a new **file-based** Windows prefs `KeyStorable` is introduced for non-secret prefs.
- **A-5** `Bootstrap.makeEnvironment()` is the Windows DI root (SQLite storage + Windows secrets); the iOS `UserDefaultsStorable` preferences role is replaced by the file-based Windows prefs store.
- **A-6** No drag-to-reorder → Up/Down buttons.
- **A-7** SF Symbols don't render on Windows → Unicode glyphs / emoji / text labels (gear ⚙, fire 🔥, stars ★/☆, "ASC" text).
- **A-8** Swift Concurrency (`@MainActor`, `async/await`, `Task`) is available on the Windows toolchain.
- **A-9** No `AsyncImage` → app icons are placeholder boxes in v1 (**D4**).
- **A-10** The re-import flow is a disabled placeholder on Windows v1 (**D7**).

### 1.5 Out of Scope (Windows v1)

Deep links (`stackconnect://`, widget/notification routing); WidgetKit home/lock-screen widgets; background sync; local push notifications; pull-to-refresh gesture (replaced by Sync button); Google Play provider card; real async app-icon loading / `WidgetIconCache`; `LocalNotificationService`; debug sync-started notification; `DeepLinkRouter`/`ReimportRouter`; any `HomeRoute` destination beyond US-011 (rendered as placeholders in v1); accessibility (Narrator); MSIX packaging / Store distribution; full localization (hardcoded English v1).

---

## 2. Design Spec (UX Designer)

> Target: Windows 11 / Fluent Design, constrained to what SwiftCrossUI 0.7 (WinUI backend) can render. This is a **native desktop app**, not a skin of the iOS layout.

### 2.1 SwiftCrossUI 0.7 capability assumptions
- **Confirmed:** `VStack`/`HStack`/`Text`/`Button`/`Spacer`/padding, `WindowGroup`+`.defaultSize`, `@State`, `ScrollView`, `ForEach`.
- **Treat as absent:** `Grid`/`LazyVGrid`, `NavigationStack`/`NavigationSplitView`, `.sheet`, menu bar, SF Symbols, `AsyncImage`, drag-reorder, Acrylic/Mica.
- **Uncertain (use fallback):** `.alert`, `ProgressView`, `Divider`, geometry reading → text/`Rectangle`/fixed-layout fallbacks.

### 2.2 Window architecture
- **Min size** 680×520; **default** 900×660; no max.
- **Content width capped at ~860px**, centered, with 16px side padding below the cap.
- OS-rendered title bar ("StackConnect"); no custom title-bar content; no menu bar in v1 (global commands live in the in-content toolbar row).

### 2.3 Navigation model
- Custom `WindowsHomeCoordinator` holding a `[WindowsRoute]` stack (Home = empty/root). `push`/`pop`; window redraws on the top route.
- In-content **"< Back"** button (no title-bar back). Alt+Left is the Windows convention but key interception is a v2 enhancement.
- **Customize Widgets is a pushed full-screen route** (no sheet).
- Routes: `.home`, `.accountsList(ProviderType)`, `.settings`, `.appDetail`, `.reviewDetail`, `.allReviews`, `.reimport`, `.customizeWidgets`.

### 2.4 Home layout (top → bottom, in a `ScrollView` + `VStack`)
1. **Toolbar row** (manual HStack): "StackConnect" (≈20pt bold) on the left; "Sync" + "Customize Widgets" buttons on the right.
2. **Sync banner** (conditional): InfoBar-style strip — 4px colored left border + spinner/text "Syncing N account(s)…", ≈40px tall.
3. **Provider cards**: manual 2-column grid (HStack/VStack pairs). Cards 120px tall, radius **8** (Fluent uses tighter radii than iOS 16), tinted background (~8% opacity), 1px tinted border. Settings card occupies the 3rd cell. Below 680px width → single column.
4. **Widgets section**: vertical stack of widget cards (radius 8, gray ~8% bg, 1px border, 16px padding, no drop shadow). Empty state → a single centered card with glyph + "No widgets yet" + description + "Add Widgets" button.

### 2.5 Widget cards
- Header row: glyph (Unicode/emoji) + bold title + "(count)" secondary + Spacer.
- Rows: 36×36 gray placeholder square (no `AsyncImage`) + text; review rows use ★/☆ (U+2605/U+2606) + title + excerpt + relative date.
- Empty: single secondary-color text row. Loading: "Loading…" text (no shimmer).
- Awaiting Release phased progress → "Day N of 7" text (use `ProgressView` only if available).
- Recent Reviews → "See more >" text button → `.allReviews`.

### 2.6 Customize Widgets screen (pushed)
- Header: "< Home" back + "Customize Widgets" title.
- **Active** section: rows `[glyph] [name] [summary] [^] [v] [Remove]` (Up disabled on first, Down on last); empty → "No active widgets".
- **Add Widgets** section: rows `[glyph] [name] [summary] [Add]`; hidden when all kinds active.
- No "Edit/Done" mode — Up/Down always visible.

### 2.7 Expiration alerts
- **Inline InfoBar banner** at the very top of the content area (above the toolbar row), not a modal. Expired = **red**; Expiring Soon = **amber**. Expired shown first / more urgent (precedence). "Re-import File" → `.reimport` (disabled placeholder, D7).

### 2.8 Icon substitution table (authoritative)
| iOS SF Symbol | Purpose | Windows v1 substitution |
|---|---|---|
| `square.grid.2x2` | Customize Widgets / empty state | "Customize Widgets" text button; "[#]" glyph in empty card |
| `gearshape.fill` | Settings card | ⚙ (U+2699) |
| (Apple) | App Store Connect card | "ASC" bold blue text (no usable Unicode mark) |
| `flame.fill` | Firebase card | 🔥 (U+1F525, Segoe UI Emoji) |
| `magnifyingglass.circle.fill` | In Review header | 🔍 or "[Review]" |
| `paperplane.circle.fill` | Awaiting Release header | 📤 or "[Release]" |
| `star.bubble.fill` | Recent Reviews header | 💬 or "[Reviews]" |
| `star.fill` / `star` | Rating stars | ★ / ☆ (U+2605 / U+2606) |
| `chevron.right` | Disclosure | ">" |
| app icon | App icon | gray rounded rectangle (placeholder) |

### 2.9 Responsive reflow
| Width | Provider cards | Toolbar buttons |
|---|---|---|
| ≥ 860px | 2-col, content capped 860px centered | full labels |
| 680–859px | 2-col, fills with 16px padding | shortened labels |
| < 680px | single column | abbreviated |

### 2.10 Key UX deltas from iOS (accepted for v1)
1. No pull-to-refresh → "Sync" button (improvement for desktop; auto-sync on first appear preserved).
2. Modal alerts → inline InfoBar banners (more Fluent; render at top so they're visible regardless of scroll).
3. Customize Widgets is a pushed full-screen view, not a sheet (v2: side panel/drawer).
4. Up/Down reorder instead of drag (keyboard-accessible; ≤3 widgets typical).
5. No deep links; re-import is a placeholder.
6. App icons are gray placeholders.
7. No Acrylic/Mica; flat background.
8. Segoe UI Variable system font (correct Fluent behavior).
9. `HomeWidget.makeView()` removed from the shared protocol; Windows builds its own widget views from the same data classes.

### 2.11 Proposed Windows file structure
```
StackConnectWindowsApp/Sources/StackConnectWindowsApp/
├── App/
│   ├── StackConnectApp.swift            # extend with the real WindowGroup body
│   └── WindowsHomeCoordinator.swift     # route stack + navigation
├── Home/
│   ├── WindowsHomeView.swift
│   ├── WindowsToolbarView.swift
│   ├── WindowsSyncBannerView.swift
│   ├── WindowsProviderCardView.swift
│   └── Widgets/
│       ├── WindowsWidgetContainerView.swift
│       ├── WindowsWidgetsEmptyStateView.swift
│       ├── WindowsInReviewWidgetView.swift
│       ├── WindowsAwaitingReleaseWidgetView.swift
│       └── WindowsRecentReviewsWidgetView.swift
├── CustomizeWidgets/
│   └── WindowsCustomizeWidgetsView.swift
└── Shared/
    ├── WindowsAlertBannerView.swift
    └── WindowsBackButtonView.swift
```

---

## 3. Task Breakdown (Developer)

> Grounded in codebase exploration. Order respects dependencies. Complexity S/M/L.

### 3.1 Architecture decisions (confirmed against the code)
- **`StackHomeCore`** = new Foundation-pure SPM package depending only on `StackProtocols`. Holds the Home models, the pure `HomeWidget` protocol + the 3 widget data types, the `AppleAccountSyncing` protocol, the pure `SyncService` pipeline, and the platform-agnostic `HomeViewModel`.
- **Models extract cleanly** — `AccountModel`/`AppModel`/`CustomerReviewModel`/`SyncState` are Foundation-pure `Codable` (not SwiftData `@Model`). **Exception:** `ProviderType.swift` leaks SwiftUI (`Color`, SF Symbol name) → split into pure enum (raw `iconSymbolName`/`colorName` tokens) in core + an iOS-only `ProviderType+SwiftUI.swift`. Same split for `HomeWidgetKind.systemImage`/`tintColor`.
- **`makeView()` removal** — drop `makeView() -> AnyView` from the shared `HomeWidget` protocol; keep `id`/`kind`/`configuration`/`isLoading`/`load() async`. iOS rebuilds views via a `HomeWidgetViewFactory`; Windows builds its own SwiftCrossUI widget views from the same result data.
- **Combine bridge** — replace `syncService.$state.sink`/`Set<AnyCancellable>` with `onStateChanged: ((SyncState) -> Void)?` (and/or `AsyncStream<SyncState>`); iOS re-publishes via a `#if canImport(Combine)` adapter to keep existing SwiftUI bindings; all Combine imports gated.
- **`SyncService` gating** — pure pipeline is already `nonisolated static`; gate `WidgetCenter.reloadAllTimelines()` under `#if canImport(WidgetKit)`, the `#if DEBUG` UIKit usage under `#if canImport(UIKit)`, and `UserNotifications` under `#if canImport(UserNotifications)`.
- **Latent bug / prerequisite:** a duplicate `KeyStorable` protocol still in the app target shadows the public `StackProtocols` one (from A1) — must be removed first (T-A1).
- **`WindowsHomeCoordinator`** — custom `[WindowsRoute]` stack; current route = `last ?? .home`; Customize Widgets is a pushed route; in-content Back.

### 3.2 Block A — `StackHomeCore` extraction & shared-model migration
| ID | Title | Description | Deps | Cx |
|----|-------|-------------|------|----|
| **T-A1** | Remove duplicate `KeyStorable` from app target | Delete the shadowing `protocol KeyStorable` in `StackConnect/Storage/KeyStorable.swift`; repoint refs to the public `StackProtocols` one; `xcodegen generate`; confirm iOS compiles. | — | M |
| **T-A2** | Create `StackHomeCore` package skeleton | `Packages/StackHomeCore/` Foundation-pure lib depending on `StackProtocols`; add to `project.yml` (iOS) and `StackConnectWindowsApp/Package.swift`; regenerate. | T-A1 | M |
| **T-A3** | Split `ProviderType` | Pure enum + `displayName` + raw `iconSymbolName`/`colorName` → core; iOS-only `ProviderType+SwiftUI.swift` re-adds `Color`/`Image(systemName:)`. | T-A2 | M |
| **T-A4** | Migrate Home value models | Move `AccountModel`/`AppModel`/`CustomerReviewModel`/`SyncState` + related Codable types into core; update iOS imports; confirm no SwiftData/SwiftUI leakage. | T-A2 | M |
| **T-A5** | Move widget value types + pure `HomeWidget` protocol; drop `makeView()` | Move `HomeWidgetKind`/`Size`/`Configuration` (raw tokens, no SwiftUI); redefine protocol w/o `makeView()`/SwiftUI `@MainActor`; iOS-only `HomeWidgetKind+SwiftUI.swift`. | T-A4 | M |
| **T-A6** | Extract the 3 concrete widget data types | Move pure `load()` logic of `InReviewWidget`/`AwaitingReleaseWidget`/`RecentReviewsWidget` into core, exposing typed result data; strip SwiftUI view code. | T-A5 | L |
| **T-A7** | iOS `HomeWidgetViewFactory` | Map widget `kind` + result → existing iOS SwiftUI subviews (relocated `makeView()` bodies); wire iOS Home to render through it. | T-A6 | L |
| **T-A8** | Move `AppleAccountSyncing` protocol to core | Protocol → core; keep `AppleAccountConnection` conformance (ASC SDK) iOS-side; confirm core builds without the SDK. | T-A2 | M |
| **T-A9** | Extract `SyncService` with full side-effect gating | Pipeline → core; gate WidgetKit/UIKit/UserNotifications; replace ObservableObject/Combine with `onStateChanged` callback (+`AsyncStream`); Combine under `#if canImport(Combine)`. | T-A4, T-A5, T-A8 | L |
| **T-A10** | Combine bridge + migrate `HomeViewModel` to core | Move state shaping / manual+auto sync / expiration precedence / widget add/remove/reorder / config load+save via `KeyStorable`; iOS `#if canImport(Combine)` republish adapter; update iOS Home view/coordinator. | T-A9 | L |
| **T-A11** | Verify iOS regression parity (D6 gate) | `xcodegen generate` + iOS build + existing Home/Sync/ViewModel tests must pass; fix residual leakage. | T-A7, T-A10 | M |
| **T-A12** | File-based Windows prefs `KeyStorable` (D1) | New JSON-file `KeyStorable` under `%APPDATA%` for non-secret prefs (widget config); Credential Manager stays secrets-only; wire into Windows DI. | T-A2 | M |

### 3.3 Block B — Windows navigation + Home shell
| ID | Title | Description | Deps | Cx |
|----|-------|-------------|------|----|
| **T-B1** | `WindowsRoute` + `WindowsHomeCoordinator` | `App/WindowsHomeCoordinator.swift` with the route enum + `routeStack` + push/pop/current. No NavigationStack. | T-A4 | M |
| **T-B2** | Wire app entry + DI bootstrap | Replace the smoke counter in `App/StackConnectApp.swift` with the resizable window (680×520 / 900×660 / capped ~860px) hosting the route switch; inject core `HomeViewModel` from `Bootstrap.makeEnvironment()` (SQLite + file-based prefs per D1); handle `SCUI_DEFAULT_BACKEND`. | T-A10, T-A12, T-B1 | L |
| **T-B3** | `WindowsBackButtonView` + `WindowsToolbarView` | In-content "< Back" (pop when stack non-empty); toolbar HStack (title + "Sync" US-004 + "Customize Widgets" US-009). | T-B1, T-B2 | S |
| **T-B4** | `WindowsHomeView` content shell | Toolbar + banner slot + provider-grid slot + widgets slot in ScrollView+VStack capped 860px; bind to core state; auto-sync on first appear; render route switch. | T-B3 | M |
| **T-B5** | `WindowsProviderCardView` + manual 2-col grid (US-001, US-002) | Radius-8 tinted card w/ Unicode/text icon + displayName; manual 2-col grid; Settings 3rd cell → `.settings`; cards → `.accountsList`. | T-B4 | M |
| **T-B6** | `WindowsSyncBannerView` (US-003) | InfoBar strip (colored left-border Rectangle) reflecting `SyncState` via the callback bridge; text/Rectangle fallback if no ProgressView (D5). | T-B4 | S |

### 3.4 Block C — Windows widgets UI
| ID | Title | Description | Deps | Cx |
|----|-------|-------------|------|----|
| **T-C1** | `WindowsWidgetContainerView` + empty state (US-006) | ScrollView+VStack of widget cards from active `[HomeWidgetConfiguration]`; empty-state card → push `.customizeWidgets`. | T-B4, T-A6 | M |
| **T-C2** | 3 Windows widget views (US-007) | `WindowsInReviewWidgetView`/`WindowsAwaitingReleaseWidgetView`/`WindowsRecentReviewsWidgetView` w/ loading+empty+data; tappable rows → `.appDetail`/`.reviewDetail`; header action → `.allReviews`; ★/☆ ratings; gray placeholder icons (D4). | T-C1 | L |
| **T-C3** | `WindowsCustomizeWidgetsView` (US-008) | Pushed full-screen route: Active (Remove + Up/Down) + Add sections; mutations via core `HomeViewModel`; persist via file-based prefs `KeyStorable` (survive restart); Back to Home. | T-C2, T-A10, T-A12 | M |

### 3.5 Block D — Alerts / loading / polish
| ID | Title | Description | Deps | Cx |
|----|-------|-------------|------|----|
| **T-D1** | `WindowsAlertBannerView` (US-005) | Inline InfoBar (Expired=red, Expiring=amber) driven by core logic w/ Expired precedence; rendered inline (not modal). | T-B4, T-A10 | S |
| **T-D2** | Cold-start / loading (US-012) | Loading state across shell/grid/widgets (text/Rectangle fallback per D5); offline-first: render SQLite data immediately then reflect sync via banner. | T-B6, T-C2 | S |
| **T-D3** | Wire v1 nav targets as placeholders (US-011, D3) | Route-switch destinations for `accountsList`/`settings`/`appDetail`/`reviewDetail`/`allReviews`/`reimport` as **labeled placeholders with working Back** (reimport disabled, D7). | T-B5, T-C2 | M |
| **T-D4** | Responsive reflow (D2) | Verify manual grid + widget list across the resize range, capped 860px centered; collapse 2-col → 1-col on narrow widths. | T-D2 | S |

### 3.6 Block E — Tests & VM-gate validation
| ID | Title | Description | Deps | Cx |
|----|-------|-------------|------|----|
| **T-E1** | Core logic unit tests | `StackHomeCore` tests: expiration precedence, widget add/remove/reorder + persistence round-trip (MockKeyStorable), manual-sync orchestration, `onStateChanged` transitions. | T-A10 | M |
| **T-E2** | `SyncService` pipeline tests under gating | Pipeline compiles/runs with Apple side-effects compiled out (Windows path); assert state transitions + gated code doesn't run off-platform. | T-A9 | M |
| **T-E3** | 7th GUI Home build gate | Extend `Test-WindowsPort.ps1` w/ a GUI build of `StackConnectWindowsApp` + `StackHomeCore` honoring `--scratch-path`/`core.symlinks=false`/`SCUI_DEFAULT_BACKEND=WinUIBackend`; pure-ASCII; optional `-RunGui` launch. | T-B2 (+ T-C3, T-D3 for a full build) | M |
| **T-E4** | VM end-to-end Home smoke | Run the (now 7) gates on the VM, launch the GUI, manually verify US-001…US-009/011/012 + push/pop + Customize persistence across restart. | T-E3 | M |

### 3.7 Technical risks & unknowns
- **Model-dependency graph** — extraction order is strict (models → widget types → protocol → widgets → AppleAccountSyncing → SyncService → ViewModel). `AppleAccountConnection: AppleAccountSyncing` stays iOS-side (ASC SDK is iOS-only); Windows likely has **no live Apple sync** in v1 (relates to D7 — the Windows factory may be a no-op/stub). Stray `import WidgetKit` in `AppDetailViewModel`/`AppListViewModel`/`ArchivedAppsViewModel` are out-of-Home but would break any shared build that includes them — keep iOS-only.
- **SwiftCrossUI 0.7 gaps** — NavigationStack/sheet/menu-bar/LazyVGrid/native-alert/drag-reorder absent (mitigated). `ProgressView`/`Divider`/geometry **uncertain** → spike each inside the GUI build gate before closing its dependent task.
- **Combine→callback bridge** — risk of ordering/threading differences vs Combine's `@MainActor` delivery; the iOS republish adapter must preserve main-thread delivery + de-dup (covered by T-E1).
- **MAX_PATH / symlinks** — adding `StackHomeCore` deepens the graph; the 7th gate must run under the constrained `--scratch-path`.
- **`Test-WindowsPort.ps1` 7th gate** — GUI builds are slow/backend-dependent; keep pure-ASCII (recent PS 5.1 parse-error fix), reuse existing scratch/symlink setup, gate `-RunGui` behind a flag so CI runs build-only.

---

## 4. Test Cases (QA)

> 92 test cases across 14 groups. `[A]` automatable, `[M]` manual-only. Priorities P0/P1/P2. Full per-case detail (preconditions/steps/expected) was authored in the QA phase; this section captures the catalog + traceability. (P0: 56 · P1: 27 · P2: 9. Unit/Integration [A]: 42 · Manual [M]: 38 · mixed: 12.)

### 4.1 Catalog by group
- **G1 US-001 Provider Cards:** TC-001 (2 cards, no Google Play, M/P0), TC-002 (never replaced by empty state, M/P0), TC-003 (ASC→AccountsList, M/P0), TC-004 (Firebase→AccountsList, M/P0), TC-005 (icon/name/tint, M/P1), TC-006 (VM returns 2 providers, A/P0), TC-007 (coordinator enqueues route, A/P0).
- **G2 US-002 Settings Card:** TC-008 (3rd cell, M/P0), TC-009 (→Settings, M/P0), TC-010 (coordinator settings route, A/P0).
- **G3 US-003 Sync Banner:** TC-011 (hidden idle, M/P0), TC-012 ("Syncing N…", A+M/P0), TC-013 ("Syncing…" at 0, A/P1), TC-014 (auto-dismiss, A+M/P0), TC-015 (non-blocking, M/P1), TC-016 (inline InfoBar, M/P1).
- **G4 US-004 Manual Sync:** TC-017 (button→trigger+banner, M/P0), TC-018 (double-click coalesced, A/P0), TC-019 (auto trigger+load on appear, A/P0), TC-020 (button disabled while syncing, A/P0).
- **G5 US-005 Expiration Alerts:** TC-021 (Expired red InfoBar, M/P0), TC-022 (Expiring amber + date, M/P0), TC-023 (Expired precedence, A/P0), TC-024 (dismiss→warned, no repeat, A+M/P0), TC-025 (already-warned→no alert, A/P0), TC-026 (Re-import→disabled placeholder D7, M/P0), TC-027 (no expiry→no alert, A/P0), TC-028 (multiple expired, A+M/P1).
- **G6 US-006 Empty State:** TC-029 (empty card content, M/P0), TC-030 (empty flag, A/P0), TC-031 (cards above empty state, M/P0), TC-032 (Add Widgets→panel, M/P0).
- **G7 US-007 Widget Display:** TC-033 (In Review, M/P0), TC-034 (Awaiting Release phased, M/P0), TC-035 (Recent Reviews ≤5, M/P0), TC-036 (limit 5, A/P0), TC-037 (gray placeholder icons D4, M/P0), TC-038 (loading state, M/P1), TC-039 (row→AppDetail, M/P1), TC-040 (See more→AllReviews, M/P1), TC-041 (review→ReviewDetail, M/P1), TC-042 (star string, A/P1).
- **G8 US-008 Customize Widgets:** TC-043 (Active+Add sections, M/P0), TC-044 (Add moves to Active, M/P0), TC-045 (duplicate-add guard, A/P0), TC-046 (Remove moves to Add, M/P0), TC-047 (Up/Down reorder, A+M/P0), TC-048 (Up disabled first, A/P0), TC-049 (Down disabled last, A/P0), TC-050 ("No active widgets", M/P1), TC-051 (Back→Home state preserved, M/P0), TC-052 (full-screen not sheet, M/P0).
- **G9 US-009 Toolbar:** TC-053 (always visible, M/P0), TC-054 (opens panel, M/P0), TC-055 (re-click no duplicate, A+M/P1).
- **G10 US-010 Extraction:** TC-056 (no forbidden imports + Windows build, A/P0), TC-057 (Combine gated, A/P0), TC-058 (no `makeView()` in protocol, A/P0), TC-059 (iOS compiles + tests pass, D6 gate, A/P0), TC-060 (config serialize round-trip, A/P0), TC-062 (xcodegen clean, A/P0).
- **G11 US-011 Navigation:** TC-063 (init `[home]`, A/P0), TC-064 (push, A/P0), TC-065 (pop, A/P0), TC-066 (back at root no-op, A/P0), TC-067 (Back restores Home state, M/P0), TC-068 (destinations = placeholders w/ Back, D3, M/P0).
- **G12 US-012 Cold Start:** TC-069 (loading indicator, M/P0), TC-070 (isLoading transition, A/P0), TC-071 (zero accounts no crash, A+M/P0), TC-072 (empty storage valid state, A/P0).
- **G13 Edge/Negative:** TC-073 (corrupt storage no crash, A/P0), TC-074 (widget load failure, A+M/P0), TC-075 (min-width 1-col, M/P1), TC-076 (>860px centered cap, M/P1), TC-077 (below-min resize blocked, M/P1), TC-078 (sync coalescing, A/P0), TC-079 (restart persistence file-based, D1, A/P0), TC-080 (move same index no-op, A/P1), TC-081 (move out-of-bounds no crash, A/P0), TC-082 (ProgressView/Divider fallbacks, M/P1), TC-083 (no ad-hoc hardcoded strings, A/P2), TC-084 (valid account no alert, A/P0), TC-085 (stress N=20 widgets, M/P2), TC-086 (network failure no crash, A/P0), TC-087 (default 900×660, M/P1), TC-088 (both expired+expiring → only Expired, A/P0), TC-089 (`warnedAccountIds` session-scoped, A/P1).
- **G14 Build Gate:** TC-090 (gate 7 GUI Home passes + renders, M/P0), TC-091 (MAX_PATH via `--scratch-path`, M/P0), TC-092 (`SCUI_DEFAULT_BACKEND=WinUIBackend`, M/P0).

### 4.2 Coverage matrix (US → TCs)
| US | TCs |
|----|-----|
| US-001 | TC-001, 002, 003, 004, 005, 006, 007 |
| US-002 | TC-008, 009, 010 |
| US-003 | TC-011, 012, 013, 014, 015, 016 |
| US-004 | TC-017, 018, 019, 020, 078 |
| US-005 | TC-021, 022, 023, 024, 025, 026, 027, 028, 084, 088, 089 |
| US-006 | TC-029, 030, 031, 032 |
| US-007 | TC-033, 034, 035, 036, 037, 038, 039, 040, 041, 042 |
| US-008 | TC-043, 044, 045, 046, 047, 048, 049, 050, 051, 052, 060, 061, 079 |
| US-009 | TC-053, 054, 055 |
| US-010 | TC-056, 057, 058, 059, 060, 062 |
| US-011 | TC-063, 064, 065, 066, 067, 068 |
| US-012 | TC-069, 070, 071, 072 |
| Edge/Build | TC-073–077, 080–087, 090–092 |

### 4.3 Test infra notes
- Unit/Integration land in `Packages/StackHomeCore/Tests/` using `MockPersistentStorable` / `MockKeyStorable` (+ a `MockSyncService`).
- iOS regression (TC-059) runs the existing `StackConnect` Home/Sync/ViewModel suite on the Mac.
- Manual `[M]` cases run on the Windows VM via `Test-WindowsPort.ps1` (gate 7 + `-RunGui`).
- Windows prefs file expected at `%APPDATA%\StackConnect\` (TC-061, TC-079).

---

## 5. Summary

- **User stories:** 12 (US-001 … US-012)
- **Tasks:** 30 across 5 blocks (A: 12 incl. T-A12, B: 6, C: 3, D: 4, E: 4)
- **Test cases:** 92 (P0: 56 · P1: 27 · P2: 9)
- **Open doubts:** all 7 resolved (see §0)
- **Critical path:** T-A1 → T-A2 → T-A4 → T-A5 → T-A6 → T-A9 → T-A10 → T-B2 → T-B4 → T-C1 → T-C2 → T-C3 → T-E3 → T-E4
- **Biggest risks:** `StackHomeCore` extraction (Combine bridge + `makeView()` removal + `ProviderType` split), SwiftCrossUI 0.7 capability gaps, and the iOS regression gate (D6).
