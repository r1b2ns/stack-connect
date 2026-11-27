# Contributing to StackConnect

Thanks for helping. Bug reports, translations, documentation and code are all welcome. This guide covers how to get the app running, how the code is organized and what a pull request needs.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). Security issues should not be reported in public issues; see [SECURITY.md](SECURITY.md).

## Ways to help

- **Report a bug or ask for a feature.** Open an [issue](https://github.com/r1b2ns/stack-connect/issues/new/choose) using one of the forms. For open-ended ideas and questions, use [Discussions](https://github.com/r1b2ns/stack-connect/discussions).
- **Pick up an issue.** Issues labeled [good first issue](https://github.com/r1b2ns/stack-connect/labels/good%20first%20issue) are small and well scoped; [help wanted](https://github.com/r1b2ns/stack-connect/labels/help%20wanted) ones are bigger. Leave a comment before you start so work isn't duplicated.
- **Improve a translation.** See [Translations](#translations) below.

## Getting the app running

You need Xcode 16.3 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/r1b2ns/stack-connect.git
cd stack-connect
xcodegen generate --spec project.yml
open StackConnect.xcodeproj
```

- **The `.xcodeproj` is generated.** Never edit it by hand. Change `project.yml` and run `xcodegen generate --spec project.yml` again after adding or removing files, packages or build settings.
- **The Rust core is downloaded automatically.** `Packages/StackCoreRust` points SwiftPM at a prebuilt binary from the [stack-connect-core releases](https://github.com/r1b2ns/stack-connect-core/releases), so you don't need Rust.
- **Firebase is optional.** Without `StackConnect/Resources/GoogleService-Info.plist` (git-ignored) the app runs normally and analytics only go to the unified log.
- **DEBUG builds never send analytics or crash reports to Firebase.** Even with the plist bundled, Firebase is only configured for Remote Config and events go to the unified log only. To check events in Firebase DebugView, launch a DEBUG build with `-StackAnalyticsSendToFirebase YES -FIRDebugEnabled` (or set `STACK_ANALYTICS_SEND_TO_FIREBASE=1`). The opt-in is ignored in Release builds, unit tests and fake data mode.

### Running without a developer account: fake data mode

The **StackConnect Fake Data** scheme runs the app on invented, realistic accounts: no network, no Keychain and no API keys. It is the easiest way to explore the app and to work on most screens. It is DEBUG-only and never ships.

| Launch argument | Effect |
|---|---|
| `-StackFakeData YES` | Run on fake data (set in the scheme). |
| `-StackFakeDataReset YES` | Wipe the fake store and seed it again (tick it in *Edit Scheme › Run › Arguments*). |
| `-StackFakeDataWidgets YES` | Also feed the Home Screen widgets with the fake data. |

### Running on a device or with real accounts

The tracked configuration signs with the maintainer's team. To use your own, copy `Configs/Local.xcconfig.example` to `Configs/Local.xcconfig` (git-ignored), fill in your team, bundle identifier and App Group as the comments explain, and run `xcodegen generate` again. Simulator builds work with the no-team settings shown in the same file.

To connect a real App Store Connect account you need an [App Store Connect API key](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api) (`.p8`, key ID and issuer ID). For Firebase you need a service account JSON with access to the project.

## Project layout

| Path | What lives there |
|---|---|
| `StackConnect/App` | App entry point and app delegate |
| `StackConnect/Modules` | One folder per feature module |
| `StackConnect/Infra` | Shared infrastructure: design system (`Infra/DS`), providers, networking, logging, fake data |
| `StackConnect/Storage` | Storage abstractions (SwiftData, Keychain, UserDefaults) |
| `StackConnectWidget` | Home Screen widgets |
| `StackConnectTests` | Unit tests |
| `Packages/` | Local Swift packages: shared protocols, storage, crypto, API providers, the Rust core wrapper |
| `project.yml` | XcodeGen project definition |
| `Configs/` | Build settings (`.xcconfig`) |

## Architecture

MVVM with a Coordinator per module. A module looks like this:

```
Modules/ModuleName/
├── ModuleNameView.swift          # Factory + Entry + View
├── ModuleNameCoordinator.swift   # Route enum + Coordinator
├── ModuleNameViewModel.swift     # Protocol + UiState + implementation
└── Components/                   # Optional subviews
```

- The **Factory** (`ModuleNameViewFactory.build()`) is the only way other code creates the screen.
- The **Entry** is a private view that owns the `@StateObject`s (coordinator and view model).
- The **View** is generic over the view model protocol, which keeps it previewable and testable.
- The **ViewModel** is `@MainActor`, exposes one `uiState` struct and receives its dependencies (storage, services) through `init` with production defaults.
- Navigation goes through the module's coordinator and route enum.

When in doubt, copy the structure of an existing module close to what you are building.

## Conventions

- **Logging:** use `Log.print` (built on `os.Logger`), never `print()`. Example: `Log.print.info("[Module] message")`.
- **Strings:** every user-facing string uses `String(localized:)` and lives in `StackConnect/Resources/Localizable.xcstrings`.
- **Storage:** secrets (API keys, `.p8` keys, service accounts) go to `KeychainStorable`; app data goes to `SwiftDataStorable`.
- **Offline-first:** load from local storage first, then sync from the API.
- **Shared protocols** belong in the `StackProtocols` package.
- **Reusable UI:** when a view structure repeats, extract it into a design-system component under `StackConnect/Infra/DS` instead of copying it.
- **View builders:** private view-building methods are named `buildXxx()`.

## Tests

Every ViewModel and Service change needs unit tests. Use the mocks in `StackConnectTests/Mocks`, such as `MockPersistentStorable` and `MockKeyStorable`, instead of real storage or network.

Run the suite from Xcode (**⌘U** on the StackConnect scheme) or from the command line:

```bash
xcodebuild test -project StackConnect.xcodeproj -scheme StackConnect \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Use any simulator you have installed. Don't pass `CODE_SIGNING_ALLOWED=NO`: the tests need the App Group container, which doesn't exist in an unsigned build.

## Translations

The app is written in English and translated into German, Spanish (Spain and Mexico), French, Italian, Japanese, Korean, Dutch, Portuguese (Brazil and Portugal), Russian, Swedish and Traditional Chinese. Several languages are incomplete, so this is a great first contribution:

1. Open `StackConnect/Resources/Localizable.xcstrings` in Xcode.
2. Pick your language, filter by strings that need review or are untranslated, and fill them in.
3. Keep placeholders such as `%@` and `%lld` exactly as they are, and keep the tone short and plain.
4. Open a pull request with the `translation` label.

You don't need to run the app to translate, but checking your text on a simulator in that language helps catch strings that are too long.

## Pull requests

1. Fork the repository and create a branch from `master`.
2. Keep the change focused on one thing. Open an issue first for big changes, new providers or new dependencies.
3. Run `xcodegen generate --spec project.yml`, then make sure the app builds and the tests pass.
4. Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages, as the history does: `feat(reviews): add reply templates`, `fix(accounts): …`, `test: …`, `docs: …`.
5. Fill in the pull request template, including screenshots for UI changes (light and dark mode).

CI builds the app and runs the tests on every pull request. A maintainer will review your pull request, usually within a few days.

### App Review constraints

StackConnect ships on the App Store, so some changes are shaped by Apple's App Review Guidelines rather than by code:

- Don't present StackConnect as an Apple product: no Apple logos and nothing that looks like the official "Sign in with Apple" button.
- Work that isn't released yet stays behind a feature flag, and the store build must not mention it.
- Privacy claims in the UI must match the App Privacy label and [PRIVACY.md](PRIVACY.md).

If you're unsure whether a change is affected, ask in the issue.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
