# T-E4: VM End-to-End Home Smoke Test Plan

Task: T-E4-vm-e2e-smoke
Scope: Run all 7 gates on the Windows VM, launch the GUI, manually verify
US-001 through US-009/US-011/US-012 plus push/pop navigation and Customize
Widgets persistence across app restart.

---

## Prerequisites

### Windows VM Setup

1. **Windows 11** (22H2 or later) with **Developer Mode** enabled.
   - Settings > Privacy & security > For developers > Developer Mode = ON
2. **Swift toolchain** for Windows installed and on PATH.
   - Install from https://www.swift.org/install/windows/
   - Verify: open PowerShell and run `swift --version` (expect 6.0+ output).
3. **Git for Windows** installed.
   - `git --version` must return 2.39+.
   - Configure: `git config --global core.symlinks false` (the script sets this
     automatically if not already present, but pre-setting avoids any prompt).
4. **Windows App Runtime 1.5** redistributable installed (for WinUI rendering).
   - Download from https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads
   - The `Register-StackConnectApp.ps1` script bypasses the bootstrap but the
     runtime must still be present for WinUI widgets/rendering.
5. **Visual Studio Build Tools 2022** (C++ workload) OR the Windows SDK
   (10.0.22621.0+) for the C interop headers the Swift toolchain needs.
6. **Repository** cloned to a short path (e.g. `C:\repos\stack-connect`).
   - Long paths (e.g. under OneDrive/Desktop) can blow MAX_PATH. The script
     mitigates this via `--scratch-path` but a short clone path is safest.
7. **Branch**: `experiment/windows` (or the task branch `feat/T-E4-vm-e2e-smoke`).
   - `git checkout experiment/windows && git pull`

### Environment Variables (optional)

| Variable | Purpose |
|----------|---------|
| `FIREBASE_SA_JSON` | Path to Firebase service-account .json (if testing Firebase flows) |
| `PLAY_SA_JSON` | Path to Google Play service-account .json (if testing Play flows) |

These are optional for the Home smoke test (the Home uses local SQLite data).

---

## Part 1: Automated Gates (7 gates via Test-WindowsPort.ps1)

### Run command

```powershell
# Full run with GUI launch (recommended for E2E):
.\Test-WindowsPort.ps1 -Pull -CleanGui -RunGui

# Full run including ASC SDK rebuild (slower, use if SDK deps changed):
.\Test-WindowsPort.ps1 -Pull -Clean -RunGui

# Skip SDK gate (faster iteration on GUI changes only):
.\Test-WindowsPort.ps1 -SkipSDK -CleanGui -RunGui
```

### Gate-by-gate expected results

| # | Gate | Expected Output | TC Coverage |
|---|------|-----------------|-------------|
| 1 | Core PoC (SQLite + crypto + RS256 + PEM) | `[PASS]` — SQLite read/write, AES-GCM, PBKDF2, RS256, PEM parse all succeed | - |
| 2 | Secrets probe (Credential Manager) | `[PASS]` — Win32 Credential Manager write/read/delete round-trip | - |
| 3 | Credential store (WindowsCredentialStorable / KeyStorable) | `[PASS]` — protocol-conforming store round-trip | - |
| 4 | App Store Connect SDK build | `[PASS]` — ASC SDK compiles on Windows (or `[SKIP]` if `-SkipSDK`) | - |
| 5 | Windows app bootstrap (headless) | `[PASS]` — StackConnectWindows links and runs the B2 bootstrap (or `[SKIP]` if `-SkipSDK`) | TC-091 |
| 6 | Windows GUI build (full Home B+C+D + StackHomeCore) | `[PASS]` — StackConnectWindowsApp package compiles all blocks | TC-092 |
| 7 | GUI screen test (register identity + launch window) | `[PASS]` — package registered, app launched via activation | TC-090 |

### Verifying TC-090 (gate 7 passes + renders)

- The script prints `[PASS] GUI screen test (register identity + launch window)`.
- The StackConnect window appears on screen showing the Home content.
- If the window does NOT appear: check Developer Mode is ON, the Windows App
  Runtime is installed, and the Swift runtime DLLs were bundled (the script
  logs these steps).

### Verifying TC-091 (MAX_PATH via --scratch-path)

