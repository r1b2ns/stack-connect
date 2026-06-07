# Refinement: Windows Account Management

**Date:** 2026-06-07
**Status:** Refined

---

## 1. Requirements (Product Owner)

### Summary

This document defines the requirements for porting the App Store Connect account management feature from iOS (SwiftUI) to the Windows target (SwiftCrossUI/WinUI backend). The feature encompasses three flows currently implemented in the iOS app: the account list screen, the "create new account" form, and the "import .scexport file" flow.

**Reference iOS files:**
- `StackConnect/Modules/AccountsList/AccountsListView.swift`
- `StackConnect/Modules/AccountsList/AccountsListViewModel.swift`
- `StackConnect/Modules/AddAccount/AddAccountView.swift`
- `StackConnect/Modules/AddAccount/AddAccountViewModel.swift`
- `StackConnect/Modules/AccountManagement/AccountManagementView.swift`

**Windows app entry points:**
- `StackConnectWindowsApp/Sources/StackConnectWindowsApp/App/RootView.swift`
- `StackConnectWindowsApp/Sources/StackConnectWindowsApp/App/WindowsHomeCoordinator.swift`

The porting approach is: reuse all business logic (models, view models, crypto, storage) as-is; write new SwiftCrossUI views for each screen; adapt navigation, modality, file picking, and secret storage to Windows constraints.

---

### Assumptions

**A-1** — SwiftCrossUI 0.7 is the UI framework. It supports: `VStack`, `HStack`, `ScrollView`, `ForEach`, `Button`, `TextField`, `TextEditor`, `Text`, `Spacer`, `ProgressView`, `GeometryReader`, `cornerRadius`, `.task`, `.onTapGesture`, `@State`, and `ObservableObject`/`@Published` via SwiftCrossUI's own types. It does NOT support `.sheet`, `NavigationStack`, `.alert` (native dialog), `.fileImporter`, `UIDocumentPicker`, SF Symbols, `UIPasteboard`, or `.toolbar`.

**A-2** — `WindowsCredentialStorable` (already in `Packages/StackSecretsWindows`) is the secrets store and satisfies `KeyStorable`. It is a direct drop-in replacement for `KeychainStorable` since both implement the same protocol with identical byte encoding.

**A-3** — `SQLitePersistentStorable` (already in `Packages/StackStorageSQLite`) is the persistence store and satisfies `PersistentStorable`. It is already wired in `Bootstrap.makeEnvironment()`.

**A-4** — `StackCrypto` (`AccountCrypto.decrypt`) uses `swift-crypto`, which supports Windows. The `.scexport` decryption logic is fully portable and can be consumed unchanged.

**A-5** — `AccountModel`, `ProviderType`, `AppleCredentials`, `FirebaseCredentials`, and `GooglePlayCredentials` are Foundation-pure and compile on Windows unchanged.

**A-6** — The iOS `AddAccountViewModel` calls `AppleAccountConnection.validateCredentials()` — a live App Store Connect API call. This call uses `appstoreconnect-swift-sdk`, which is an iOS-only dependency. The "Create New Account" flow on Windows will skip live credential validation in v1. The account is saved after local format validation only (non-empty fields, basic string checks). This is the same tradeoff already documented for live Apple sync (D7 in the existing codebase).

**A-7** — File picking on Windows v1 uses Win32's `GetOpenFileName` dialog (native file picker).

**A-8** — Navigation reuses the existing `WindowsHomeCoordinator` route stack pattern. The `.accountsList(ProviderType)` route (already defined in `WindowsRoute`) will render the real `WindowsAccountsListView` instead of the current placeholder.

**A-9** — In-screen modality (iOS `.sheet`) is replaced by in-route full-screen replacement, following the existing Windows navigation convention: pushing a new route onto the stack shows a new full screen with a "< Back" button.

**A-10** — "Delete with swipe" (iOS `List.onDelete`) is not available in SwiftCrossUI. Deletion is triggered by a "Delete" button rendered in-row on the account list, confirmed by an inline confirmation banner (no native `.alert`).

**A-11** — The Apple credential validation step (live API call) is disabled on Windows v1 (same as D7 for sync). The StackCrypto package is added to `Package.swift` for import functionality. Firebase and Google Play JSON format validation (parsing `PlayConfiguration` / `FirebaseConfiguration`) must be confirmed as Windows-compilable by the developer before attempting to include them. If not, v1 also skips Firebase/Google Play JSON validation.

**A-12** — `StackCrypto` has a declared platform restriction of `.iOS(.v17), .macOS(.v14)` in its manifest. The Windows package manifest must be updated to remove the platform restriction (or loosen it to allow Windows) before `AccountCrypto` can be imported. This is a prerequisite task.

