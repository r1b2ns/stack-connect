# StackConnect

A native iOS and Windows app to manage your **App Store Connect**, **Firebase**, and **Google Play** developer accounts from a single place. From a unified interface you can browse apps, edit version metadata, manage TestFlight groups, reply to customer reviews, view analytics, manage Firebase Remote Config and FCM campaigns, and securely export/import accounts to share with your team.

Built with SwiftUI for iOS 17+ and SwiftCrossUI (WinUI backend) for Windows 11.

## Running the app

### Requirements
- Xcode 16.3+
- iOS 17.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/r1b2ns/stack-connect.git
   cd stack-connect
   ```

2. Generate the Xcode project (the `.xcodeproj` is not checked in):
   ```bash
   xcodegen generate --spec project.yml
   ```

3. Open `StackConnect.xcodeproj` in Xcode.

4. Select the **StackConnect Development** scheme and run on a simulator or device.

> Re-run `xcodegen generate --spec project.yml` whenever source files, Swift package dependencies, or build settings change.

## Windows (experimental)

The Windows target lives on the `experiment/windows` branch. It reuses the shared `StackHomeCore` package (Foundation-pure business logic) and renders the Home screen using [SwiftCrossUI](https://github.com/moreSwift/swift-cross-ui) with the WinUI backend.

### Requirements

- Windows 11 (22H2+) with **Developer Mode** enabled
- [Swift toolchain for Windows](https://www.swift.org/install/windows/) (6.0+)
- Git for Windows 2.39+ (`git config --global core.symlinks false`)
- Visual Studio Build Tools 2022 (C++ workload) or Windows SDK 10.0.22621.0+
- [Windows App Runtime 1.5](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads) redistributable

### Building

Clone to a **short path** (e.g. `C:\repos\stack-connect`) to avoid MAX_PATH issues.

```powershell
git checkout experiment/windows
git pull

# Build the GUI app (StackHomeCore is compiled as a transitive dependency):
$env:SCUI_DEFAULT_BACKEND = "WinUIBackend"
cd StackConnectWindowsApp
swift build --scratch-path $env:USERPROFILE\.scwapp
```

### Running

```powershell
swift run --scratch-path $env:USERPROFILE\.scwapp StackConnectWindowsApp
```

Or use the packaging script for a proper WinUI identity registration:

```powershell
.\StackConnectWindowsApp\Packaging\Register-StackConnectApp.ps1 -ExeDir $env:USERPROFILE\.scwapp\debug
```

### Testing (automated gates)

The `Test-WindowsPort.ps1` script runs 7 validation gates covering the full stack:

```powershell
# All gates (build-only):
.\Test-WindowsPort.ps1 -Pull -Clean

# All gates + launch the GUI window:
.\Test-WindowsPort.ps1 -Pull -Clean -RunGui

# Skip the slow ASC SDK gate and just rebuild/launch the GUI:
.\Test-WindowsPort.ps1 -SkipSDK -CleanGui -RunGui
```

Gates:
1. Core PoC (SQLite + crypto + RS256 + PEM)
2. Secrets probe (Windows Credential Manager)
3. Credential store (WindowsCredentialStorable / KeyStorable)
4. ASC SDK build (skippable with `-SkipSDK`)
5. Windows app bootstrap (headless, non-UI stack)
6. Windows GUI build (full Home: Blocks B+C+D + StackHomeCore)
7. GUI screen test (register identity + launch window, requires `-RunGui`)

### Manual verification

After launching the GUI with `-RunGui`, follow the manual test plan at `docs/test-plans/T-E4-vm-e2e-smoke.md` which covers:
- All user stories (US-001 through US-012)
- Navigation push/pop with working Back
- Widget persistence across app restart
- Responsive reflow at different window widths

### Shared package: StackHomeCore

Business logic shared between iOS and Windows lives in `Packages/StackHomeCore/`. It is Foundation-pure (no SwiftUI/UIKit/Combine) and depends only on `StackProtocols`. Run its unit tests from macOS:

```bash
cd Packages/StackHomeCore
swift test
```

## Screenshots

| | | | |
|:-:|:-:|:-:|:-:|
| <img src="fastlane/screenshots/en-US/iPhone_6.5_1.png" width="200" /> | <img src="fastlane/screenshots/en-US/iPhone_6.5_2.png" width="200" /> | <img src="fastlane/screenshots/en-US/iPhone_6.5_3.png" width="200" /> | <img src="fastlane/screenshots/en-US/iPhone_6.5_4.png" width="200" /> |
| <img src="fastlane/screenshots/en-US/iPhone_6.5_5.png" width="200" /> | <img src="fastlane/screenshots/en-US/iPhone_6.5_6.png" width="200" /> | <img src="fastlane/screenshots/en-US/iPhone_6.5_7.png" width="200" /> | <img src="fastlane/screenshots/en-US/iPhone_6.5_8.png" width="200" /> |

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