- Gate 5 uses `--scratch-path C:\Users\<user>\.scw` for the headless app.
- Gate 6 uses `--scratch-path C:\Users\<user>\.scwapp` for the GUI app.
- Both build successfully despite the repo being at a potentially long path.
- Verification: confirm no "filename too long" or MAX_PATH errors in the log.
- The log file (`Test-WindowsPort-<timestamp>.log`) records the full build output.

### Verifying TC-092 (SCUI_DEFAULT_BACKEND=WinUIBackend)

- The script sets `$env:SCUI_DEFAULT_BACKEND = "WinUIBackend"` before gate 6.
- Gate 6 builds successfully (no `<gtk/gtk.h>` errors — the Gtk graph is pruned).
- The launched window (gate 7) renders using WinUI controls (not Gtk/AppKit).
- Visual confirmation: WinUI-style buttons, text, scroll, and layout are used.

---

## Part 2: Manual GUI Verification Checklist

After gate 7 launches the app window, perform the following checks. Each
maps to a User Story (US) and describes the expected visual/behavioral result.

### US-012: Cold Start / Loading State

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Observe the window immediately after launch | A `ProgressView` spinner + "Loading..." text appears below the toolbar while `loadDashboard()` runs |
| 2 | Wait 1-2 seconds | The loading indicator disappears once the SQLite load completes |
| 3 | Confirm content appears below | Provider cards and widgets section become visible after loading |

### US-001: Provider Cards Grid

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Look at the main content area below the toolbar | A 2-column grid of provider cards is visible |
| 2 | Count the provider cards | Exactly 2 cards: "App Store Connect" (blue tint) and "Firebase" (orange/amber tint). No "Google Play" card is shown |
| 3 | Verify card styling | Each card has rounded corners (~8px radius), a tinted background, a glyph/icon, and the provider name |
| 4 | Tap the "App Store Connect" card | Navigation pushes to a placeholder: "App Store Connect" title + "App Store Connect - coming soon" subtitle + "< Back" button |
| 5 | Tap "< Back" | Returns to Home; all state (widgets, sync banner) is intact |
| 6 | Tap the "Firebase" card | Navigation pushes to a placeholder: "Firebase" title + "Firebase - coming soon" + "< Back" |
| 7 | Tap "< Back" | Returns to Home |

### US-002: Settings Card (3rd Cell)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Look at the grid after the 2 provider cards | A 3rd cell labeled "Settings" with a gear glyph is present (gray tint) |
| 2 | Confirm its position | In a 2-column grid: row 1 has "App Store Connect" + "Firebase"; row 2 has "Settings" in the left column, right column is empty/spacer |
| 3 | Tap the "Settings" card | Navigation pushes to placeholder: "Settings" title + "Settings - coming soon" + "< Back" |
| 4 | Tap "< Back" | Returns to Home |

### US-003: Sync Banner (Conditional Appearance)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | On initial load with no sync in progress | No sync banner is visible between the toolbar and the grid |
| 2 | (If triggerable) Tap the "Sync" toolbar button | A sync banner appears showing a progress indicator + "Syncing..." text with a blue left-accent strip |
| 3 | After sync completes (or immediately on Windows v1, since sync is no-op) | The banner disappears. On v1 with the no-op observer, the banner may appear only momentarily or not at all (expected: no banner on v1 unless a real sync observer is wired) |

Note: On Windows v1, `WindowsNoOpSyncObserver` is wired, so `syncState.isSyncing`
is always `false`. The banner slot will NOT show. This is the EXPECTED behavior
for v1. The code path is validated by unit tests (T-E1/T-E2).

### US-004: Manual Sync Trigger (Toolbar Button)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Look at the toolbar row (top of content) | A "Sync" button is visible on the right side of the toolbar |
| 2 | Tap "Sync" | The button is responsive (visual press feedback). On v1 (no-op observer) no visible sync occurs, but no crash/error happens |
| 3 | Confirm the app remains stable | No freeze, no crash. Home content remains displayed |

### US-005: Account Expiration Alerts (Inline InfoBar)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | If no accounts have expiring/expired credentials | No alert banner is visible above the toolbar |
| 2 | (With test data: an expired account in SQLite) | A RED-accented InfoBar appears at the very top: "Account Expired" title + message naming the account + "Re-import File" and "Cancel" buttons |
| 3 | Tap "Cancel" on the expired banner | The banner dismisses (session-only; reappears on next launch unless already dismissed) |
| 4 | (With test data: an expiring-soon account) | An AMBER/ORANGE-accented InfoBar: "Account Expiring Soon" + date message + "Re-import File" and "OK" buttons |
| 5 | Tap "Re-import File" | Banner dismisses, navigation pushes to "Re-import" placeholder with "Not available on Windows" subtitle (D7 disabled state) |
| 6 | Tap "< Back" from Re-import | Returns to Home |