**A-13** — The "Re-import" flow remains a disabled placeholder in v1 (D7 in the existing codebase). No change to this decision.

---

### Out of Scope (v1)

- Live Apple API credential validation during "Create New Account" (no `appstoreconnect-swift-sdk` on Windows).
- Firebase and Google Play JSON schema validation via live API calls.
- The `AccountManagement` screen (export, provisioning sub-screens, user access) — these require many unported downstream modules and are not needed for the core add/list/delete flow.
- Re-import flow (D7 — remains a disabled placeholder).
- Deep link routing (`DeepLinkRouter`, `ReimportRouter`) — iOS-only infrastructure.
- Swipe-to-delete gesture — not supported by SwiftCrossUI 0.7.
- Biometric/accessibility-specific input behaviors (`textContentType`, `UIImpactFeedbackGenerator`).
- Tutorial expansion sections (collapsible "How to generate the API key") — `DisclosureGroup` availability in SwiftCrossUI 0.7 is unconfirmed. Tutorial text can be rendered as always-visible static text if needed, or deferred to v2.
- Google Play account creation and import (can be included if the JSON validation blocker in A-11 is resolved, but is not a hard requirement for v1 which focuses on Apple and Firebase).

---

### User Stories

#### US-W01 — View the Account List Screen

**Priority:** Must Have | **Complexity:** M | **Dependencies:** None

```
As a Windows user,
I want to tap a provider card on the Home screen and see my saved accounts for that provider,
So that I can select an account to work with or manage my account list.
```

**Acceptance Criteria:**

- AC-1. Tapping a provider card pushes `.accountsList(provider)` route and renders `WindowsAccountsListView` — not the placeholder.
- AC-2. All matching accounts are displayed as rows in a scrollable list filtered by provider.
- AC-3. Empty-state message when no accounts exist ("No accounts. Tap Add to add your first account.").
- AC-4. Loading indicator while fetching; disappears on completion.
- AC-5. "imported" badge on rows with `origin == .imported`.
- AC-6. "expired" badge on rows with `isExpired == true`; tapping shows inline error (not navigation).
- AC-7. "< Back" pops to Home screen.
- AC-8. "+" button pushes `.addAccountOptions(provider)` route.

---

#### US-W02 — Navigate to Add Account Options

**Priority:** Must Have | **Complexity:** S | **Dependencies:** US-W01

```
As a Windows user,
I want to see a choice between "Create New" and "Import" when I press "+",
So that I can pick the right path for my situation.
```

**Acceptance Criteria:**

- AC-1. Options screen shows "Create New" and "Import" (Import only shown for `.apple` provider).
- AC-2. Tapping "Create New" pushes `.createAppleAccount` or `.createFirebaseAccount`.
- AC-3. Tapping "Import" pushes `.importScexport`.
- AC-4. "< Back" pops to account list.

---

#### US-W03 — Create a New Apple Account

**Priority:** Must Have | **Complexity:** L | **Dependencies:** US-W02, T-F01

```
As a Windows user,
I want to enter my Account Name, Issuer ID, Private Key ID, and Private Key and save a new App Store Connect account,
So that I can use StackConnect on Windows to manage my apps.
```

**Acceptance Criteria:**

- AC-1. Form shows Account Name, Issuer ID, Private Key ID, Private Key TextEditor, Save button, and Back button.
- AC-2. All four fields non-empty → Save shows loading, disables form, calls save() async.
- AC-3. Save success → credentials stored in WindowsCredentialStorable, AccountModel saved to SQLite, pop to list.
- AC-4. Account Name empty → inline error "Account name is required."
- AC-5. Duplicate private key → inline error "An account with these credentials already exists: '<name>'."
- AC-6. Save failure → inline error with description, form re-enabled.
- AC-7. PEM headers/footer stripped before storing (sanitizedPrivateKey).
- AC-8. Back without saving → no data written, pops to options.

---

#### US-W04 — Create a New Firebase Account

**Priority:** Should Have | **Complexity:** M | **Dependencies:** US-W02

```
As a Windows user,
I want to paste my Firebase service account JSON and save a new Firebase account,
So that I can manage Firebase projects on Windows.
```

**Acceptance Criteria:**

- AC-1. Form shows Account Name, Service Account JSON TextEditor, Save button, and Back button.
- AC-2. JSON empty → inline error "Service Account JSON is required."
- AC-3. Invalid JSON → inline error "Invalid JSON format."
- AC-4. Valid save → credentials in WindowsCredentialStorable, AccountModel in SQLite, pop to list.
- AC-5. Duplicate JSON → inline error "An account with these credentials already exists: '<name>'."

---

#### US-W05 — Import an Account from a .scexport File

**Priority:** Must Have | **Complexity:** L | **Dependencies:** US-W02, T-F01

