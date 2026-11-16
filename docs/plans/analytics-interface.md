# Implementation Plan — Analytics interface with user opt-out

> Branch: `feature/analytics-interface`
> Paths below were checked against the current source on `master` (29cd88e).

## Goals

1. A single, provider-agnostic analytics interface that every part of the app calls.
2. Track **all** user-facing activity: screen views, button taps and meaningful actions (sync, submit, delete, export, …).
3. A user setting to turn sending off. It is **ON by default**.
4. When the user turns it **off**, the app sends **one last event** (`analytics_disabled`) and then sends nothing else until it is turned back on.

## Non-goals (for this branch)

- Choosing and integrating a concrete backend SDK (see [Open decisions](#open-decisions)). The first provider only logs through `Log.print`, so the whole pipeline can be built and tested without a vendor.
- Instrumenting the widget extension (`StackConnectWidget`).
- Crash reporting.

---

## 0. Findings that shape the plan

- **No analytics exists today.** There is no tracker, SDK or `GoogleService-Info.plist`. `Modules/Analytics*` are App Store Connect *report* screens, unrelated. To avoid confusion the new code uses the `Analytics` prefix only inside `Infra/Analytics/`, and event names are prefixed by domain, not by "analytics".
- **User settings already have a home:** `AppSetting` / `AppSettings` in `StackConnect/Infra/Settings/AppSettings.swift`, persisted in `UserDefaults`, with a compiled-in `defaultValue`. The opt-out is a new case there.
  It is a *user setting*, not a `FeatureFlag`, so `docs/FEATURE_FLAGS.md` does **not** change.
- **The Settings screen** (`Modules/Settings/SettingsView.swift` + `SettingsViewModel.swift`) already has a toggle pattern (`preReviewChecklistEnabled`) to copy.
- **ViewModels are `@MainActor` and take dependencies through `init` with defaults** (`storage: PersistentStorable? = nil`, `appSettings: AppSettings = .shared`). The tracker follows the same pattern, so it can be mocked in tests.
- **Size of the instrumentation:** ~57 modules, ~70 files with `Button`s. Instrumentation must be cheap per call site, so it needs a reusable helper instead of hand-written code in every view.

---

## 1. Architecture

```
View / ViewModel ──► AnalyticsTracking (protocol, StackProtocols)
                         │
                         ▼
                  AnalyticsService (app, Infra/Analytics)
                   │  gate: AppSetting.analyticsEnabled
                   ▼
           [AnalyticsProvider]  ← LogAnalyticsProvider (now)
                                ← <Vendor>AnalyticsProvider (later)
```

### 1.1 Event model — `StackProtocols/AnalyticsEvent.swift` + `Infra/Analytics/AnalyticsEvent+Factories.swift`

```swift
public struct AnalyticsEvent: Equatable, Sendable {
    let name: String                         // snake_case, e.g. "screen_view"
    let parameters: [String: AnalyticsValue]
}

/// Restricted value type: no free-form objects, keeps payloads PII-safe and Sendable.
public enum AnalyticsValue: Equatable, Sendable {
    case string(String), int(Int), double(Double), bool(Bool)
}
```

Typed factories (in the app, since they use the app enums) so call sites never build raw strings:

```swift
extension AnalyticsEvent {
    static func screenView(_ screen: AnalyticsScreen) -> Self
    static func buttonTap(_ button: AnalyticsButton, on screen: AnalyticsScreen) -> Self
    static func action(_ action: AnalyticsAction, on screen: AnalyticsScreen,
                       result: AnalyticsResult? = nil, parameters: [String: AnalyticsValue] = [:]) -> Self
    static let analyticsDisabled: Self       // the opt-out "last event"
    static let analyticsEnabled: Self
}
```

- `AnalyticsScreen: String` — one case per screen (`home`, `settings`, `appDetail`, `versionDetail`, …). Exhaustive enum = no typos, easy to audit.
- `AnalyticsButton: String` — tap identifiers (`addAccount`, `submitForReview`, `deleteAllAccounts`, …).
- `AnalyticsAction: String` — outcome events for async work (`syncApps`, `submitForReview`, `exportAccount`, …) with `AnalyticsResult` (`success` / `failure` / `cancelled`).
- Event names: `screen_view` (`screen_name`), `button_tap` (`button_name`, `screen_name`), `action` (`action_name`, `screen_name`, optional `result`, plus typed extra parameters — reserved keys always win), `analytics_disabled`, `analytics_enabled`. Names/keys live in `AnalyticsEventName` / `AnalyticsParameterKey`.
- Raw values are snake_case (`case appDetail = "app_detail"`).

Standard parameters added by the service on every event: `app_version`, `build_number`, `platform` (`ios`), `os_version`. **No user ID.**

### 1.2 App-facing protocol — `Packages/StackProtocols/.../AnalyticsTracking.swift`

Per the project rule "shared protocols go in `StackProtocols`". The protocol only uses the event type, so the event types move with it (`AnalyticsEvent`, `AnalyticsValue`) while the app-specific enums (`AnalyticsScreen`, …) stay in the app.

```swift
@MainActor
public protocol AnalyticsTracking: AnyObject, Sendable {   // Sendable: needed by the nonisolated EnvironmentKey default
    var isEnabled: Bool { get }
    func track(_ event: AnalyticsEvent)
    func setEnabled(_ enabled: Bool)
}
```

### 1.3 Backend sink — `Infra/Analytics/AnalyticsProvider.swift`

```swift
protocol AnalyticsProvider: Sendable {
    func send(_ event: AnalyticsEvent)
    func flush() async          // used right after the opt-out event
    func reset()                // clears any vendor-side identifiers when disabled
}
```

`LogAnalyticsProvider` writes `Log.print.info("[Analytics] screen_view {screen_name=settings}")`. Enabled in DEBUG; in RELEASE it is the only provider until a vendor is chosen.

### 1.4 Service — `Infra/Analytics/AnalyticsService.swift`

```swift
@MainActor
final class AnalyticsService: AnalyticsTracking {
    static let shared = AnalyticsService()

    init(providers: [any AnalyticsProvider] = [LogAnalyticsProvider()],
         settings: AppSettings = .shared,
         bundle: Bundle = .main,
         processInfo: ProcessInfo = .processInfo)

    var isEnabled: Bool { settings.isEnabled(.analyticsEnabled) }

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }          // the single gate
        dispatch(event)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }   // no-op, no duplicate events
        if enabled {
            settings.setEnabled(true, for: .analyticsEnabled)
            dispatch(.analyticsEnabled)
        } else {
            dispatch(.analyticsDisabled)            // the last event, sent while still enabled
            settings.setEnabled(false, for: .analyticsEnabled)
            pendingFlush = Task { for p in providers { await p.flush(); p.reset() } }  // awaited by tests
        }
    }
}
```

Rules this enforces:
- **Order matters on opt-out:** the `analytics_disabled` event is dispatched *before* the setting is persisted as `false`, then providers are flushed. Any `track` after that returns at the gate.
- Turning it off when already off, or on when already on, sends nothing.
- The gate is read from `AppSettings` on every call (cheap `UserDefaults` read), so there is no cached state that can drift.

### 1.5 Setting — `Infra/Settings/AppSettings.swift`

```swift
/// When ON, anonymous usage analytics are sent. Ships ON by default.
/// Turning it OFF sends a final `analytics_disabled` event and stops all sending.
case analyticsEnabled = "appSetting.analyticsEnabled"   // defaultValue: true
```

---

## 2. Settings UI

- New **Privacy** section in `SettingsView` (`buildPrivacySection()`), between "App Store Connect" and "About":
  - `Toggle` "Share usage analytics", caption "Sends anonymous usage data to help improve StackConnect".
  - Section footer explaining what is and is not collected (no account names, keys, bundle IDs or app data).
- `SettingsUiState.analyticsEnabled: Bool`, `SettingsViewModelProtocol.setAnalyticsEnabled(_:)`.
- `SettingsViewModel` gets `analytics: AnalyticsTracking = AnalyticsService.shared` and calls `analytics.setEnabled(_:)` — the ViewModel does **not** write the setting itself; the service owns it, so the "last event" logic lives in one place.
- All strings go to `Localizable.xcstrings` via `String(localized:)`.

---

## 3. Instrumentation strategy

Three mechanisms, one per kind of event, so every call site is a one-liner:

| What | How | Where |
|---|---|---|
| Screen views | `.trackScreen(.settings)` view modifier (fires on `onAppear`, so going back to a screen counts again — expected `screen_view` semantics) | Each module's main `View` body |
| Taps that only navigate (coordinator calls, sheets, links) | `StackTrackedButton(.addAccount, on: .home) { … } label: { … }` — DS component in `Infra/DS`, drop-in replacement for `Button` with `role` support | Views |
| Taps that trigger work + their outcome | `analytics.track(.buttonTap(...))` and `.action(..., result:)` inside the ViewModel method | ViewModels (testable) |

`.trackScreen` and `StackTrackedButton` read the tracker from a SwiftUI `EnvironmentValues.analytics` key, defaulting to `AnalyticsService.shared`, so previews and tests can inject a mock.

Files: `Infra/Analytics/AnalyticsEnvironment.swift` (environment key; the default is computed via `MainActor.assumeIsolated` because `EnvironmentKey.defaultValue` is nonisolated), `Infra/DS/Analytics/View+TrackScreen.swift` (`StackTrackScreenModifier` + `View.trackScreen(_:)`), `Infra/DS/Analytics/StackTrackedButton.swift` (`init(_ button:on:role:action:label:)` plus a `Text` convenience `init(_ title:button:on:role:action:)`).

### 3.1 Privacy rules (enforced in review)

- Parameters only from the typed enums, booleans, counts and durations.
- **Never** send account names, issuer IDs, key IDs, bundle IDs, app names, version strings of the user's apps, review text, emails, or any error message text (send an error *category* instead).
- No device/user identifier is generated by us.

---

## 4. Delivery — tasks

Each task ends with `xcodegen generate --spec project.yml` + `xcodebuild build` green, and tests green.

### T1 — Core infrastructure
- `AnalyticsEvent`, `AnalyticsValue`, `AnalyticsTracking` in `StackProtocols`.
- `AnalyticsScreen`, `AnalyticsButton`, `AnalyticsAction`, `AnalyticsResult`, `AnalyticsProvider`, `LogAnalyticsProvider`, `AnalyticsService` in `StackConnect/Infra/Analytics/`.
- `AppSetting.analyticsEnabled` (default `true`).
- Tests (`StackConnectTests/Infra/AnalyticsServiceTests.swift`, isolated `UserDefaults(suiteName:)` + `MockAnalyticsProvider`):
  - default is enabled and events reach providers;
  - disabling sends exactly one `analytics_disabled` event, then later `track` calls send nothing;
  - disabling twice sends one event total;
  - re-enabling sends `analytics_enabled` and resumes tracking;
  - flush/reset are called on opt-out;
  - standard parameters are attached.

### T2 — Settings toggle
- Privacy section, UiState, ViewModel method, strings.
- `MockAnalyticsTracker` in `StackConnectTests/Mocks/` (`MockAnalyticsProvider` lives there too).
- `SettingsViewModelTests`: initial state reflects tracker, toggle forwards to `setEnabled`.

### T3 — SwiftUI helpers
- `View.trackScreen(_:)` modifier, `EnvironmentValues.analytics`, `StackTrackedButton` DS component. First usage: `.trackScreen(.settings)` on `SettingsView`.
- Tests (`StackConnectTests/Views/AnalyticsViewHelpersTests.swift`) for the modifier/button side effects and the environment default/override, using `MockAnalyticsTracker`.

### T4 — Screen views across all modules
- `AnalyticsScreen` is already seeded in T1 with one case per module main view and notable sheet; add any missing ones and `.trackScreen(...)` to each module's main view (~57 modules), including sheets (Welcome, Release Notes, Pre-submit checklist, pickers).

### T5 — Taps and actions, by area
Split into reviewable chunks:
- T5a Home, Accounts, Add Account, Settings
- T5b Apps, App Detail, Versions, Submissions, App Review, Pre-submit
- T5c TestFlight, Builds, Beta groups/testers
- T5d Certificates, Identifiers, Profiles, Devices, Users
- T5e Analytics reports, Ratings & Reviews, Reply templates
- T5f Firebase (projects, apps, Remote Config, Messaging) and Google Play

For each: navigation taps via `StackTrackedButton`, work taps + outcomes in the ViewModel, ViewModel tests asserting the events with `MockAnalyticsTracker`.

### T6 — Real backend provider: Firebase Analytics (done)
- Add the SDK in `project.yml`, implement `<Vendor>AnalyticsProvider`, map `flush`/`reset` to the vendor's API, and make sure the vendor SDK's own automatic collection is off when the setting is off (from app launch, not only after toggling).
- Update the App Store privacy "nutrition label" and `README.md`.

**What was done**
- **SDK.** `firebase-ios-sdk` pinned with `exactVersion: 13.1.1` (latest stable release at least two weeks old at the time). Product `FirebaseAnalyticsCore`, the no-IDFA variant (backed by `GoogleAppMeasurementCore`, no `AdSupport`, no on-device conversion). Linked to the `StackConnect` app target only, never to the widget or the test target.
- **Optional config file.** `StackConnect/Resources/GoogleService-Info.plist` is git-ignored. It is picked up by the `StackConnect` folder glob only when present at `xcodegen generate` time. It is deliberately *not* an explicit `optional: true` source: XcodeGen still emits that file reference, and the build then fails with "Build input file cannot be found" when the file is missing.
- **Provider.** `FirebaseAnalyticsProvider` is a thin forwarder to `Analytics.logEvent`. The mapping and limits live in the Firebase-free `FirebaseAnalyticsPayload` (unit tested without a configured `FirebaseApp`):
  - `screen_view` / `screen_name` already equal `AnalyticsEventScreenView` / `AnalyticsParameterScreenName`; other events pass through as-is.
  - `string` → `NSString`, `int` → `NSNumber` (Int64), `double` → `NSNumber` (non-finite dropped), `bool` → `"true"`/`"false"` (GA4 custom dimensions are text).
  - Event and parameter names must match `[A-Za-z][A-Za-z0-9_]*`, have no reserved prefix (`firebase_`, `google_`, `ga_`) and not be a reserved event name (`first_open`, `session_start`, …). Unusable event names drop the event; unusable parameter names drop the parameter. Names over 40 characters are truncated, string values over 100 characters are truncated, and only the first 25 parameters (sorted by key) are kept. Everything is logged; nothing traps.
  - `flush()` is a no-op (Firebase has no public flush). `reset()` is also a no-op: `resetAnalyticsData()` is deliberately not called, because it deletes the queued `analytics_disabled` event, which the product requires to be sent. Collection is stopped through `setCollectionEnabled(false)`.
- **Collection switch.** `AnalyticsProvider` gained `setCollectionEnabled(_:)` with a default no-op. `AnalyticsService` calls it:
  - at launch, through `applyCollectionSetting()`, with the persisted setting;
  - on opt-in, after persisting `true` and before dispatching `analytics_enabled`;
  - on opt-out, inside `pendingFlush`, in the order `send(analytics_disabled)` → `flush()` → `setCollectionEnabled(false)` → `reset()`. The disabled event is always handed to the SDK before collection is turned off.
- **Bootstrap.** `AnalyticsService.shared` is built with `AnalyticsBootstrap.makeDefaultProviders()`. When the plist is bundled (and the process is not hosting XCTest), it calls `FirebaseApp.configure()` and uses `[FirebaseAnalyticsProvider]`, plus `LogAnalyticsProvider` in DEBUG. Otherwise it logs that Firebase is not configured and uses only `LogAnalyticsProvider`. `StackConnectApp.init` calls `AnalyticsService.shared.applyCollectionSetting()` first, so configuration and the opt-out state are applied before the app delegate or any view runs. The test-friendly `AnalyticsService.init(providers:settings:bundle:processInfo:)` is unchanged.
- **Tracking gap fixed.** The Home "Review Agreements" `Link` now uses `.trackOpenURL(.reviewAgreements, on: .home)`.

**Info.plist privacy keys (app target, via `project.yml`)**

| Key | Value | Why |
|-----|-------|-----|
| `FIREBASE_ANALYTICS_COLLECTION_ENABLED` | `NO` | Nothing is collected until `AnalyticsService` enables collection for a user whose setting is ON (no `first_open` for opted-out users). |
| `FirebaseAutomaticScreenReportingEnabled` | `NO` | The app sends `screen_view` itself. |
| `GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS` | `NO` | No ad personalization. |
| `GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_USER_DATA` | `NO` | Consent mode: no user data for ads. |
| `GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE` | `NO` | Consent mode: no ad storage. |
| `GOOGLE_ANALYTICS_DEFAULT_ALLOW_ANALYTICS_STORAGE` | `YES` | Analytics storage, still gated by the collection switch above. |
| `GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED` | `NO` | No IDFV. |
| `GOOGLE_ANALYTICS_REGISTRATION_WITH_AD_NETWORK_ENABLED` | `NO` | No SKAdNetwork registration. |

**Known limitation.** Firebase has no public flush API, so delivery of `analytics_disabled` is best-effort: it is logged before collection is disabled and is no longer wiped (`resetAnalyticsData()` is not called), but the upload happens on the SDK's own schedule. The app instance ID and any data already stored by Firebase are therefore kept on the device after opt-out.

**Still open.** The App Store privacy "nutrition label" must be updated in App Store Connect by hand: "Product Interaction" (Analytics, not linked to the user, not used for tracking) and, because Firebase generates an app instance ID, "Device ID" (Analytics, not linked, not tracking). Also review the Firebase SDK privacy manifest in the archive's privacy report.

---

## Open decisions

1. **Backend vendor** — Decided: Firebase Analytics (see T6). Alternatives considered: TelemetryDeck, PostHog, own endpoint.
2. **Re-enable event** — plan sends `analytics_enabled` when the user turns it back on. Drop it if only the opt-out event is wanted.
3. **First-launch disclosure** — the setting is ON by default; consider a line in the Welcome screen saying anonymous analytics are on and can be turned off in Settings.
