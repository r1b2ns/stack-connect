# Session Context: Accounts Grid + DesktopAlertView

**Date:** 2026-06-12
**Branch:** `experiment/windows`
**Goal:** Refactor the Windows accounts list from a vertical list of rows to a 2-column card grid with a three-dot menu (⋮) for "Open" and "Delete" actions.

---

## What was done

### 1. New component: `DesktopAlertView`

**File:** `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Shared/DesktopAlertView.swift`

A reusable full-screen modal overlay component for SwiftCrossUI desktop apps. Features:

- **Dimmed background**: `Color.black.opacity(0.5)` covering the full parent area
- **Centered card**: 300px wide, rounded corners (12), gray border
- **Header**: title + X close button (top-right)
- **Vertical option buttons**: each tinted with its own color, 0.08 opacity background
- **Callbacks**: `onClose: () -> Void`, `onSelect: (String) -> Void`

Supporting type: `DesktopAlertOption(label: String, color: Color)`.

Usage pattern — drive via `@Published` model property + `.overlay {}`:
```swift
.overlay {
    if model.alertAccountId != nil {
        DesktopAlertView(
            title: "Account Options",
            options: [
                DesktopAlertOption("Open", color: .blue),
                DesktopAlertOption("Delete", color: .red),
            ],
            onClose: { model.alertAccountId = nil },
            onSelect: { label in handleSelection(label) }
        )
    }
}
```

### 2. Refactored `WindowsAccountsListView`

**File:** `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Accounts/WindowsAccountsListView.swift`

#### Layout: 2-column card grid
- Each card is a vertical `VStack`: `...` button (top-right) → provider glyph (centered) → account name → badges row
- Grid built using `ForEach(model.accounts, id: \.id)` with `isRowStart()` / `pairAccount()` helpers — only even-indexed accounts render an `HStack` pair

#### Actions: overlay-based modals
- **⋮ actions alert**: triggered by `model.alertAccountId != nil` → "Open" and "Delete" options
- **Delete confirmation**: triggered by `model.deleteConfirmingId != nil` → "Delete" and "Cancel" options
- Both use `DesktopAlertView` rendered via `.overlay {}` on the body `ScrollView`

#### Dark mode fix
- All `Color(white: 0.94)` replaced with `Color.gray.opacity(0.15)` in error banner, expired inline error

### 3. Model changes: `WindowsAccountsListModel`

**File:** `StackConnectWindowsApp/Sources/WindowsAppCore/Accounts/WindowsAccountsListModel.swift`

Added two `@Published` properties:
- `expiredTappedId: String?` — moved from view `@State` to model (required for ForEach reactivity)
- `alertAccountId: String?` — tracks which account's ⋮ modal is showing

---

## Key learnings (SwiftCrossUI)

### ForEach limitations
- `ForEach(computedHelperArray(), id: \.id)` **does NOT** propagate `@State` or `@Published` changes to button action closures inside its content. Buttons silently fail to fire.
- **Fix**: always iterate over a model's `@Published` array directly: `ForEach(model.accounts, id: \.id)`.

### @State vs @Published in ForEach
- `@State` changes on the parent view do NOT reliably trigger re-renders of conditional views inside `ForEach` content closures.
- **Fix**: use `@Published` properties on the `ObservableObject` model for any state that drives conditional rendering inside ForEach.

### No ZStack in SwiftCrossUI
- `ZStack` is not available. Use `.overlay(alignment:)` instead.
- `.overlay()` supports alignment parameter (default: `.center`).

### Native APIs available but fragile
- `Menu("label") { Button... }` — exists but didn't work reliably in testing.
- `.alert("title", isPresented: $bool) { Button... }` — exists but didn't trigger from ForEach button actions.
- **Workaround**: build custom modals with `.overlay {}` + conditional rendering driven by model `@Published` state.

### Button text rendering
- `\u{22EE}` (⋮ vertical ellipsis) may not render or may have zero hit area on some platforms. Use `"..."` instead.