```
As a Windows user,
I want to provide the path to an .scexport file and enter the decryption password,
So that I can restore account credentials shared from another device.
```

**Acceptance Criteria:**

- AC-1. Form shows file path field, password field, "Decrypt and Import" button, and Back button. Native file picker (Win32 GetOpenFileName) for browse.
- AC-2. Valid path + correct password → reads file, calls AccountCrypto.decrypt, shows confirmation with pre-populated name.
- AC-3. Confirm → credentials in WindowsCredentialStorable (origin=.imported), AccountModel in SQLite, pop to list.
- AC-4. File path empty → inline error "File path is required."
- AC-5. File not readable → inline error "Failed to read file."
- AC-6. Wrong password → inline error "Decryption failed. Check your password and try again."
- AC-7. Missing JSON fields → inline error "Missing or invalid '<field>' field."
- AC-8. Provider mismatch → inline error "This file contains a <provider> account..."
- AC-9. Duplicate credentials → inline error "An account with these credentials already exists: '<name>'."

---

#### US-W06 — Delete an Account

**Priority:** Must Have | **Complexity:** M | **Dependencies:** US-W01

```
As a Windows user,
I want to delete an account from the list,
So that I can remove credentials I no longer need.
```

**Acceptance Criteria:**

- AC-1. Each row has a "Delete" button visible inline.
- AC-2. Tapping Delete → inline confirmation banner "Delete '<name>'? This cannot be undone." with Confirm/Cancel.
- AC-3. Confirm → removes AppModel + AppStoreVersionModel + AccountModel from SQLite + credentials from WindowsCredentialStorable; row disappears.
- AC-4. Cancel → banner dismissed, no data deleted.
- AC-5. Delete error → inline error "Failed to delete account. Try again." account remains.

---

## 2. Design Spec (UX Designer)

### Component Mapping

| iOS Component | Windows Equivalent | Rationale |
|---|---|---|
| `NavigationStack` push | `WindowsHomeCoordinator.push()` route | Established pattern. No NavigationStack in SwiftCrossUI 0.7. |
| `.sheet` (action/form/import) | Pushed full-screen route with `< Back` | Sheets not available. Full-screen route is the established fallback. |
| `List` + `.onDelete` (swipe) | `VStack` of card rows with inline `Delete` button | No swipe gesture on desktop. |
| `ContentUnavailableView` | Centered `VStack`: glyph, heading, subheading | SwiftUI-only. |
| Badge `Capsule` | `Text` with background `cornerRadius(4)` | `Capsule` not confirmed in SwiftCrossUI 0.7. |
| `.alert` (confirmation) | Inline `WindowsAlertBannerView`-style InfoBar banner | No `.alert` in SwiftCrossUI 0.7. |
| `DisclosureGroup` (tutorial) | Omitted in v1 | Not in SwiftCrossUI 0.7. |
| `Label(systemImage:)` | `Text(glyph)` + `Text(label)` in `HStack` | SF Symbols not available. |
| `.fileImporter` | Win32 `GetOpenFileName` dialog | Native file dialog. |
| `SecureField` | `TextField` (fallback if SecureField unavailable) | SwiftCrossUI 0.7 availability uncertain. |
| `Form` / `Section` | `VStack` with section-header `Text` + card chrome | No `Form`/`Section` in SwiftCrossUI. |

### Navigation Architecture

```
WindowsRoute (additions)
├── .accountsList(ProviderType)          [exists as placeholder — now real]
│   ├── .addAccountOptions(ProviderType) [new]
│   │   ├── .createAppleAccount          [new]
│   │   ├── .createFirebaseAccount       [new]
│   │   └── .importScexport              [new]
│   └── (inline delete banner, no route push)
└── (all other existing routes unchanged)
```

**Route push sequences:**
- US-W01: Home → push(.accountsList(.apple))
- US-W02: AccountsList → push(.addAccountOptions(.apple))
- US-W03: AddAccountOptions → push(.createAppleAccount)
- US-W04: AddAccountOptions → push(.createFirebaseAccount)
- US-W05: AddAccountOptions → push(.importScexport)
- US-W06: AccountsList → (inline, no push)

### Glyph Substitution Table

| iOS SF Symbol | Windows Glyph |
|---|---|
| `person.crop.circle.badge.plus` (empty state) | `"(+)"` large text |
| `plus` (toolbar) | `"+ Add"` text button |
| `plus.circle.fill` (Create New) | `"+"` + `"Create New"` |
| `square.and.arrow.down.fill` (Import) | `"↓"` + `"Import"` |
| `doc.badge.arrow.up.fill` (import hero) | `"📄"` large |
| `doc.badge.plus` (Browse .p8) | `"+ Browse…"` text |
| `doc.on.clipboard` (paste) | `"Paste"` text |
| `exclamationmark.triangle.fill` (error) | `"⚠"` in red |
| `trash` (delete) | `"Delete"` text |
| `chevron.right` (disclosure) | `">"` |

