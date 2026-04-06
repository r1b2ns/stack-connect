# StackConnect

A native iOS app to manage your **App Store Connect**, **Firebase**, and **Google Play** developer accounts from a single place. Built with SwiftUI for iOS 17+.

## Highlights

- 📱 **Multi-provider** — manage Apple, Firebase, and Google Play accounts in one app
- 🔐 **Secure storage** — credentials stored in Keychain, app data in SwiftData
- 💾 **Offline-first** — works without internet, syncs from API in the background
- 🤝 **Account sharing** — export encrypted account files to share with your team
- 🎨 **iPad ready** — adaptive layout via NavigationSplitView
- 💳 **Subscriptions** — StoreKit 2 with Individual, Team, and Lifetime plans

---

## Features

### App Store Connect

#### Apps Management
- List all apps with search, sort, and favorites
- Archive apps locally
- App detail with platform-grouped versions
- App icon, version, state, review pending indicator

#### Versions
- View all platforms (iOS, macOS, tvOS, etc.)
- Version detail with metadata, builds, and screenshots
- Edit Promotional Text, Description, What's New (read-only when state doesn't allow)
- Edit Keywords, Support URL, Marketing URL, Version, Copyright
- **Actions per state**:
  - Submit for Review (prepareForSubmission)
  - Cancel Review (waitingForReview / inReview)
  - Release (pendingDeveloperRelease)
  - Reject (pendingDeveloperRelease)
- Build selection with status filtering
- Screenshots preview, resolution picker, page navigation

#### App Information
- Bundle ID, SKU, Apple ID with copy-to-clipboard + haptic feedback
- Manage Localizations (multi-language)
- App Category picker
- Content Rights declaration
- Age Rating

#### App Privacy
- Privacy by locale
- Edit privacy policy URL, choices URL, and policy text

#### App Accessibility
- Accessibility declarations per device family
- Add, edit, publish, delete declarations

#### Customer Reviews
- Browse all customer reviews with infinite scroll pagination
- Filter by star rating (server-side via API)
- Rating distribution computed via parallel API calls
- Reply to reviews and delete responses

#### App Review Submissions
- App Review Information per version
- Submission tracking and status

#### App History
- Activity timeline of changes per app

#### Analytics
- **Installs & Deletes** — dual-line chart from CSV report
- **Downloads** — stacked bar chart by type (First-time, Manual update, Redownload, Restore)
- **Impressions** and **Product Page Views** from Discovery & Engagement report
- Date filter strip with "All" option
- Tip banner showing min/max data range
- Share button: exports all cached TSVs as zip
- File cache (configurable TTL) for fast subsequent loads

#### TestFlight
- Beta groups (Internal and External)
- Tester management with App Store Connect team picker
- Build assignment to groups
- Edit group settings (name, public link, feedback)
- Delete groups (External only)

#### User Access
- Team members with roles
- Filter by role
- Invite, edit, and delete users

### Firebase

- Project list and detail
- App list per project
- **Remote Config** — view, edit, duplicate parameters and conditions
- **Analytics Dashboard** — basic metrics
- **Cloud Messaging (FCM)** — campaigns with User Segment targeting

### Google Play

- App list with auto-discovery via Play Developer Reporting API
- Service Account JSON authentication

---

## Account Management

### Three Provider Types
- **App Store Connect**: API key (Issuer ID, Private Key ID, .p8 file)
- **Firebase**: Service Account JSON
- **Google Play**: Service Account JSON

### Granular Permissions
Each account has rules per resource:
- `apps`, `version`, `users`, `review`, `testFlight`, `analytics`

Each resource has 4 permission levels with hierarchy:
- `view` — read access
- `edit` — implies view
- `delete` — implies edit + view
- `add` — implies edit + view

### Account Origins
- **Created**: configured in the app, fully editable, can be exported
- **Imported**: received via shared file, cannot be exported

