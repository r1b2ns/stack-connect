# Fake data mode (demo accounts)

A DEBUG-only mode that runs StackConnect entirely on invented, realistic data:
no network, no Keychain, no App Group store. Use it to compare screens with the
design prototypes and to capture App Store screenshots.

All the code lives in `StackConnect/Infra/FakeData/` and is wrapped in
`#if DEBUG`, so none of it ships in Release builds.

## Switches

| Switch | Effect |
|---|---|
| `-StackFakeData YES` (launch argument) or `STACK_FAKE_DATA=1` (environment) | Run on fake data. |
| `-StackFakeDataReset YES` or `STACK_FAKE_DATA_RESET=1` | Wipe the fake store, icon cache and preferences, then seed again. Only applies together with the switch above. |
| `-StackFakeDataWidgets YES` or `STACK_FAKE_DATA_WIDGETS=1` | Also feed the **home-screen widgets**: the WidgetKit snapshot (`WidgetDashboard.json`) and the widget icons are written to the App Group instead of the private fake folder. Use it to capture App Store screenshots of the widgets. It replaces the real widget snapshot until the next sync with real accounts (launch without the switch to restore it). Only applies together with `-StackFakeData YES`. |

The argument wins over the environment variable (`-StackFakeData NO` turns the
mode off even when `STACK_FAKE_DATA=1` is set). Parsing lives in
`FakeDataMode`.

**Xcode:** pick the **StackConnect Fake Data** scheme (Debug). Both arguments are
pre-filled in *Edit Scheme › Run › Arguments*; tick `-StackFakeDataReset YES`
to start from scratch.

**Command line:**

```bash
xcrun simctl launch <sim-id> zeroSixteen.stackconnect -StackFakeData YES -StackFakeDataReset YES
```

In fake mode the app also skips the welcome / release notes sheets, tips, the
notification permission prompt, netfox and Firebase Analytics.

## Isolation

`FakeDataBootstrap.install` runs once from `StackConnectApp.init`, before any
screen exists, and swaps every seam:

| Seam | Real | Fake |
|---|---|---|
| SwiftData store | App Group container (shared with the widget extension) | `Application Support/FakeData/FakeData.store` |
| `KeychainStorable.shared` | Keychain | `FakeKeyStorable` (in memory, re-seeded every launch) |
| `UserDefaultsStorable` default (Home layout, analytics prefs) | standard defaults | `zeroSixteen.stackconnect.fakedata` suite |
| `BackendEnvironment.coreProviders` (App Store Connect, Google Play) | Rust core | `FakeCoreProviderFactory` |
| `BackendEnvironment.firebaseProviders` | URLSession + service-account OAuth | `FakeFirebaseProviderFactory` → `FakeFirebaseServer` |
| `BackendEnvironment.ratingSummaryFetcher` | iTunes Lookup | `FakeRatingSummaryFetcher` |
| `WidgetIconCache.directoryOverride` | App Group container | `Application Support/FakeData/WidgetIcons` (App Group with `-StackFakeDataWidgets YES`) |
| `WidgetDashboardSnapshotStore.directoryOverride` (WidgetKit snapshot) | App Group container | `Application Support/FakeData/Widget` (App Group with `-StackFakeDataWidgets YES`) |
| `URLSession.shared` | network | `FakeNetworkURLProtocol`: renders fake icons / screenshots, refuses (and logs) everything else |

Real accounts, Keychain items and widget data are never read or written. The
WidgetKit extension can only read the App Group, so it keeps showing the real
snapshot — unless the app was launched with `-StackFakeDataWidgets YES`:

```bash
xcrun simctl launch <sim-id> zeroSixteen.stackconnect -StackFakeData YES -StackFakeDataReset YES -StackFakeDataWidgets YES
```

then add the In Review, Awaiting Release and Recent Reviews widgets to the home
screen. To look at the widget layouts without placing them, run
`WidgetRenderingTests` with `TEST_RUNNER_STACK_RENDER_WIDGETS_DIR=<folder>`: it
renders every widget family from the App Group snapshot into PNG files.

Only the `AccountModel`s are seeded into SwiftData, plus the Google Play
tracks cache of each Play app (as if Tracks had been opened the day before:
only an edit-based read fills it, so the background sync never does, and the
Home needs it to draw the staged rollout percentages). Apps, versions, phased
releases, reviews (both stores) and every other per-screen cache are filled by
the app's own sync paths from the fake providers (Home sync and widgets
included), exactly like with real accounts. Writes (replies, version edits, submissions, TestFlight,
users, provisioning, Remote Config publish, Firebase app edits…) succeed
against the in-memory backends and show up on the next read; they last until
the app quits. Dates are relative to the launch time, so the data stays fresh.

## What the fake accounts contain

All names, people, e-mails (`*.example`) and URLs are invented.

### App Store Connect — "Northwind Labs" (company team, Admin key)

| App | Platforms | Versions |
|---|---|---|
| Trailhead | iOS | 4.2.0 Ready for Sale, phased release day 3 of 7 · 4.1.2 / 4.1.0 / 4.0.0 replaced |
| Ledger Pocket | iOS, macOS | 2.7.0 In Review (iOS) / Waiting for Review (macOS) · 2.6.3 Ready for Sale |
| Mosaic Notes | iOS, visionOS | 5.1.0 Pending Developer Release (iOS) · 1.2.0 Rejected (visionOS) · 5.0.2 / 1.1.0 Ready for Sale |
| Lumen | tvOS | 1.4.0 Ready for Sale · 1.3.1 replaced |
| Orbit Focus | macOS | 3.0.0 Prepare for Submission · 2.9.4 Ready for Sale |