### Screen Layouts

#### W01-A: Account List — Empty State

```
┌─────────────────────────────────────────────────────────────────┐
│  [< Back]                                          [+ Add]      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                         (  +  )                                 │
│                      No Accounts                                │
│              Tap "+ Add" to add your first account.             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### W01-B: Account List — Populated State

```
┌─────────────────────────────────────────────────────────────────┐
│  App Store Connect                                  [+ Add]     │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ASC  My Work Account          [imported]     >   [Del] │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ASC  Personal Account         [expired]      >   [Del] │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ⚠  Delete "Personal Account"? This cannot be undone.   │   │
│  │                              [Cancel]  [Delete]         │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

#### W02: Add Account Options

```
┌─────────────────────────────────────────────────────────────────┐
│  [< Back]                                                       │
├─────────────────────────────────────────────────────────────────┤
│  Add Account                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  +  Create New                                       >  │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ↓  Import .scexport                                 >  │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

#### W03: Create Apple Account Form

```
┌─────────────────────────────────────────────────────────────────┐
│  [< Back]                                        [Save] / [⏳]  │
├─────────────────────────────────────────────────────────────────┤
│  ScrollView                                                     │
│  ┌─── GENERAL ──────────────────────────────────────────────┐  │
│  │  [Account Name                                    ]      │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌─── APP STORE CONNECT CREDENTIALS ────────────────────────┐  │
│  │  [Issuer ID                         ] [Paste]            │  │
│  │  [Private Key ID                    ] [Paste]            │  │
│  │  Private Key (.p8)                    [Paste]            │  │
│  │  ┌──────────────────────────────────────────────┐        │  │
│  │  │  (monospaced TextEditor, minHeight 120)      │        │  │
│  │  └──────────────────────────────────────────────┘        │  │
│  │  [+ Browse…]                                             │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌─── ⚠ error banner ──────────────────────────────────────┐  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

#### W04: Create Firebase Account Form

```
┌─────────────────────────────────────────────────────────────────┐
│  [< Back]                                        [Save] / [⏳]  │
├─────────────────────────────────────────────────────────────────┤
│  ScrollView                                                     │
│  ┌─── GENERAL ──────────────────────────────────────────────┐  │
│  │  [Account Name                                    ]      │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌─── FIREBASE CREDENTIALS ─────────────────────────────────┐  │
│  │  Service Account Key (JSON)             [Paste]          │  │
│  │  ┌──────────────────────────────────────────────┐        │  │
│  │  │  (monospaced TextEditor, minHeight 200)      │        │  │
│  │  └──────────────────────────────────────────────┘        │  │
│  │  [+ Browse…]                                             │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌─── ⚠ error banner ──────────────────────────────────────┐  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

#### W05: Import .scexport (Progressive Disclosure)

```
┌─────────────────────────────────────────────────────────────────┐
│  [< Back]                                                       │
├─────────────────────────────────────────────────────────────────┤
│  ScrollView                                                     │
│                         📄                                      │
│       Import an encrypted .scexport file containing             │
│       your account credentials.                                 │
│  ┌─── STEP 1 — SELECT FILE ────────────────────────────────┐  │
│  │  [selected file name, or "No file selected"]             │  │
│  │                       [↓ Browse…]                        │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌─── STEP 2 — PASSWORD (shown after file selected) ───────┐  │
│  │  Password  [          ]                                  │  │
│  │                        [Decrypt]                         │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌─── ⚠ decryption error banner ───────────────────────────┐  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌─── STEP 3 — ACCOUNT NAME (shown after decrypt) ─────────┐  │
│  │  Account Name   [pre-filled from file]                   │  │
│  │                        [Import]                          │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Key UX Deltas from iOS

1. **No sheets** — all flows are pushed full-screen routes (SwiftCrossUI constraint)
2. **No swipe-to-delete** — inline Delete button + confirmation banner (desktop has no swipe)
3. **No modal alerts** — inline InfoBar banners for all errors/confirmations (Fluent pattern)
4. **Progressive disclosure import** — 3 sequential inline steps instead of chained alerts
5. **Tutorial omitted** — no DisclosureGroup in v1
6. **Rectangular badges** — `cornerRadius(4)` instead of Capsule shape
7. **No live credential validation** — local checks only (no appstoreconnect-swift-sdk on Windows)

### Responsive Behavior

| Tier | Window width | Behavior |
|---|---|---|
| `.regular` | >= 860px | Content column capped at 860px, centered. Full labels. |
| `.compact` | 680–859px | Content fills width minus 32px padding. |
| `.abbreviated` | < 680px | Single-column. Toolbar labels shortened ("+" instead of "+ Add"). |