Note: If the SQLite store has no expired/expiring accounts, steps 2-6 will not
trigger. To test, seed the store with accounts whose `expirationDate` is in the
past (expired) or within 30 days (expiring soon).

### US-006: Widgets Empty State

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | On first launch with no widget configuration persisted | The widgets section (below provider cards) shows an empty-state card |
| 2 | The empty-state card content | Centered text "No widgets configured" (or similar) + an "Add Widgets" button |
| 3 | Tap "Add Widgets" | Navigation pushes to the Customize Widgets full-screen (US-008) |
| 4 | (Go back without adding) Tap "< Home" | Returns to Home; empty state is still shown |

### US-007: Widget Display (All 3 Types)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | After adding widgets via Customize Widgets | The widgets section shows one card per active widget in stored order |
| 2 | "In Review" widget card | Shows the widget glyph + "In Review" title + app rows (or "No apps in review" if data is empty) + loading indicator if still fetching |
| 3 | "Awaiting Release" widget card | Shows "Awaiting Release" title + app rows (or "No apps awaiting release") |
| 4 | "Recent Reviews" widget card | Shows "Recent Reviews" title + review rows (or "No recent reviews") + a "See more" link at the bottom |
| 5 | Tap an app row in In Review or Awaiting Release | Pushes "App Detail" placeholder with "< Back" |
| 6 | Tap a review row in Recent Reviews | Pushes "Review Detail" placeholder with "< Back" |
| 7 | Tap "See more" in Recent Reviews | Pushes "All Reviews" placeholder with "< Back" |
| 8 | Verify widget order | Matches the order set in Customize Widgets |

### US-008: Customize Widgets Panel

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Navigate to Customize Widgets (toolbar button or empty-state "Add Widgets") | Full-screen panel appears with "< Home" back button + "Customize Widgets" title |
| 2 | "Active" section (no widgets active) | Shows "No active widgets" text |
| 3 | "Add Widgets" section | Shows rows for all 3 available kinds: In Review, Awaiting Release, Recent Reviews — each with glyph + name + summary + "Add" button |
| 4 | Tap "Add" on "In Review" | The widget moves from "Add" section to "Active" section. "Add" section now shows 2 kinds |
| 5 | Tap "Add" on "Awaiting Release" | Active section now shows 2 widgets. Add section shows 1 |
| 6 | Tap "Add" on "Recent Reviews" | Active section shows 3 widgets. Add section disappears (all kinds active) |
| 7 | Verify reorder buttons | Each Active row has "^" (up) and "v" (down) buttons. First row: "^" disabled. Last row: "v" disabled |
| 8 | Tap "v" on the first active widget | First and second widgets swap positions |
| 9 | Tap "^" on the last active widget | Last and second-to-last swap positions |
| 10 | Tap "Remove" on a widget | Widget moves back to the "Add" section; removed from Active |
| 11 | Tap "< Home" | Returns to Home; widget section reflects the current active configuration immediately |

### US-009: Toolbar Entry Point (Customize Widgets)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Look at the toolbar row | A "Customize Widgets" button is visible on the right (label adapts by window width: "Customize Widgets" / "Customize" / "Widgets") |
| 2 | Tap the button | Pushes the Customize Widgets full-screen panel (same as US-008 step 1) |
| 3 | Tap "< Home" | Returns to Home |

### US-011: Navigation (Push/Pop, Placeholders with Back)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | From Home, tap "App Store Connect" card | Screen changes to placeholder: title "App Store Connect", subtitle "App Store Connect - coming soon", "< Back" visible |
| 2 | Tap "< Back" | Returns to Home. All Home state (widgets, grid, toolbar) is intact |
| 3 | From Home, tap "Settings" card | Placeholder: "Settings - coming soon" |
| 4 | Navigate to Customize Widgets | Full real screen (not a placeholder) renders |
| 5 | From Home, push to a widget detail (e.g., tap app row in In Review) | "App Detail" placeholder appears |
| 6 | Tap "< Back" | Returns to Home |
| 7 | Trigger Re-import (via expiration banner if available) | "Re-import" placeholder: "Not available on Windows" (disabled notice) |
| 8 | Tap "< Back" | Returns to Home |
| 9 | Verify no "forward" navigation leaks | After popping, the previous screen's state is fully gone from the route stack |

