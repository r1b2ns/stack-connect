<#
.SYNOPSIS
    Runs the StackConnect Windows-port phase-4 gates, with logging and cleanup.

.DESCRIPTION
    Executes the validation gates on the Windows Swift toolchain:
      1. Core PoC         - SQLite + AES-GCM/PBKDF2 + RS256 + PEM
      2. Secrets probe    - Windows Credential Manager round-trip (raw Win32)
      3. Credential store - WindowsCredentialStorable through KeyStorable
      4. ASC SDK build    - does appstoreconnect-swift-sdk compile on Windows
      5. Windows app      - headless StackConnectWindows: whole non-UI stack links + bootstraps
      6. Windows GUI      - StackConnectWindowsApp (SwiftCrossUI/WinUI) FULL Home (Blocks B+C+D) + StackHomeCore compile (build only)
      7. GUI screen test  - (only with -RunGui) register package identity + LAUNCH the Home window

    The GUI gate (6) builds the COMPLETE Windows Home (T-E3), not just the
    earlier shell - Blocks B, C and D are all part of the StackConnectWindowsApp
    package, so a single `swift build` over the whole package compiles every
    Home surface:
      - Block B (T-B1..T-B6, US-011/US-001/US-002/US-003/US-004): the route
        stack + WindowsHomeCoordinator, the SQLite + file-prefs DI bootstrap, the
        toolbar, provider cards (incl. Settings cell) and the sync banner.
      - Block C (T-C1..T-C3, US-006/US-007/US-008/US-009): the widget container +
        empty state, the 3 widget views (In Review / Awaiting Release / Recent
        Reviews) and the Customize Widgets full-screen panel.
      - Block D (T-D1..T-D4, US-005/US-012): the inline alert banner (Expired /
        Expiring Soon), the cold-start / loading state, the v1 navigation
        placeholders (accountsList / settings / appDetail / reviewDetail /
        allReviews / reimport) and the responsive 2-col->1-col reflow.
    All of it builds against StackHomeCore (US-010 AC-3: the shared core compiles
    when imported by StackConnectWindowsApp); StackHomeCore is a dependency of the
    GUI package, so this gate recompiles it as part of the GUI build. The build is
    over the whole package (no single product/target filter), so the entire Home
    surface above is exercised on every run.

    With -RunGui, after gate 6 builds the GUI, the script runs
    StackConnectWindowsApp\Packaging\Register-StackConnectApp.ps1 to give the .exe
    package identity (HANDOVER section 8: skips the Windows App Runtime 1.5 bootstrap),
    bundle the Swift runtime DLLs, and LAUNCH the window via package activation.
    The launch is non-blocking (Start-Process), so the run still finishes and
    prints its summary - confirm the window renders on screen. Needs Developer
    Mode ON. Build gate 6 must have passed (the launch is skipped otherwise).

    Each gate runs independently; one failing does not stop the others. The full
    console output is also written to a timestamped .log file, and a summary
    table plus an overall exit code (0 = all ran gates passed) are printed.

.PARAMETER Pull
    Run `git pull` in the repo root before testing.

.PARAMETER Clean
    Wipe all SwiftPM state before testing: each package's .build and
    Package.resolved, plus the global SwiftPM cache
    (%LOCALAPPDATA%\org.swift.swiftpm). Forces a fresh dependency resolution -
    use this after changing a branch-based dependency.

.PARAMETER SkipSDK
    Skip the (slow) App Store Connect SDK build gate.

.PARAMETER CleanGui
    Wipe ONLY the GUI package's SwiftPM state (StackConnectWindowsApp\.build,
    its Package.resolved, and the .scwapp scratch) before testing - a light
    alternative to -Clean that forces a fresh resolution of the GUI package
    without rebuilding the slow ASC SDK. Use this after the GUI Package.swift
    changes (e.g. new dependencies) so the GUI gate picks them up. Implied by
    -Clean (which already wipes everything).