---

## 3. Task Breakdown (Developer)

### Prerequisites

1. **StackCrypto platform restriction** — Package.swift declares `platforms: [.iOS(.v17), .macOS(.v14)]`. Must be removed for Windows.
2. **Credential model types** — `AppleCredentials`, `FirebaseCredentials`, `GooglePlayCredentials` are in the iOS app target, not importable by Windows. Need duplication or extraction.
3. **AppEnvironment secrets store** — Current `AppEnvironment` does not expose a `KeyStorable` for credentials.

### Tasks

#### T-F01 — Remove platform restriction from StackCrypto manifest

| Field | Value |
|-------|-------|
| **Dependencies** | None |
| **Complexity** | S |
| **Files** | `Packages/StackCrypto/Package.swift` |
| **AC coverage** | Prerequisite (A-12) |

Remove or comment out `platforms: [.iOS(.v17), .macOS(.v14)]` from StackCrypto. Verify package resolves on macOS host.

---

#### T-F02 — Add StackCrypto dependency to the Windows app package

| Field | Value |
|-------|-------|
| **Dependencies** | T-F01 |
| **Complexity** | S |
| **Files** | `StackConnectWindowsApp/Package.swift` |
| **AC coverage** | Prerequisite for US-W05 |

Add `.package(path: "../Packages/StackCrypto")` and `.product(name: "StackCrypto", package: "StackCrypto")`.

---

#### T-F03 — Create shared credential model types accessible from the Windows target

| Field | Value |
|-------|-------|
| **Dependencies** | None |
| **Complexity** | S |
| **Files** | `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Models/AppleCredentials.swift`, `FirebaseCredentials.swift`, `GooglePlayCredentials.swift` |
| **AC coverage** | Prerequisite for US-W01/03/04/05 |

Create simple `Codable` structs mirroring the iOS credential models. Foundation-only, 3–7 lines each.

---

#### T-F04 — Extend AppEnvironment with the credential (secrets) store

| Field | Value |
|-------|-------|
| **Dependencies** | T-F03 |
| **Complexity** | S |
| **Files** | `StackConnectWindowsApp/Sources/StackConnectWindowsApp/App/Bootstrap.swift` |
| **AC coverage** | Prerequisite for US-W01/03/04/05 |

Add `secrets: KeyStorable` property to `AppEnvironment`, backed by `WindowsCredentialStorable()`.

---

#### T-F05 — Add new routes to WindowsRoute and wire placeholders in RootView

| Field | Value |
|-------|-------|
| **Dependencies** | None |
| **Complexity** | S |
| **Files** | `WindowsHomeCoordinator.swift`, `RootView.swift` |
| **AC coverage** | Navigation skeleton for all US |

Add `.addAccountOptions(ProviderType)`, `.createAppleAccount`, `.createFirebaseAccount`, `.importScexport` to `WindowsRoute`. Wire placeholders in `RootView.destination(for:)`.

---

#### T-F06 — Create WindowsAccountsListModel

| Field | Value |
|-------|-------|
| **Dependencies** | T-F03, T-F04 |
| **Complexity** | M |
| **Files** | `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Accounts/WindowsAccountsListModel.swift` |
| **AC coverage** | US-W01, US-W06 (load, filter, delete) |

SwiftCrossUI `ObservableObject` adapter: loads accounts, filters by provider, handles delete cascade (account + apps + versions + credentials). Exposes `accounts`, `isLoading`, `deleteConfirmingId`, `errorMessage`.

---

#### T-F07 — Create WindowsAccountsListView

| Field | Value |
|-------|-------|
| **Dependencies** | T-F05, T-F06 |
| **Complexity** | L |
| **Files** | `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Accounts/WindowsAccountsListView.swift` |
| **AC coverage** | US-W01 (all ACs), US-W06 (inline delete confirmation) |

Full account list screen: toolbar with back/title/add button, loading/empty/populated states, card rows with badges, inline delete confirmation banner.

---

#### T-F08 — Create WindowsAddAccountOptionsView

| Field | Value |
|-------|-------|
| **Dependencies** | T-F05 |
| **Complexity** | S |
| **Files** | `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Accounts/WindowsAddAccountOptionsView.swift` |
| **AC coverage** | US-W02 |

Two tappable cards: "Create New" + "Import" (Import only for `.apple`). Back button. Content capped at 860px.

---

#### T-F09 — Create WindowsCreateAccountModel

| Field | Value |
|-------|-------|
| **Dependencies** | T-F03, T-F04 |
| **Complexity** | M |
| **Files** | `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Accounts/WindowsCreateAccountModel.swift` |
| **AC coverage** | US-W03 (Apple save), US-W04 (Firebase save) |

