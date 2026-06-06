<#
.SYNOPSIS
  Gives the built StackConnectWindowsApp.exe a package IDENTITY so the WinUI /
  Windows App Runtime 1.5 bootstrap is skipped (HANDOVER §8). Registers the
  sparse AppxManifest.xml loose (Developer Mode) next to the SwiftPM-built .exe,
  then launches the app through its package activation so the process actually
  runs with identity.

.PARAMETER ExeDir
  Folder holding StackConnectWindowsApp.exe. Default: the `swift run --scratch-path`
  debug dir ($env:USERPROFILE\.scwapp\debug).

.PARAMETER NoLaunch
  Register only; do not start the app.
#>
[CmdletBinding()]
param(
    [string]$ExeDir = (Join-Path $env:USERPROFILE ".scwapp\debug"),
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$pkgRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path

# SwiftPM makes `.build\debug` (here `.scwapp\debug`) a SYMLINK to the
# arch-specific output (aarch64-unknown-windows-msvc\debug). Add-AppxPackage
# -Register refuses paths that traverse a reparse point ("untrusted mount
# point", 0x800701C0), so resolve to the real directory first.
if (Test-Path -LiteralPath $ExeDir) {
    $item = Get-Item -LiteralPath $ExeDir
    if ($item.LinkType -eq 'SymbolicLink') {
        $target = @($item.Target)[0]
        if (-not [System.IO.Path]::IsPathRooted($target)) {
            $target = Join-Path (Split-Path -Parent $ExeDir) $target
        }
        $ExeDir = [System.IO.Path]::GetFullPath($target)
        Write-Host "Resolved symlinked output dir -> $ExeDir"
    }
}

$exePath  = Join-Path $ExeDir "StackConnectWindowsApp.exe"

if (-not (Test-Path $exePath)) {
    throw "StackConnectWindowsApp.exe not found at '$exePath'. Build it first: " +
          "swift run --scratch-path `$env:USERPROFILE\.scwapp StackConnectWindowsApp"
}

# When launched via package activation the process gets a clean environment
# WITHOUT the Swift toolchain on PATH, so the Swift runtime DLLs (swift_Concurrency,
# swiftCore, Foundation, the VC++ redist, …) that `swift run` finds via PATH go
# missing ("swift_Concurrency.dll was not found"). Bundle them next to the .exe so
# the loader finds them in the app dir.
$runtimeBin = ($env:PATH -split ';' | Where-Object { $_ -match '\\Swift\\Runtimes\\.*\\usr\\bin' } | Select-Object -First 1)
if (-not $runtimeBin) {
    $swift = (Get-Command swift -ErrorAction SilentlyContinue).Source
    if ($swift) {
        $cand = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $swift)))) "Runtimes"
        $runtimeBin = Get-ChildItem $cand -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName "usr\bin" } |
            Where-Object { Test-Path $_ } | Select-Object -First 1
    }
}
if (-not $runtimeBin -or -not (Test-Path $runtimeBin)) {
    throw "Could not locate the Swift runtime bin dir (…\Swift\Runtimes\<ver>\usr\bin)."
}
Write-Host "Bundling Swift runtime DLLs from: $runtimeBin"
Copy-Item (Join-Path $runtimeBin "*.dll") $ExeDir -Force

# The manifest references the .exe and its logos by relative path, so they must
# sit beside it. Copy the manifest + assets into the exe dir.
Copy-Item (Join-Path $pkgRoot "AppxManifest.xml") (Join-Path $ExeDir "AppxManifest.xml") -Force
Copy-Item (Join-Path $pkgRoot "Assets") (Join-Path $ExeDir "Assets") -Recurse -Force

$manifestInExe = Join-Path $ExeDir "AppxManifest.xml"

# Re-register cleanly (a stale registration pins the old exe dir / version).
Get-AppxPackage "StackConnect.WindowsApp" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }

Write-Host "Registering loose manifest: $manifestInExe"
Add-AppxPackage -Register $manifestInExe

$pkg = Get-AppxPackage "StackConnect.WindowsApp"
if (-not $pkg) { throw "Registration reported success but package is not present." }
$pfn   = $pkg.PackageFamilyName
$appId = "StackConnectWindowsApp"
Write-Host "Registered. PackageFamilyName = $pfn"
Write-Host "Activation target: shell:AppsFolder\$pfn!$appId"

if ($NoLaunch) { return }

# Launch through package activation so the process gets identity (raw double-click
# of the loose .exe would NOT carry identity → bootstrap would still run).
Write-Host "Launching..."
Start-Process "shell:AppsFolder\$pfn!$appId"