.PARAMETER RunGui
    After the GUI build gate, register package identity and LAUNCH the window
    (the on-screen test) via Packaging\Register-StackConnectApp.ps1. Needs
    Developer Mode ON. Without this switch gate 6 is build-only.

.PARAMETER FirebaseServiceAccount
    Path to a Firebase service-account .json (sets FIREBASE_SA_JSON).

.PARAMETER PlayServiceAccount
    Path to a Google Play service-account .json (sets PLAY_SA_JSON).

.PARAMETER LogPath
    Where to write the log. Defaults to Test-WindowsPort-<timestamp>.log in the
    repo root.

.EXAMPLE
    .\Test-WindowsPort.ps1 -Pull -Clean

.EXAMPLE
    .\Test-WindowsPort.ps1 -SkipSDK -LogPath C:\temp\run.log

.EXAMPLE
    # Build the GUI and actually open the window (on-screen test):
    .\Test-WindowsPort.ps1 -SkipSDK -RunGui

.EXAMPLE
    # After the GUI Package.swift changed: refresh just the GUI package and
    # open the Home window, skipping the slow SDK gates:
    .\Test-WindowsPort.ps1 -Pull -SkipSDK -CleanGui -RunGui

.EXAMPLE
    # Full E2E smoke for T-E4 (all 7 gates + GUI launch for manual verification):
    .\Test-WindowsPort.ps1 -Pull -Clean -RunGui

.NOTES
    After a -RunGui pass, the test plan (docs/test-plans/T-E4-vm-e2e-smoke.md)
    documents the manual verification steps for US-001 through US-012. Confirm
    the window renders, then walk through the checklist.

    Persistence file: %APPDATA%\StackConnect\prefs.json
    SQLite store:     %APPDATA%\StackConnect\store.sqlite
#>
[CmdletBinding()]
param(
    [switch]$Pull,
    [switch]$Clean,
    [switch]$CleanGui,
    [switch]$SkipSDK,
    [switch]$RunGui,
    [string]$FirebaseServiceAccount,
    [string]$PlayServiceAccount,
    [string]$LogPath
)

$root = $PSScriptRoot
$results = [ordered]@{}

# Short scratch path for the StackConnectWindows build. The repo often lives
# under a deep folder (e.g. OneDrive\Desktop\repos\...), and that package pulls
# the App Store Connect SDK whose generated OpenAPI filenames are very long, so
# the default `.build` tree blows past Windows' 260-char MAX_PATH. Building into
# a short root (C:\Users\<you>\.scw) keeps every path under the limit.
$scwScratch = Join-Path $env:USERPROFILE ".scw"
# Separate short scratch path for the GUI package (its own build tree).
$scwAppScratch = Join-Path $env:USERPROFILE ".scwapp"

if (-not $LogPath) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $LogPath = Join-Path $root "Test-WindowsPort-$stamp.log"
}