SwiftCrossUI `ObservableObject` for account creation: form fields, validation (local only), duplicate detection, save to storage + secrets. Sanitizes PEM headers.

---

#### T-F10 — Create WindowsCreateAppleAccountView

| Field | Value |
|-------|-------|
| **Dependencies** | T-F05, T-F09, T-F14, T-F15 |
| **Complexity** | M |
| **Files** | `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Accounts/WindowsCreateAppleAccountView.swift` |
| **AC coverage** | US-W03 |

Apple form: General section (name) + ASC Credentials section (Issuer ID, Private Key ID, Private Key TextEditor + Paste + Browse). Error banner. Save button.

---

#### T-F11 — Create WindowsCreateFirebaseAccountView

| Field | Value |
|-------|-------|
| **Dependencies** | T-F05, T-F09, T-F14, T-F15 |
| **Complexity** | M |
| **Files** | `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Accounts/WindowsCreateFirebaseAccountView.swift` |
| **AC coverage** | US-W04 |

Firebase form: General section (name) + Firebase Credentials section (JSON TextEditor + Paste + Browse). Error banner. Save button.

---

#### T-F12 — Create WindowsImportAccountModel

| Field | Value |
|-------|-------|
| **Dependencies** | T-F02, T-F03, T-F04 |
| **Complexity** | M |
| **Files** | `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Accounts/WindowsImportAccountModel.swift` |
| **AC coverage** | US-W05 |

3-step progressive import model: `selectFile` → `enterPassword` → `confirmName`. Reads file, calls `AccountCrypto.decrypt`, validates JSON, checks duplicates, saves account.

---

#### T-F13 — Create WindowsImportAccountView

| Field | Value |
|-------|-------|
| **Dependencies** | T-F05, T-F12, T-F14 |
| **Complexity** | L |
| **Files** | `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Accounts/WindowsImportAccountView.swift` |
| **AC coverage** | US-W05 |

Import screen with progressive disclosure: hero section, Step 1 (file browse), Step 2 (password + decrypt), Step 3 (name + import). Error banners between steps.

---

#### T-F14 — Implement Win32 file picker helper

| Field | Value |
|-------|-------|
| **Dependencies** | None |
| **Complexity** | M |
| **Files** | `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Shared/WindowsFilePicker.swift` |
| **AC coverage** | US-W03 (.p8), US-W04 (.json), US-W05 (.scexport) |

Wraps Win32 `GetOpenFileNameW` with configurable file filters. Returns selected path or nil. macOS stub returns nil.

---

#### T-F15 — Implement Win32 clipboard paste helper

| Field | Value |
|-------|-------|
| **Dependencies** | None |
| **Complexity** | S |
| **Files** | `StackConnectWindowsApp/Sources/StackConnectWindowsApp/Shared/WindowsClipboard.swift` |
| **AC coverage** | US-W03, US-W04 (paste buttons) |

Reads text from clipboard via `OpenClipboard/GetClipboardData(CF_UNICODETEXT)/CloseClipboard`. macOS stub returns nil.

---

#### T-F16 — Wire all real views into RootView and connect to AppEnvironment

| Field | Value |
|-------|-------|
| **Dependencies** | T-F07, T-F08, T-F10, T-F11, T-F13 |
| **Complexity** | M |
| **Files** | `RootView.swift` |
| **AC coverage** | Full navigation integration |

Replace all placeholder destinations with real views. Pass `storage` and `secrets` from AppEnvironment to model initializers.

---

### Dependency Graph

```
Wave 1 (parallel, no dependencies):
  T-F01, T-F03, T-F05, T-F14, T-F15

Wave 2 (after Wave 1):
  T-F02 (needs T-F01)
  T-F04 (needs T-F03)
  T-F06 (needs T-F03, T-F04)
  T-F08 (needs T-F05)
  T-F09 (needs T-F03, T-F04)
  T-F12 (needs T-F02, T-F03, T-F04)

Wave 3 (after Wave 2):
  T-F07 (needs T-F05, T-F06)
  T-F10 (needs T-F05, T-F09, T-F14, T-F15)
  T-F11 (needs T-F05, T-F09, T-F14, T-F15)
  T-F13 (needs T-F05, T-F12, T-F14)

Wave 4 (final):
  T-F16 (needs T-F07, T-F08, T-F10, T-F11, T-F13)
```

### Critical Path

T-F01 → T-F02 → T-F12 → T-F13 → T-F16

### Technical Risks

| # | Risk | Mitigation |
|---|------|-----------|
| R1 | SwiftCrossUI may not support `SecureField` | Fallback to plain `TextField` for v1 |
| R2 | Win32 `GetOpenFileName` Swift bindings may require C bridge | T-F14 tested on Windows VM early |
| R3 | StackCrypto PBKDF2 (BoringSSL) on Windows unvalidated | Run `swift build` in StackCrypto on VM after T-F01 |
| R4 | Credential types duplicated (iOS + Windows) | Acceptable for v1; track as tech debt |
| R5 | `SQLitePersistentStorable` actor isolation with `@MainActor` | Same proven pattern as `WindowsHomeModel` |