Per app: builds (one per version, plus TestFlight builds of the next version —
in testing, waiting for beta review, processing), internal / external / partner
beta groups with testers, beta app and build localizations, localized store
text (en-US + pt-BR, de-DE, fr-FR, es-ES, ja), screenshots per display type,
App Review contact and demo account, review submission history, 4–12 customer
reviews in several languages (ratings 1–5, some replied, one pending), App
Store rating per storefront, app info (categories, age rating, privacy URLs),
accessibility declarations, an App ID with capabilities, an App Store profile
and analytics reports (every catalog report, daily / weekly / monthly
instances with downloadable rows). Team-wide: 9 users (two pending invites,
two with limited app access), 11 devices (one disabled), 5 certificates (one
expiring in 18 days), a wildcard App ID, a team development profile and an
expired ad hoc profile.

### App Store Connect — "Jordan Avery (Personal)" (App Manager key)

Tide Tables (iOS, 1.6.0 Waiting for Review) and Pocket Haiku (iOS, 2.0.1 Ready
for Sale), 2 users, 3 devices, 2 certificates.

### Firebase — "Northwind Labs"

Two projects, **Trailhead** (`trailhead-prod-4f2a1`) and **Mosaic Notes**
(`mosaic-notes-91c0e`), each with iOS, Android and web apps (config files
downloadable), a Remote Config template with conditions, parameters and
parameter groups (publishing bumps the version), a linked Google Analytics
property with 31 days of active users, and FCM delivery stats for the Android
apps (sending a message succeeds).

### Google Play — "Northwind Labs"

| App | Package | Tracks (release lifecycle state from `releases.list`) |
|---|---|---|
| Trailhead | `com.northwind.trailhead` | production 4.2.0 rolling out 20% (+ 4.1.2 completed), open testing 4.3.0-beta2 **in review**, internal 4.3.0 (4305) **draft** + 4.3.0 (4303) |
| Ledger Pocket | `com.northwind.ledger` | production 2.8.1 **approved, not published** (managed publishing) + 2.7.0 **halted** at 10% + 2.6.3, closed testing, internal |
| Mosaic Notes | `com.northwind.mosaic` | production 5.2.0 **not approved** (+ 5.1.0 published), open testing 5.2.0 draft, internal |
| Harbor Transit | `com.northwind.harbor` | production 1.9.0 published, custom track `city-partners` (US + CA only), internal 2.0.0 **not sent for review** |

Releases not listed as above are published. Every app also has uploaded
bundles (one newer than any release, for the bundle picker).

The account has developer ID `4829103756618820931` (so the Users tab loads
right away; clear it in Account Settings to see the setup state) and ten users:
two admins (Dana Whitfield and `play-publisher@…`, the account's own service
account, which shows the self-protection), a release manager and a finance user
with account-wide permissions, Aiko Kimura and a support mailbox with per-app
grants, a pending invitation (expiring in 45 days), an expired invitation (to
try Resend), an access that expired 12 days ago and a CI service account.
Invites, permission and app-access changes, resends and removals succeed and
show up on the next read; the developer ID must be numeric, like Google's
(anything else is a 404). Track changes (`applyReleaseChange`) follow
the core's rules (fraction 0–1 exclusive, priority 0–5, uploaded version codes
only, release notes up to 500 characters per language, `ReleaseNotFound` for a release that is gone) and update the lifecycle
state (in review when sent for review, not sent for review otherwise).

Each app has store listings in 3–5 languages, app details (contact e-mail,
phone, website), a locally rendered icon and recent reviews (pt-BR, en-US,
de-DE, es, fr…, some replied). Replies are upserts and over 350 characters are
rejected, like Google. As with the real core, Play reviews carry no territory
and no device metadata.

## How to extend

The fakes sit behind the same seams production uses, so screens never branch on
fake mode.

- **New content:** edit the seeds — `AppStoreConnect/FakeAppStoreConnectSeeds.swift`,
  `GooglePlay/FakeGooglePlayCatalog.swift`, `Firebase/FakeFirebaseCatalog.swift`.
  New accounts go in `FakeDataSeeder.accounts` / `writeCredentials`; bump
  `FakeDataSeeder.seedVersion` so existing fake stores re-seed.
- **New core capability (e.g. the Google Play release summaries, bundles, track
  mutations or users of `docs/plans/google-play-releases.md`):**
  1. Re-vendor the core.
  2. Add the data to `FakeGooglePlayState` and seed it in `FakeGooglePlayCatalog`.
  3. In `FakeGooglePlayProvider.swift`, override **every** new `open func` of the
     capability handle (e.g. `FakePlayTracks.fetchReleaseSummaries`,
     `applyReleaseChange`), or add a new `FakePlay…` subclass and return it from
     the provider's accessor (plus `capabilities()`). Mutations write through
     `developer.state.write { … }` so the next read reflects them.
  4. If the core adds a method to `Provider` itself, override it in
     `FakeCoreProvider` too.

  UniFFI generates every handle as an `open class` with `init(noHandle:)`; a
  method the fake doesn't override calls into Rust with a null handle and
  **crashes**, so always override the whole surface of a handle you return.
- **New Firebase endpoint:** add a route in `FakeFirebaseServer.handle`.
- **New network call outside these seams:** it is refused by
  `FakeNetworkURLProtocol` and logged as `[FakeData] Blocked network request`;
  give it a seam in `BackendEnvironment` and a fake.
