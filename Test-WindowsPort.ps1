<#
.SYNOPSIS
    Runs the StackConnect Windows-port phase-3 gates, with logging and cleanup.

.DESCRIPTION
    Executes the validation gates on the Windows Swift toolchain:
      1. Core PoC         — SQLite + AES-GCM/PBKDF2 + RS256 + PEM
      2. Secrets probe    — Windows Credential Manager round-trip (raw Win32)
      3. Credential store — WindowsCredentialStorable through KeyStorable
      4. ASC SDK build    — does appstoreconnect-swift-sdk compile on Windows
      5. Windows app      — headless StackConnectWindows: whole non-UI stack links + bootstraps
      6. Windows GUI      — StackConnectWindowsApp (SwiftCrossUI/WinUI) compiles (build only)

    Each gate runs independently; one failing does not stop the others. The full
    console output is also written to a timestamped .log file, and a summary
    table plus an overall exit code (0 = all ran gates passed) are printed.

.PARAMETER Pull
    Run `git pull` in the repo root before testing.

.PARAMETER Clean
    Wipe all SwiftPM state before testing: each package's .build and
    Package.resolved, plus the global SwiftPM cache
    (%LOCALAPPDATA%\org.swift.swiftpm). Forces a fresh dependency resolution —
    use this after changing a branch-based dependency.

.PARAMETER SkipSDK
    Skip the (slow) App Store Connect SDK build gate.

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
#>
[CmdletBinding()]
param(
    [switch]$Pull,
    [switch]$Clean,
    [switch]$SkipSDK,
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

    if ($Clean) { Invoke-Clean }

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

    # SwiftCrossUI GUI (B1b): its own package. Build only — `swift run` would open
    # a window and block the script. Independent of the SDK, so it runs even with
    # -SkipSDK.
    #
    # SwiftCrossUI's transitive deps (jpeg, swift-java, swift-argument-parser)
    # contain symlinks that git on Windows refuses to check out by default
    # ("unable to create symlink ...: Permission denied"). Set core.symlinks=false
    # so git writes those as plain files instead — they live only in plugin/sample/
    # test dirs, never in compiled sources. (Alternative: enable Developer Mode.)
    $symlinksCfg = (& git config --global core.symlinks) 2>$null
    if ($symlinksCfg -ne "false") {
        Write-Header "Configure git for SwiftCrossUI checkout"
        Write-Host "  setting: git config --global core.symlinks false" -ForegroundColor Yellow
        Write-Host "  (lets SwiftCrossUI's deps check out on Windows; revert with:" -ForegroundColor DarkGray
        Write-Host "   git config --global --unset core.symlinks)" -ForegroundColor DarkGray
        & git config --global core.symlinks false
    }

    # To see the window: swift run --scratch-path $env:USERPROFILE\.scwapp StackConnectWindowsApp
    Invoke-Gate -Name "Windows GUI build (StackConnectWindowsApp, SwiftCrossUI/WinUI)" `
                -WorkingDirectory (Join-Path $root "StackConnectWindowsApp") `
                -SwiftArgs @("build", "--scratch-path", $scwAppScratch)

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