### Open Questions

1. **Cascade delete** — Should delete also remove AppModel/AppStoreVersionModel? **Assumption: yes (mirror iOS).**
2. **Import scope** — Import shown only for `.apple` (match iOS) or all providers? **Assumption: Apple only.**
3. **Route structure** — Separate `.createAppleAccount`/`.createFirebaseAccount` vs single `.createAccount(ProviderType)`? **Recommendation: keep separate for type safety.**
4. **Reload on pop** — Re-load accounts via `.task` on appear (same as iOS). **Confirmed.**

---

## 4. Test Cases (QA)

### Overview

**77 total test cases** organized by user story. Full test plan with preconditions, steps, expected results, automation strategy, and coverage matrix.

**By Type:**
- Unit Tests: 8
- Integration Tests: 30
- UI Tests: 37
- Manual Tests: 2 (Win32 file picker, keyboard navigation)

**By Priority:**
- P0 (Critical): 45
- P1 (High): 22
- P2 (Medium): 10

---

### US-W01 Tests (TC-F001 through TC-F018)

| ID | Title | Type | Priority | AC |
|---|---|---|---|---|
| TC-F001 | Account List route pushed on provider card tap | UI | P0 | AC-1 |
| TC-F002 | Firebase provider card pushes correct route | UI | P1 | AC-1 |
| TC-F003 | Google Play provider card pushes correct route | UI | P1 | AC-1 |
| TC-F004 | List displays all accounts filtered by provider | Integration | P0 | AC-2 |
| TC-F005 | List updates when new account added | Integration | P1 | AC-2 |
| TC-F006 | Responsive layout tiers respected | UI | P2 | AC-2 |
| TC-F007 | Empty state message displayed | UI | P0 | AC-3 |
| TC-F008 | Empty state disappears after adding account | Integration | P1 | AC-3 |
| TC-F009 | Loading indicator shown during fetch | UI | P1 | AC-4 |
| TC-F010 | Loading flag cleared after fetch | Unit | P1 | AC-4 |
| TC-F011 | "imported" badge displayed on imported accounts | UI | P1 | AC-5 |
| TC-F012 | "imported" badge NOT shown on manual accounts | UI | P2 | AC-5 |
| TC-F013 | "expired" badge displayed on expired accounts | UI | P1 | AC-6 |
| TC-F014 | Tapping expired row shows inline error, no navigation | UI | P1 | AC-6 |
| TC-F015 | "expired" badge NOT shown on valid accounts | UI | P2 | AC-6 |
| TC-F016 | Back button pops to Home | UI | P0 | AC-7 |
| TC-F017 | "+" button pushes addAccountOptions route | UI | P0 | AC-8 |
| TC-F018 | "+" button visible for all provider types | UI | P1 | AC-8 |

---

### US-W02 Tests (TC-F019 through TC-F026)

| ID | Title | Type | Priority | AC |
|---|---|---|---|---|
| TC-F019 | "Create New" + "Import" shown for Apple | UI | P0 | AC-1 |
| TC-F020 | Only "Create New" shown for Firebase | UI | P0 | AC-1 |
| TC-F021 | Only "Create New" shown for Google Play | UI | P1 | AC-1 |
| TC-F022 | "Create New" pushes createAppleAccount | UI | P0 | AC-2 |
| TC-F023 | "Create New" pushes createFirebaseAccount | UI | P0 | AC-2 |
| TC-F024 | "Create New" pushes createGooglePlayAccount | UI | P1 | AC-2 |
| TC-F025 | "Import" pushes importScexport | UI | P0 | AC-3 |
| TC-F026 | Back pops to account list | UI | P0 | AC-4 |

---

### US-W03 Tests (TC-F027 through TC-F041)

| ID | Title | Type | Priority | AC |
|---|---|---|---|---|
| TC-F027 | Form displays all required fields | UI | P0 | AC-1 |
| TC-F028 | Form respects responsive layout | UI | P2 | AC-1 |
| TC-F029 | Save enabled when all fields non-empty | UI | P1 | AC-2 |
| TC-F030 | Save triggers async with loading indicator | UI | P0 | AC-2 |
| TC-F031 | Save calls storage with sanitized key | Unit | P1 | AC-3 |
| TC-F032 | Credentials stored in WindowsCredentialStorable | Integration | P0 | AC-3 |
| TC-F033 | AccountModel stored in SQLite | Integration | P0 | AC-3 |
| TC-F034 | Successful save pops to account list | UI | P0 | AC-3 |
| TC-F035 | Empty Account Name shows error | UI | P0 | AC-4 |
| TC-F036 | Error clears when user enters text | UI | P2 | AC-4 |
| TC-F037 | Duplicate private key shows error | Integration | P0 | AC-5 |
| TC-F038 | Storage failure shows error, form re-enabled | Integration | P1 | AC-6 |
| TC-F039 | PEM headers/footer stripped | Unit | P1 | AC-7 |
| TC-F040 | Key without PEM stored as-is | Unit | P2 | AC-7 |
| TC-F041 | Back without saving discards data | UI | P1 | AC-8 |