function Write-Header([string]$Text) {
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Invoke-Clean {
    Write-Header "Clean (build artifacts + SwiftPM cache)"
    $paths = @(
        (Join-Path $root "WindowsPoC\.build"),
        (Join-Path $root "WindowsPoC\Package.resolved"),
        (Join-Path $root "ASCBuildProbe\.build"),
        (Join-Path $root "ASCBuildProbe\Package.resolved"),
        (Join-Path $root "StackConnectWindows\.build"),
        (Join-Path $root "StackConnectWindows\Package.resolved"),
        (Join-Path $root "StackConnectWindowsApp\.build"),
        (Join-Path $root "StackConnectWindowsApp\Package.resolved"),
        $scwScratch,
        $scwAppScratch,
        (Join-Path $env:LOCALAPPDATA "org.swift.swiftpm"),
        (Join-Path $env:LOCALAPPDATA "org.swift.swiftpm\cache")
    )
    foreach ($p in ($paths | Select-Object -Unique)) {
        if (Test-Path $p) {
            Write-Host "  removing  $p"
            Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue
        } else {
            Write-Host "  (absent)  $p"
        }
    }
}

function Invoke-CleanGui {
    # Light clean: only the GUI package's resolution + build trees, so a changed
    # StackConnectWindowsApp\Package.swift (new deps, backend env var) resolves
    # fresh without touching the slow ASC SDK build. The global SwiftPM cache is
    # left intact (local path deps don't need re-downloading).
    Write-Header "Clean GUI package (StackConnectWindowsApp resolution + scratch)"
    $paths = @(
        (Join-Path $root "StackConnectWindowsApp\.build"),
        (Join-Path $root "StackConnectWindowsApp\Package.resolved"),
        $scwAppScratch
    )
    foreach ($p in ($paths | Select-Object -Unique)) {
        if (Test-Path $p) {
            Write-Host "  removing  $p"
            Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue
        } else {
            Write-Host "  (absent)  $p"
        }
    }
}

function Invoke-Gate {
    param(
        [string]$Name,
        [string]$WorkingDirectory,
        [string[]]$SwiftArgs
    )
    Write-Header $Name
    Push-Location $WorkingDirectory
    try {
        # Merge stderr into the success stream so swift's errors land in the
        # transcript log (Start-Transcript does not capture native stderr).
        & swift @SwiftArgs 2>&1 | ForEach-Object { Write-Host $_ }
        $ok = ($LASTEXITCODE -eq 0)
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        $ok = $false
    } finally {
        Pop-Location
    }
    $script:results[$Name] = $ok
    if ($ok) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
    }
}

# --- Run (wrapped so the whole console session is captured to the log) --------