### US-012 (continued): Confirm Loading Is Gone After Load

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | After the initial load finishes | No "Loading..." text or spinner is visible anywhere on the Home |
| 2 | The offline-first content is rendered | Provider cards + widgets (or empty state) are fully visible |

---

## Part 3: Customize Widgets Persistence Across Restart

This verifies that the file-based preferences (`prefs.json`) correctly persist
the widget configuration and survive an app restart.

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Launch the app (gate 7 or manual `swift run`) | Note the initial widget state (likely empty on first-ever run) |
| 2 | Open Customize Widgets | Add all 3 widgets. Reorder them: Recent Reviews first, then In Review, then Awaiting Release |
| 3 | Tap "< Home" | Home shows 3 widgets in order: Recent Reviews, In Review, Awaiting Release |
| 4 | Close the app window (X button or Alt+F4) | App terminates |
| 5 | Verify persistence file exists | Check `%APPDATA%\StackConnect\prefs.json` exists and contains a `home.widget.configurations` key with 3 entries |
| 6 | Relaunch the app | Run `.\Test-WindowsPort.ps1 -SkipSDK -RunGui` (or `swift run --scratch-path $env:USERPROFILE\.scwapp StackConnectWindowsApp` from the GUI package dir) |
| 7 | Observe the Home screen after load | The 3 widgets appear in the SAME order as step 3: Recent Reviews, In Review, Awaiting Release |
| 8 | Open Customize Widgets | Active section shows the 3 widgets in the persisted order. Add section is empty (all active) |
| 9 | Remove one widget (e.g., "In Review"), close, relaunch | After relaunch: only 2 widgets shown, in the order they were left |

### Persistence file location

- **Windows**: `%APPDATA%\StackConnect\prefs.json`
- **Content structure** (example):
  ```json
  {
    "home.widget.configurations": {
      "type": "data",
      "value": "<base64-encoded [HomeWidgetConfiguration] JSON>"
    }
  }
  ```

---

## Part 4: Responsive Reflow Verification (Bonus)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | With the window at >= 860px width | Content is capped at 860px and centered. 2-column grid. Toolbar shows "Customize Widgets" (full label) |
| 2 | Resize window to 680-859px | Grid remains 2-column. Toolbar label shortens to "Customize" |
| 3 | Resize window below 680px | Grid collapses to 1 column. Toolbar label becomes "Widgets" |
| 4 | Resize back to >= 860px | Layout returns to 2-column + full labels |

---

## Summary: TC Coverage Matrix

| TC | Requirement | How Verified |
|----|-------------|--------------|
| TC-090 | Gate 7 GUI Home passes + renders | Gate 7 `[PASS]` + window visually renders Home content |
| TC-091 | MAX_PATH via --scratch-path | Gates 5+6 pass with `--scratch-path` short dirs; no filename-too-long errors in log |
| TC-092 | SCUI_DEFAULT_BACKEND=WinUIBackend | Gate 6 passes without Gtk errors; launched window uses WinUI controls |

---

## Troubleshooting

### Window does not appear after gate 7

1. Confirm Developer Mode is ON.
2. Check `Get-AppxPackage "StackConnect.WindowsApp"` returns the registration.
3. Verify Swift runtime DLLs are in the debug dir (`ls $env:USERPROFILE\.scwapp\debug\*.dll`).
4. Try manual launch: `Start-Process "shell:AppsFolder\<PackageFamilyName>!StackConnectWindowsApp"`.

### Gate 6 fails with `<gtk/gtk.h>` not found

- `$env:SCUI_DEFAULT_BACKEND` was not set to `"WinUIBackend"`.
- Run with `-CleanGui` to force fresh resolution after setting the env var.

### Gate 5 fails with MAX_PATH errors

- The repo is too deep. Clone to `C:\repos\stack-connect` (short path).
- Confirm `--scratch-path` is being applied (check the log for the swift args).

### Persistence not surviving restart

- Check `%APPDATA%\StackConnect\prefs.json` exists after adding widgets.
- If the file is missing, the `AppPaths.dataDirectory()` resolution may have
  failed. Check the `APPDATA` environment variable is set.
- Try launching from the same terminal (env vars carry over).