### Encrypted Export/Import
- Export account as `.scexport` binary file
- **AES-256-GCM** encryption with **HKDF** key derivation
- Fixed app salt + user password = unique encryption key
- File completely unreadable outside StackConnect
- Per-resource permission selection during export
- Import flow: file picker → password → name customization
- Duplicate credential detection on add and import

### Cascading Deletion
- Deleting an account removes all related apps, versions, and credentials
- "Delete All Accounts" option in Settings

---

## Subscriptions (StoreKit 2)

| Plan | Monthly | Yearly | One-time | Export |
|------|---------|--------|----------|--------|
| **Individual** | $3.99 | $39.99 | — | ❌ |
| **Team** | $7.99 | $79.99 | — | ✅ |
| **Lifetime** | — | — | $99.99 | ✅ |

- **Paywall**: horizontal carousel with 3 plans, billing toggle (Monthly/Yearly), Subscribe Now, Restore Purchases
- **Import Account** on the paywall: users with shared accounts unlock the app without subscribing
- **Export gating**: only Team and Lifetime can export accounts
- **Welcome sheet**: shown after subscription (first time only)

---

## Architecture

### Pattern: MVVM + Coordinator

Each module follows the structure:
```
Modules/ModuleName/
├── ModuleNameView.swift          # Factory + Entry + View
├── ModuleNameCoordinator.swift   # Route enum + Coordinator class
├── ModuleNameViewModel.swift     # Protocol + UiState + Implementation
└── Components/                   # Optional subviews
```

### Key Patterns
- **Factory**: each module exposes a `*ViewFactory.build(...)` static method
- **ViewModel Protocol**: all view models implement a generic protocol for testability
- **Coordinator**: each module has its own `*Coordinator: MainCoordinatorProtocol` for navigation
- **HomeCoordinator**: centralized navigation with `HomeRoute` enum (40+ routes)
- **Offline-first**: load from SwiftData first, then sync from API
- **PersistentStorable**: protocol abstraction over SwiftData
- **KeyStorable**: protocol abstraction over Keychain

### Storage
- **SwiftData**: app data, accounts, apps, versions, rules
- **Keychain**: credentials (Apple/Firebase/Google Play)
- **Files cache**: analytics CSVs in `Caches/analytics/{appId}/`

### Networking
- **APIProviderApple**: based on `appstoreconnect-swift-sdk`
- **APIProviderFirebase**: custom Swift package using JWT/OAuth2
- **APIProviderPlay**: custom Swift package for Google Play Developer API

### Encryption
- **CryptoKit** for AES-256-GCM
- **HKDF<SHA256>** key derivation
- Fixed 32-byte app salt + user password
- Random per-file salt + nonce

---

## Project Setup

### Requirements
- Xcode 16.3+
- iOS 17.0+ deployment target
- Ruby 3.x with Bundler (for Fastlane)
- XcodeGen

### Generating the Xcode Project

The Xcode project is managed by **XcodeGen**. Never edit `.xcodeproj` directly.

```bash
xcodegen generate --spec project.yml
```

Run this after:
- Creating or deleting any source file
- Adding or removing Swift package dependencies
- Changing build settings, schemes, or Info.plist properties

### Build Configurations
- **Debug** (`StackConnect Development` scheme): `zeroSixteen.stackconnect.dev`, automatic signing
- **Release** (`StackConnect Production` scheme): `zeroSixteen.stackconnect`, manual signing via match

### Schemes
- **StackConnect Development** — debug build with `StackConnectProductsDev.storekit`
- **StackConnect Production** — release build with `StackConnectProductsPrd.storekit`
- **StackConnectTests** — unit tests

### Dependencies
- `appstoreconnect-swift-sdk` — App Store Connect API
- `netfox` (DEBUG only) — network debugging
- `swift-crypto` — used by App Store Connect SDK
- Local packages:
  - `APIProviderFirebase`
  - `APIProviderPlay`
  - `StackProtocols`

---

## Fastlane

Fastlane is configured for CI/CD with the following lanes:

```bash
bundle exec fastlane test          # Run unit tests
bundle exec fastlane beta_dev      # Build & upload Dev to TestFlight
bundle exec fastlane beta          # Build & upload Production to TestFlight
bundle exec fastlane beta_all      # Both Dev and Production betas
bundle exec fastlane screenshots   # Upload App Store screenshots
bundle exec fastlane metadata      # Upload App Store metadata
bundle exec fastlane release       # Build and submit to App Store
```

### Setup
1. Copy `fastlane/.env.template` to `fastlane/.env`
2. Fill in App Store Connect API key credentials
3. Set `MATCH_GIT_URL` and `MATCH_PASSWORD`
4. Run `bundle install`
5. Run `bundle exec fastlane match appstore --app_identifier zeroSixteen.stackconnect`
6. Run `bundle exec fastlane match appstore --app_identifier zeroSixteen.stackconnect.dev`

### Code Signing
- Managed via **fastlane match** stored in a private GitHub repository
- Manual signing in xcconfig with `PROVISIONING_PROFILE_SPECIFIER`
- Certificate type: `Apple Distribution`

---

## Conventions

### Code Style
- **Logging**: use `Log.print` (os.Logger) — never `print()`
- **Localization**: all user-facing strings via `String(localized:)` in `Localizable.xcstrings`
- **View methods**: prefix with `build` (e.g., `buildHeader()`, `buildContent()`)
- **Sensitive data** → `KeychainStorable`
- **App data** → `SwiftDataStorable`

### Module Conventions
- Always use the **Settings module** as the structural template for new modules
- Coordinator protocol, ViewModel protocol, Factory pattern, Entry struct
- After creating/deleting source files, run `xcodegen generate`

### Testing
- Test ViewModels and Services
- Use `MockPersistentStorable` and `MockKeyStorable`
- Run via `bundle exec fastlane test` or Xcode Test Navigator

---

## Project Structure

```
stack-connect/
├── StackConnect/
│   ├── App/                          # App entry point, AppDelegate
│   ├── Models/                       # Data models (Codable)
│   ├── Modules/                      # Feature modules (MVVM + Coordinator)
│   │   ├── Home/
│   │   ├── AccountsList/
│   │   ├── AppList/
│   │   ├── AppDetail/
│   │   ├── VersionDetail/
│   │   ├── AppAnalytics/
│   │   ├── TestFlight/
│   │   ├── RatingsReviews/
│   │   ├── Settings/
│   │   ├── Subscription/
│   │   └── ... (Firebase, Google Play, etc.)
│   ├── Infra/
│   │   ├── Providers/
│   │   │   ├── Apple/                # AppleAccountConnection, AnalyticsReportService
│   │   │   ├── Firebase/
│   │   │   └── GooglePlay/
│   │   ├── Subscription/             # SubscriptionService, .storekit configs
│   │   ├── Crypto/                   # AccountCrypto (AES-256-GCM)
│   │   └── DS/                       # Design system components
│   ├── Storage/                      # PersistentStorable, KeychainStorable
│   ├── Resources/                    # Assets, Localizable.xcstrings
│   └── Configs/
├── Packages/
│   ├── APIProviderFirebase/
│   ├── APIProviderPlay/
│   └── StackProtocols/
├── Configs/
│   ├── Debug.xcconfig
│   └── Release.xcconfig
├── fastlane/
│   ├── Fastfile
│   ├── Appfile
│   ├── Matchfile
│   └── metadata/
├── project.yml                       # XcodeGen specification
└── Gemfile                           # Fastlane dependencies
```

---

## Contributing

1. Branch from `master` with descriptive name (`feat/`, `fix/`, `chore/`)
2. Run `xcodegen generate` after creating/deleting files
3. Verify build: `xcodebuild build -scheme "StackConnect Development" -destination "generic/platform=iOS Simulator"`
4. Open PR against `master`

---

## License

Copyright © 2026 Rubens Machion. All rights reserved.