$exitCode = 0
Start-Transcript -Path $LogPath -Force | Out-Null
try {
    Write-Host "StackConnect Windows-port test run"
    Write-Host "log: $LogPath"

    if (-not (Get-Command swift -ErrorAction SilentlyContinue)) {
        Write-Host "Swift toolchain not found on PATH." -ForegroundColor Red
        Write-Host "Install it from https://www.swift.org/install/windows/ and open a new terminal." -ForegroundColor Yellow
        $exitCode = 2
        return
    }

    Write-Header "Toolchain"
    & swift --version

    if ($Pull) {
        Write-Header "git pull"
        Push-Location $root
        & git pull
        Pop-Location
    }

    if ($Clean) {
        Invoke-Clean
    } elseif ($CleanGui) {
        # -Clean already wipes the GUI package, so only run the light clean when
        # the full clean wasn't requested.
        Invoke-CleanGui
    }

    # TC-091: log the scratch paths so the reviewer can confirm MAX_PATH is
    # respected (both are under ~30 chars vs the 260-char limit).
    Write-Header "Scratch paths (TC-091: MAX_PATH mitigation)"
    Write-Host "  Headless: $scwScratch ($($scwScratch.Length) chars)"
    Write-Host "  GUI:      $scwAppScratch ($($scwAppScratch.Length) chars)"
    if ($scwScratch.Length -gt 40 -or $scwAppScratch.Length -gt 40) {
        Write-Host "  WARNING: scratch path exceeds 40 chars - MAX_PATH risk increases." -ForegroundColor Yellow
    } else {
        Write-Host "  OK: scratch paths are short." -ForegroundColor Green
    }

    if ($FirebaseServiceAccount) { $env:FIREBASE_SA_JSON = $FirebaseServiceAccount }
    if ($PlayServiceAccount)     { $env:PLAY_SA_JSON     = $PlayServiceAccount }

    Invoke-Gate -Name "Core PoC (SQLite + crypto + RS256 + PEM)" `
                -WorkingDirectory (Join-Path $root "WindowsPoC") `
                -SwiftArgs @("run", "StackConnectWindowsPoC")

    Invoke-Gate -Name "Secrets probe (Credential Manager)" `
                -WorkingDirectory (Join-Path $root "WindowsPoC") `
                -SwiftArgs @("run", "WindowsSecretsProbe")

    Invoke-Gate -Name "Credential store (WindowsCredentialStorable / KeyStorable)" `
                -WorkingDirectory (Join-Path $root "WindowsPoC") `
                -SwiftArgs @("run", "WindowsCredentialStoreProbe")

    if (-not $SkipSDK) {
        Invoke-Gate -Name "App Store Connect SDK build" `
                    -WorkingDirectory (Join-Path $root "ASCBuildProbe") `
                    -SwiftArgs @("build")

        # Headless Windows app: links the whole non-UI stack (storage + secrets +
        # crypto + providers + ASC SDK) into one executable and runs the B2
        # bootstrap. Depends on the SDK fork, so it is gated with the SDK build.
        # --scratch-path keeps the build tree short (see $scwScratch above) so the
        # SDK's long generated filenames don't overflow Windows MAX_PATH.
        Invoke-Gate -Name "Windows app bootstrap (StackConnectWindows, headless)" `
                    -WorkingDirectory (Join-Path $root "StackConnectWindows") `
                    -SwiftArgs @("run", "--scratch-path", $scwScratch, "StackConnectWindows")
    } else {
        Write-Header "App Store Connect SDK build"
        Write-Host "[SKIP] -SkipSDK was passed" -ForegroundColor Yellow
        Write-Header "Windows app bootstrap (StackConnectWindows, headless)"
        Write-Host "[SKIP] -SkipSDK was passed (depends on the SDK fork)" -ForegroundColor Yellow
    }

    # SwiftCrossUI GUI (T-E3): its own package, now hosting the COMPLETE Windows
    # Home (Blocks B+C+D) over the shared StackHomeCore - navigation + provider
    # cards + sync banner (T-B1..T-B6), widget container + 3 widget views +
    # Customize Widgets (T-C1..T-C3), and the alert banner / loading / v1 nav
    # placeholders / responsive reflow (T-D1..T-D4). The build below is `swift
    # build` over the ENTIRE StackConnectWindowsApp package (no product/target
    # filter), so it compiles every one of those files in one pass - the full
    # Home surface, not a subset. Build only - `swift run` would open the window
    # and block the script (use -RunGui to launch it). Independent of the SDK, so
    # it runs even with -SkipSDK. Building it also recompiles StackHomeCore, which
    # it depends on (US-010 AC-3: core compiles when imported by the GUI app).
    #
    # SwiftCrossUI's transitive deps (jpeg, swift-java, swift-argument-parser)
    # contain symlinks that git on Windows refuses to check out by default
    # ("unable to create symlink ...: Permission denied"). Set core.symlinks=false
    # so git writes those as plain files instead - they live only in plugin/sample/
    # test dirs, never in compiled sources. (Alternative: enable Developer Mode.)
    $symlinksCfg = (& git config --global core.symlinks) 2>$null
    if ($symlinksCfg -ne "false") {
        Write-Header "Configure git for SwiftCrossUI checkout"
        Write-Host "  setting: git config --global core.symlinks false" -ForegroundColor Yellow
        Write-Host "  (lets SwiftCrossUI's deps check out on Windows; revert with:" -ForegroundColor DarkGray
        Write-Host "   git config --global --unset core.symlinks)" -ForegroundColor DarkGray
        & git config --global core.symlinks false
    }

    # Force SwiftCrossUI's DefaultBackend to resolve to WinUIBackend only. Without
    # this, DefaultBackend's dependency list still drags GtkBackend -> Gtk ->
    # GtkCHelpers into the Windows build plan (the `.when(platforms: [.linux])`
    # condition doesn't prune the C helper target), and GtkCHelpers fails on the
    # missing <gtk/gtk.h>/<gdk/gdk.h> headers. Setting SCUI_DEFAULT_BACKEND makes
    # DefaultBackend depend on the named target alone, so the Gtk graph never
    # enters resolution. Changing it alters manifest evaluation, so a fresh
    # resolution is required (run with -Clean or delete the .scwapp scratch).
    $env:SCUI_DEFAULT_BACKEND = "WinUIBackend"
    Write-Host "  SCUI_DEFAULT_BACKEND = $env:SCUI_DEFAULT_BACKEND (TC-092)" -ForegroundColor DarkGray

    # To see the window: swift run --scratch-path $env:USERPROFILE\.scwapp StackConnectWindowsApp
    $guiBuildName = "Windows GUI build (StackConnectWindowsApp full Home B+C+D + StackHomeCore)"
    Invoke-Gate -Name $guiBuildName `
                -WorkingDirectory (Join-Path $root "StackConnectWindowsApp") `
                -SwiftArgs @("build", "--scratch-path", $scwAppScratch)

    # GUI screen test (only with -RunGui): the build above proves it compiles, but
    # actually opening the window needs package identity so the Windows App Runtime
    # 1.5 bootstrap is skipped (HANDOVER section 8). Register-StackConnectApp.ps1 bundles
    # the Swift runtime DLLs next to the .exe, registers the loose AppxManifest, and
    # launches via package activation (Start-Process - non-blocking, so the run
    # continues to the summary). The .exe lives in the GUI scratch's debug dir.
    if ($RunGui) {
        $guiLaunchName = "GUI screen test (register identity + launch window)"
        Write-Header $guiLaunchName
        if (-not $results[$guiBuildName]) {
            Write-Host "[SKIP] GUI build did not pass; nothing to launch." -ForegroundColor Yellow
            $results[$guiLaunchName] = $false
        } else {
            $register  = Join-Path $root "StackConnectWindowsApp\Packaging\Register-StackConnectApp.ps1"
            $guiExeDir = Join-Path $scwAppScratch "debug"
            try {
                # The child script sets $ErrorActionPreference='Stop' and throws on
                # any failure, so reaching the next line means it registered and
                # launched successfully.
                & $register -ExeDir $guiExeDir
                $results[$guiLaunchName] = $true
            } catch {
                Write-Host $_.Exception.Message -ForegroundColor Red
                $results[$guiLaunchName] = $false
            }
            if ($results[$guiLaunchName]) {
                Write-Host "[PASS] $guiLaunchName - confirm the window renders on screen." -ForegroundColor Green
                Write-Host ""
                Write-Host "  Manual verification checklist: docs\test-plans\T-E4-vm-e2e-smoke.md" -ForegroundColor DarkGray
                Write-Host "  Persistence file:  $env:APPDATA\StackConnect\prefs.json" -ForegroundColor DarkGray
                Write-Host "  SQLite store:      $env:APPDATA\StackConnect\store.sqlite" -ForegroundColor DarkGray
                Write-Host "  Scratch path:      $scwAppScratch" -ForegroundColor DarkGray
            } else {
                Write-Host "[FAIL] $guiLaunchName" -ForegroundColor Red
            }
        }
    }

    Write-Header "Summary"
    foreach ($name in $results.Keys) {
        if ($results[$name]) {
            Write-Host ("  PASS  {0}" -f $name) -ForegroundColor Green
        } else {
            Write-Host ("  FAIL  {0}" -f $name) -ForegroundColor Red
        }
    }

    $failed = @($results.Values | Where-Object { -not $_ }).Count
    Write-Host ""
    if ($failed -eq 0) {
        Write-Host "All gates passed." -ForegroundColor Green
        $exitCode = 0
    } else {
        Write-Host "$failed gate(s) failed." -ForegroundColor Red
        $exitCode = 1
    }
} finally {
    Stop-Transcript | Out-Null
    Write-Host ""
    Write-Host "Log saved to: $LogPath" -ForegroundColor Cyan
}

exit $exitCode