---

### US-W04 Tests (TC-F042 through TC-F046)

| ID | Title | Type | Priority | AC |
|---|---|---|---|---|
| TC-F042 | Form displays required fields | UI | P0 | AC-1 |
| TC-F043 | Empty JSON shows error | UI | P0 | AC-2 |
| TC-F044 | Invalid JSON shows error | UI | P0 | AC-3 |
| TC-F045 | Valid save stores credentials + account | Integration | P0 | AC-4 |
| TC-F046 | Duplicate JSON shows error | Integration | P0 | AC-5 |

---

### US-W05 Tests (TC-F047 through TC-F056)

| ID | Title | Type | Priority | AC |
|---|---|---|---|---|
| TC-F047 | Import form displays all fields | UI | P0 | AC-1 |
| TC-F048 | File picker (Win32 dialog) works | Manual | P1 | AC-1 |
| TC-F049 | Valid decrypt shows confirmation | Integration | P0 | AC-2 |
| TC-F050 | Confirm stores with origin=.imported | Integration | P0 | AC-3 |
| TC-F051 | Empty file path shows error | UI | P0 | AC-4 |
| TC-F052 | Unreadable file shows error | Integration | P0 | AC-5 |
| TC-F053 | Wrong password shows error | Integration | P0 | AC-6 |
| TC-F054 | Missing JSON fields shows error | Integration | P1 | AC-7 |
| TC-F055 | Provider mismatch shows error | Integration | P1 | AC-8 |
| TC-F056 | Duplicate credentials shows error | Integration | P0 | AC-9 |

---

### US-W06 Tests (TC-F057 through TC-F065)

| ID | Title | Type | Priority | AC |
|---|---|---|---|---|
| TC-F057 | Delete button visible on each row | UI | P0 | AC-1 |
| TC-F058 | Delete shows inline confirmation banner | UI | P0 | AC-2 |
| TC-F059 | Banner positioned below triggering row | UI | P2 | AC-2 |
| TC-F060 | Confirm removes AccountModel from SQLite | Integration | P0 | AC-3 |
| TC-F061 | Confirm removes credentials from store | Integration | P0 | AC-3 |
| TC-F062 | Confirm cascades AppModel/Version removal | Integration | P1 | AC-3 |
| TC-F063 | Confirm removes row from list | UI | P0 | AC-3 |
| TC-F064 | Cancel dismisses banner, no deletion | UI | P0 | AC-4 |
| TC-F065 | Delete failure shows error, account remains | Integration | P1 | AC-5 |

---

### Edge Cases (TC-F066 through TC-F077)

| ID | Title | Type | Priority |
|---|---|---|---|
| TC-F066 | Offline SQLite loading works | Integration | P1 |
| TC-F067 | Large .scexport files handled | Integration | P2 |
| TC-F068 | Special characters in account name | Integration | P2 |
| TC-F069 | Long text truncation/wrapping | UI | P2 |
| TC-F070 | Multi-line PEM paste | UI | P2 |
| TC-F071 | Multi-line JSON paste | UI | P2 |
| TC-F072 | Rapid Save button clicks prevented | UI | P1 |
| TC-F073 | Navigation during delete handled | UI | P1 |
| TC-F074 | All messages localized | Integration | P1 |
| TC-F075 | Keyboard navigation works | Manual | P2 |
| TC-F076 | Unsaved data not persisted on crash | Integration | P1 |
| TC-F077 | Deleted account does not reappear | Integration | P1 |

---

### Coverage Matrix

| User Story | ACs | Test Cases | Coverage |
|---|---|---|---|
| US-W01 | 8 | TC-F001–TC-F018 | 100% |
| US-W02 | 4 | TC-F019–TC-F026 | 100% |
| US-W03 | 8 | TC-F027–TC-F041 | 100% |
| US-W04 | 5 | TC-F042–TC-F046 | 100% |
| US-W05 | 9 | TC-F047–TC-F056 | 100% |
| US-W06 | 5 | TC-F057–TC-F065 | 100% |
| Edge Cases | — | TC-F066–TC-F077 | N/A |

All 39 acceptance criteria are covered by at least one P0 or P1 test case.
