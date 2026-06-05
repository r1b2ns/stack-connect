<#
.SYNOPSIS
    Runs the StackConnect Windows-port phase-3 gates and prints a summary.

.DESCRIPTION
    Executes the three validation gates on the Windows Swift toolchain:
      1. Core PoC      — SQLite + AES-GCM/PBKDF2 + RS256 + PEM
      2. Secrets probe — Windows Credential Manager round-trip
      3. ASC SDK build — does appstoreconnect-swift-sdk compile on Windows

    Each gate runs independently; one failing does not stop the others. A
    summary table and an overall exit code (0 = all ran gates passed) are
    printed at the end.

.PARAMETER Pull
    Run `git pull` in the repo root before testing.

.PARAMETER SkipSDK
    Skip the (slow) App Store Connect SDK build gate.

.PARAMETER FirebaseServiceAccount
    Path to a Firebase service-account .json to also exercise PEM parsing on a
    real key (sets FIREBASE_SA_JSON for the core PoC).

.PARAMETER PlayServiceAccount
    Path to a Google Play service-account .json (sets PLAY_SA_JSON).

.EXAMPLE
    .\Test-WindowsPort.ps1

.EXAMPLE
    .\Test-WindowsPort.ps1 -Pull -FirebaseServiceAccount C:\keys\firebase.json
#>
[CmdletBinding()]
param(
    [switch]$Pull,
    [switch]$SkipSDK,
    [string]$FirebaseServiceAccount,
    [string]$PlayServiceAccount
)

$root = $PSScriptRoot
$results = [ordered]@{}

function Write-Header([string]$Text) {
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
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
        & swift @SwiftArgs
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

# --- Preconditions -----------------------------------------------------------

if (-not (Get-Command swift -ErrorAction SilentlyContinue)) {
    Write-Host "Swift toolchain not found on PATH." -ForegroundColor Red
    Write-Host "Install it from https://www.swift.org/install/windows/ and open a new terminal." -ForegroundColor Yellow
    exit 2
}

Write-Header "Toolchain"
& swift --version

if ($Pull) {
    Write-Header "git pull"
    Push-Location $root
    & git pull
    Pop-Location
}

if ($FirebaseServiceAccount) { $env:FIREBASE_SA_JSON = $FirebaseServiceAccount }
if ($PlayServiceAccount)     { $env:PLAY_SA_JSON     = $PlayServiceAccount }

# --- Gates -------------------------------------------------------------------

Invoke-Gate -Name "Core PoC (SQLite + crypto + RS256 + PEM)" `
            -WorkingDirectory (Join-Path $root "WindowsPoC") `
            -SwiftArgs @("run", "StackConnectWindowsPoC")

Invoke-Gate -Name "Secrets probe (Credential Manager)" `
            -WorkingDirectory (Join-Path $root "WindowsPoC") `
            -SwiftArgs @("run", "WindowsSecretsProbe")

if (-not $SkipSDK) {
    Invoke-Gate -Name "App Store Connect SDK build" `
                -WorkingDirectory (Join-Path $root "ASCBuildProbe") `
                -SwiftArgs @("build")
} else {
    Write-Header "App Store Connect SDK build"
    Write-Host "[SKIP] -SkipSDK was passed" -ForegroundColor Yellow
}

# --- Summary -----------------------------------------------------------------

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
    exit 0
} else {
    Write-Host "$failed gate(s) failed." -ForegroundColor Red
    exit 1
}