### Overlay strokes swallow clicks (ROOT CAUSE of the dead ⋮ button)
- A `RoundedRectangle().stroke()` in `.overlay {}` renders (AppKit backend) as a plain `NSBezierPathView` — an `NSView` with **no `hitTest` override** — positioned as a sibling ON TOP of the content, covering the full card. It captures every mouse click, so any `Button`/`TextEditor` underneath silently never fires.
- This is why `.onTapGesture` works on Home/AppRow cards: the gesture is attached **outside/after** the overlay, so it wraps the stroke too.
- **Fix**: render border strokes via `.background { RoundedRectangle().stroke(...) }` instead — `BackgroundModifier` puts the builder content BEHIND the foreground (background = child 0, foreground = child 1), so clicks reach the buttons. With translucent fills (0.08/0.15 opacity) the border stays visible through the fill.
- **Sweep completed (2026-06-12, later)**: all 13 remaining `.overlay { …stroke }` blocks across 10 files were converted to `.background { …stroke }` (WindowsReplyComposerView ×2, WindowsReviewDetailView ×3, WindowsUsersTabView, WindowsArchivedAppsView, WindowsAppDetailView, WindowsAppRow, WindowsWidgetsEmptyStateView, WindowsProviderCardView, WindowsWidgetComponents, WindowsReviewRow). Zero overlay-strokes remain in the tree; the only `.overlay {}` left are the two DesktopAlertView modals in WindowsAccountsListView (intentional). Build succeeds.

---

## Files changed (uncommitted)

| File | Change |
|------|--------|
| `Shared/DesktopAlertView.swift` | **NEW** — reusable modal overlay component |
| `Accounts/WindowsAccountsListView.swift` | Major refactor: grid layout + overlay modals |
| `WindowsAppCore/Accounts/WindowsAccountsListModel.swift` | Added `expiredTappedId`, `alertAccountId` |

---

## Navigation refactor (2026-06-12, later) — persistent sidebar + tap-to-open

### Persistent sidebar shell
- **Problem**: the sidebar lived inside `WindowsHomeView`; pushing any route replaced the whole screen (`RootView.currentScreen`), so the sidebar vanished on +Add / apps list / etc.
- **Fix**: moved the shell (expiration banner + 200px sidebar + divider + right pane) into `RootView`. The right pane shows the pushed `destination(for:)` when `coordinator.current != nil`, else `WindowsHomeView`.
  - New file `Home/WindowsSidebarView.swift` — extracted sidebar (Home/App Store Connect/Settings). Each item's `.onTapGesture` now does `coordinator.popToRoot()` THEN `coordinator.sidebarSection = section` (so selecting a section from inside a pushed route navigates back to that section's root instead of leaving the old route on screen).
  - `WindowsHomeView` reduced to ONLY the right-pane content switch (dashboard / accounts / settings). Removed its outer VStack/HStack/`sidebarPanel`/`buildSidebarItem`/`expirationAlertSlot`.
  - `RootView.body` = `VStack { WindowsAlertBannerView; HStack { WindowsSidebarView; Divider; rightContent } }.task { loadDashboard }`. `currentScreen` renamed `rightContent`. All `*ModelCache` types + `destination(for:)` switch unchanged.

### Tap-to-open account (like "Open")
- In `WindowsAccountsListView.accountCard`, the glyph+name+badges are wrapped in an inner `VStack` with `.onTapGesture { openAccount(account) }`. The `...` button stays in a SEPARATE sibling row OUTSIDE the tap region (the AppKit tap target swallows clicks to any Button beneath it — same hit-test issue as overlay strokes).
- New `openAccount(_:)` helper: expired → toggle inline error; else clear it + push `.appsList`. Reused by both the card tap and the alert "Open" item so they behave identically.

### Build note
- Agent ran in a temp worktree; changes were copied into the main checkout (DesktopAlertView was identical/unchanged) and the temp worktree+branch removed. `swift build` succeeds.

## Account card visuals (2026-06-12, later) — Apple logo + square cells

- **Apple glyph**: `providerGlyph` `.apple` changed from `"ASC"` to `"\u{F8FF}"` (Apple-logo PUA char — renders the real Apple logo in the macOS system font on the AppKit backend; shows tofu on Windows since it's an Apple-specific codepoint. Phosphor has no Apple brand logo). Firebase 🔥 / Google Play ▶ unchanged. Glyph font bumped `.title2` → `.largeTitle`.
- **Square cards**: card body uses `.frame(maxWidth: .infinity, maxHeight: .infinity)` + `.aspectRatio(1, contentMode: .fit)` (the responsive square-cell idiom — both compile/work in SwiftCrossUI 0.7; the fixed-190 fallback was not needed). Each card is a 1:1 square that scales with the half-column width. The expired inline error still appends below the square.

## Status

- `swift build --package-path StackConnectWindowsApp` **succeeds** (no errors, only pre-existing warnings in RootView.swift)
- **2026-06-12 (later)**: user reported the ⋮ button did nothing at runtime. Root cause: overlay stroke swallowing clicks (see learning above). Fixed by moving the card border stroke from `.overlay {}` to `.background {}` in `WindowsAccountsListView.accountCard` and `DesktopAlertView.buildCard`. Build succeeds; awaiting runtime re-test.
- **Not committed** — awaiting user confirmation
