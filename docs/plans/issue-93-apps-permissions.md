# Implementation Plan — Issue #93: Per-app scoping ("Apps permissions") for account export/import

> GitHub issue: https://github.com/r1b2ns/stack-connect/issues/93
> All file paths, signatures, and line numbers below were verified against the current source.

## Backward-compatibility contract (MUST hold)

**No breaking changes to existing `.scexport` files or already-imported accounts.**

`appsBundles` semantics — **absent, `null`, OR empty array all mean "no restriction: every app is available to the user":**

| `appsBundles` in file / on account | Meaning |
|---|---|
| key absent (legacy files) | **All apps** (no restriction) |
| `null` | **All apps** (no restriction) |
| `[]` (empty) | **All apps** (no restriction) |
| `["com.a", "com.b"]` (non-empty) | Only those bundle IDs are available |

Only a **non-empty** array restricts. This guarantees older versions/files keep working exactly as before.

The single source of truth for this rule is `AccountModel.allowsApp(bundleId:)`:

```swift
/// Per-app export scope. nil/empty ⇒ no restriction (all apps visible).
/// Non-empty ⇒ only apps whose bundleId ∈ appsBundles are visible for this imported account.
func allowsApp(bundleId: String) -> Bool {
    guard let appsBundles, !appsBundles.isEmpty else { return true }
    return appsBundles.contains(bundleId)
}
```

---

## 0. Key findings from reading the code (these shape the whole plan)

- **Bundle ID field exists and is stable.** `AppModel.bundleId: String` (`StackConnect/Models/AppModel.swift:6`) and `StackProtocols.AppInfo.bundleId: String` (`Packages/StackProtocols/Sources/StackProtocols/AppInfo.swift:6`). The Rust sync path also carries `bundleId` through `CoreAppBlob`. Bundle ID is available everywhere apps are created — no new plumbing needed.
- **The export serialization is duplicated in TWO places** with slightly different signatures:
  - `SettingsAccountsViewModel.exportAccountWithRules(account:exportName:rules:password:expirationDate:)` — `SettingsAccountsViewModel.swift:126`
  - `AccountSettingsViewModel.exportAccountWithRules(exportName:rules:password:expirationDate:)` (no `account:`, reads `uiState.account`) — inline in `AccountSettingsView.swift:98`
  - **Both build the same `exportDict` and must both add `appsBundles`.** Factor the payload builder into one shared place to avoid divergence.
- **`ExportAccountView` is presented from TWO hosts:** `SettingsAccountsView.swift:107` and `AccountSettingsView.swift:179`. Both pass `account:` and an `onExport` closure `(String, AccountRules, String, Date?) -> URL?`. That closure signature must grow to carry the selected bundle IDs.
- **THREE code paths persist `AppModel` into SwiftData** — the crux of enforcement:
  1. `SyncService.runAccountSync(...)` save loop — `SyncService.swift:253-259`
  2. `SwiftDataBlobStore.save(typeName:id:json:)` — `SwiftDataBlobStore.swift:60-88` — **called from inside the Rust core** via `connection.syncApps(accountId:store:)` (`SyncService.swift:221`), independent of path 1.
  3. `AppListViewModel.loadApps()` foreground sync save loop — `AppListViewModel.swift:146-148`
- **SIX+ read-side consumers** `fetchAll(AppModel.self)` and filter by `accountId`: `AppListViewModel` (`:74`), `ArchivedAppsViewModel` (`:62`), `AccountManagementViewModel` (`:37`), `AllReviewsViewModel` (`:64`), `AccountsListViewModel` (`:123`), plus widget timeline providers (`InReviewWidget`, `RecentReviewsWidget`, `AwaitingReleaseWidget`), and `SettingsViewModel` (`:59`, delete cascade).

**Enforcement strategy: filter at PERSIST time, not read time.**
Applying the allowlist at the three write sites means excluded apps *never enter SwiftData* for an imported account. Every read consumer, all widgets, reviews, versions, and phased-release data become correct automatically, with zero changes per consumer. Read-time filtering would require touching every consumer (and every future one) and would still leave excluded rows in the DB. Persist-time filtering is the single robust choke point that also satisfies "don't resurface excluded apps on background sync." A tiny read-time defense-in-depth filter is added only in `AppListViewModel.loadApps` step 1 (offline-first cache read).

---

## 1. Data model changes

### 1a. `AccountModel` (`StackConnect/Models/AccountModel.swift`)
- Add stored property:
  ```swift
  /// Per-app export scope. nil/empty ⇒ no restriction (all apps visible — legacy/created accounts).
  /// Non-empty ⇒ only apps whose bundleId ∈ appsBundles are visible for this imported account.
  var appsBundles: [String]?
  ```
- Add `appsBundles: [String]? = nil` to the memberwise `init` (keep last, defaulted, so existing call sites — `SettingsAccountsViewModel.updateAccountName:79`, `importAccount:310` — keep compiling; `importAccount` must pass the parsed value, see §4).
- Add `case appsBundles` to `CodingKeys` (`:249-251`).
- In `init(from decoder:)` (`:235`), add:
  ```swift
  appsBundles = try container.decodeIfPresent([String].self, forKey: .appsBundles)
  ```
  `decodeIfPresent` ⇒ absent/null decodes to `nil` ⇒ no restriction (free backward compat).
- Add the `allowsApp(bundleId:)` helper (see backward-compat contract above) — **nil AND empty both return true**.
- **Do NOT touch `fillMissingRules()`** — it is about `AccountRules`, orthogonal.

### 1b. SwiftData migration considerations
`AccountModel` is persisted as JSON via the blob-based `SwiftDataStorable` (Codable, keyed by id). Adding an **optional** Codable field is **non-breaking/additive**:
- Old blobs lack the key ⇒ `decodeIfPresent` ⇒ `nil` ⇒ handled.
- No schema/version bump or `MigrationPlan` needed — same pattern used when `role`, `expirationDate`, `hasPendingAgreements`, `pendingAgreementsDetectedAt` were added (`AccountModel.swift:242-246`).
- **Verify** `SwiftDataStorable` stores `AccountModel` as an encoded blob (not a native `@Model`) by reading `StackConnect/Storage/SwiftDataStorable.swift` before coding. If a native `@Model` mirror exists, add the optional column there too.

### 1c. `.scexport` JSON payload addition
Inside the encrypted JSON only (container format in `AccountCrypto` untouched). Top-level key:
```json
"appsBundles": ["com.acme.one", "com.acme.two"]
```
Written **only when the exporter scoped to a non-empty subset**. Absent/empty ⇒ all apps.

---

## 2. Export UI changes (`ExportAccountView.swift`)

### 2a. Sourcing the account's apps
Pass apps in from the host (which has a ViewModel with storage). Add `let availableApps: [AppModel]` to `ExportAccountView`; each host fetches `storage.fetchAll(AppModel.self).filter { $0.accountId == account.id }` (sorted by name) before presenting. Keeps the View logic-free (MVVM rule) and reuses the pattern at `AppListViewModel.swift:74`.
- `SettingsAccountsView` (`:107`): VM already reads `AppModel` (`:104`). Add `appsForExport(accountId:) async -> [AppModel]`, load into `@State`/coordinator binding before presenting.
- `AccountSettingsView` (`:179`): add the same helper.

### 2b. New "Apps permissions" section + multi-select UX
- Add `@State private var selectedBundleIds: Set<String> = []` and `@State private var showAppsPicker = false` (mirroring `editingResource` at `:52`).
- Insert a new `Section` after the `ForEach(resources...)` loop (`:42-44`), styled like `buildResourceSection`: tappable row, title "Apps permissions", subtitle summarizing selection ("All apps", "3 of 12 apps"). Tap opens the picker sheet.
- New file `StackConnect/Modules/Settings/AppsPermissionPickerSheet.swift`, modeled on `PermissionPickerSheet.swift`:
  - Inputs: `apps: [AppModel]`, `initiallySelected: Set<String>`, `onDismiss: (Set<String>) -> Void`.
  - Rows: `app.name` + `app.bundleId` (secondary), checkmark toggle (`checkmark.circle.fill`/`circle` idiom, `PermissionPickerSheet:51`).
  - Toolbar: **Select All** / **Select None** + **OK** (confirmationAction).
  - `.presentationDetents([.large])` (apps lists can be long).
- **Empty / not-yet-synced handling:** when `availableApps.isEmpty`, render the row disabled with footer "No apps synced yet. Sync this account before scoping by app." and fall back to **all apps** (write no `appsBundles`). Never block export.

### 2c. `isExportEnabled` / `performExport()` changes
- `isExportEnabled` (`:299`): **no** hard requirement on apps selection. Keep name+resources+password.
- `performExport()` (`:317`): pass the payload through the widened `onExport`:
  ```swift
  // Empty selection ⇒ nil ⇒ all apps (no restriction). Only a non-empty subset restricts.
  let scopedBundles: [String]? = selectedBundleIds.isEmpty ? nil : Array(selectedBundleIds)
  _ = onExport(exportName, rules, password, enableExpiration ? expirationDate : nil, scopedBundles)
  ```
- **Widen the `onExport` closure type** on `ExportAccountView` from `(String, AccountRules, String, Date?) -> URL?` to `(String, AccountRules, String, Date?, [String]?) -> URL?`; update both hosts (`SettingsAccountsView.swift:109`, `AccountSettingsView.swift:181`).

### 2d. Required vs optional
Apps scoping is **OPTIONAL**, defaulting to "all apps". The other resource sections gate *verbs*; forcing an explicit app selection on every export would be a UX regression and would break exporting accounts whose apps haven't synced. Because empty ⇒ all apps (backward-compat contract), the "None" case is simply treated as "all apps" — no separate validation needed, though the UI subtitle should read "All apps" when nothing is selected to avoid confusion.

---

## 3. Export serialization changes

**Refactor to remove duplication, then add the field once** (Open/Closed + DRY):
- New file `StackConnect/Infra/Crypto/AccountExportPayloadBuilder.swift` — pure function:
  ```swift
  static func makeJSON(
      account: AccountModel,
      exportName: String,
      rules: AccountRules,
      expirationDate: Date?,
      appsBundles: [String]?,          // NEW
      credentials: [String: String]?
  ) -> String?
  ```
  Builds today's `exportDict` (id, name, providerType, createdAt, rules, role, optional expirationDate, optional credentials) **plus**:
  ```swift
  if let appsBundles, !appsBundles.isEmpty {
      exportDict["appsBundles"] = appsBundles
  }
  ```
  then `JSONSerialization` → string. (Credentials shape differs per provider; preserve existing Apple-only behavior — builder takes an already-assembled `credentials` dict from the caller's keychain read.)
- Update both `exportAccountWithRules` impls to read credentials (as today), call the builder, then `AccountCrypto.encrypt` + write temp file. Widen both signatures to accept `appsBundles: [String]?`:
  - `SettingsAccountsViewModelProtocol` (`:11`) **and** impl (`:126`).
  - `AccountSettingsViewModel` protocol (`AccountSettingsView.swift:35`) and impl (`:98`).
- Minimal fallback if the refactor is too large: add the identical `if let appsBundles…` block to both `exportDict` builders. Shared builder preferred; flag the choice to the reviewer.

---

## 4. Import parsing changes (`SettingsAccountsViewModel.importAccount`, `:184`)

- After parsing `role` (`:241`), add:
  ```swift
  // Per-app scope. Absent/null ⇒ nil ⇒ no restriction. Empty ⇒ also no restriction (see allowsApp).
  let appsBundles = dict["appsBundles"] as? [String]
  ```
- Pass into the constructed `AccountModel` (`:310`):
  ```swift
  let account = AccountModel(
      id: accountId,
      name: accountName,
      providerType: providerType,
      rules: rules,
      origin: .imported,
      role: role,
      expirationDate: expirationDate,
      appsBundles: appsBundles      // NEW
  )
  ```
- Type-tolerance: prefer strict `dict["appsBundles"] as? [String]` (matches `rules` parsing at `:222`); optional fallback `(dict["appsBundles"] as? [Any])?.compactMap { $0 as? String }`.

---

## 5. Enforcement / filtering layer

Apply the allowlist at all **three persist sites**. In each, load the owning `AccountModel` and skip/drop apps failing `account.allowsApp(bundleId:)`. Fast path: `allowsApp` returns true for nil/empty, so unrestricted accounts pay ~zero cost.

### 5a. `SyncService.runAccountSync` — `SyncService.swift:200-326`
- `account` already in scope. After building `remoteApps`, filter:
  ```swift
  let scopedRemote = remoteApps.filter { account.allowsApp(bundleId: $0.bundleId) }
  ```
  Derive everything (`baseApps`, `enrichApps`, reviews, phased, `saveMetadata` count) from the scoped set (reviews/versions/phased for excluded apps are never fetched/stored — cascade for free).
- **Purge already-persisted excluded rows** (covers re-import / tightened scope): after computing `scopedRemote`, delete cached `AppModel` for this account whose bundleId is excluded (mirror delete idiom in `SettingsAccountsViewModel.deleteAccount:106-113`, cascading versions/reviews).

### 5b. `SwiftDataBlobStore.save` — `SwiftDataBlobStore.swift:43-89` (Rust-core write path)
Runs inside `connection.syncApps(...)`, bypasses 5a. Before the `merged` save (`:82`):
```swift
// Enforce per-app export scope for imported accounts.
if let account = try? await storage.fetch(AccountModel.self, id: blob.accountId),
   !account.allowsApp(bundleId: blob.bundleId) {
    return   // do not persist excluded apps
}
```

### 5c. `AppListViewModel.loadApps` — `AppListViewModel.swift:62-160`
- **Read side (cache load, `:70-74`):** add `.filter { self.uiState.account.allowsApp(bundleId: $0.bundleId) }` (defense-in-depth for pre-existing rows).
- **Write side (persist, `:107-148`):** filter `remoteApps` right after `connection.fetchApps()` (`:106`):
  ```swift
  let remoteApps = try await connection.fetchApps().filter {
      self.uiState.account.allowsApp(bundleId: $0.bundleId)
  }
  ```

### 5d. Read consumers — no changes needed (by design)
Persist-time filtering keeps excluded apps out of SwiftData, so `ArchivedAppsViewModel:62`, `AccountManagementViewModel:37`, `AllReviewsViewModel:64`, `AccountsListViewModel:123`, `SettingsViewModel:59`, and widget providers require **no edits**. (Note this to the reviewer as the payoff.)

### 5e. Reviews/versions referencing an excluded app
Excluded apps are never stored ⇒ their reviews/versions/phased data are never fetched/persisted ⇒ nothing references a hidden app. **Excluded apps are hidden entirely** (answers the issue's open question); no "no access" UI needed.

---

## 6. Localization (`StackConnect/Resources/Localizable.xcstrings`)

New `String(localized:)` keys:
- `"Apps permissions"` — section/picker title.
- `"All apps"` — subtitle when unrestricted.
- `"%lld of %lld apps"` (or interpolated `"\(selected) of \(total) apps"`) — subset subtitle.
- `"Choose which apps the recipient can access. Leave as All apps to share everything."` — footer.
- `"No apps synced yet. Sync this account before scoping by app."` — empty-state footer.
- `"Select All"` / `"Select None"` — picker toolbar.
- Reuse existing `"None"` (`PermissionPickerSheet:72`).

---

## 7. Tests

### 7a. New `StackConnectTests/ViewModels/SettingsAccountsViewModelTests.swift`
(No `SettingsAccountsViewModelTests` exists today — create it with `MockPersistentStorable` + `MockKeyStorable`.)
- **Export writes appsBundles:** `exportAccountWithRules(..., appsBundles: ["com.a","com.b"])` → decrypt → assert `dict["appsBundles"] == ["com.a","com.b"]`.
- **Export omits key when nil:** `appsBundles: nil` → key omitted.
- **Export omits key when empty:** `[]` → key omitted (builder rule).
- **Import parses appsBundles:** payload with array → saved `AccountModel.appsBundles == [...]`, `origin == .imported`.
- **Import legacy file (no key):** imported account `appsBundles == nil`, `allowsApp` true for any id.
- **Import empty array ⇒ all apps:** payload `"appsBundles": []` → `allowsApp("x") == true` (backward-compat contract).

### 7b. New `StackConnectTests/Models/AccountModelScopeTests.swift`
- `allowsApp` truth table: `nil` ⇒ all true; `[]` ⇒ all true; `["a"]` ⇒ only "a".
- Codable round-trip incl. legacy JSON without the key ⇒ `appsBundles == nil`.

### 7c. Extend `StackConnectTests/Services/SyncServiceTests.swift`
- Seed `MockAppleAccountSyncing.apps` with bundleIds a/b/c; imported account `appsBundles == ["a","c"]`; run `syncAll`; assert only a & c persist (b filtered). Companion with `nil` and with `[]` ⇒ all three persist (fast-path parity).
- **Purge test:** pre-seed app "b", sync with `["a","c"]`, assert "b" deleted (5a purge).
- `MockAppleAccountSyncing.syncApps(accountId:store:)` currently calls `fetchApps()` ignoring `store` ⇒ tests exercise 5a. For 5b add `SwiftDataBlobStoreScopeTests` (imported account + `save` for an excluded bundle ⇒ nothing persisted).

### 7d. `AppListViewModel` filtering
- Seed cached a/b/c + account scoped to a/c, call `loadApps`, assert `uiState.apps` excludes b (5c). Create `AppListViewModelTests` if absent.

### 7e. `AccountCryptoTests` — no new crypto tests
Container unchanged; `appsBundles` is payload, covered by 7a round-trips.

**Test target:** `StackConnectTests` (`project.yml:207`; scheme wires test at `:245`/`:265`). Delegate execution to the `test-runner` agent.

---

## 8. Step-by-step ordered task breakdown

1. **Model foundation** — `AccountModel`: `appsBundles`, `CodingKeys`, decoder line, `init` param, `allowsApp` (nil/empty ⇒ all). Add `AccountModelScopeTests`.
2. **Payload builder** — `AccountExportPayloadBuilder.makeJSON(...)` with the `appsBundles` rule; `xcodegen generate`.
3. **Export serialization** — widen both `exportAccountWithRules` signatures (protocol + 2 impls); route through builder.
4. **Import parsing** — parse `appsBundles` in `importAccount`, pass into `AccountModel`. Add `SettingsAccountsViewModelTests`.
5. **Enforcement** — `SyncService.runAccountSync` (filter + purge), `SwiftDataBlobStore.save` (skip excluded), `AppListViewModel.loadApps` (read + write filter). Extend `SyncServiceTests`; add blob-store + AppList tests.
6. **Export UI** — widen `onExport`; add "Apps permissions" section + `AppsPermissionPickerSheet`; wire `selectedBundleIds`/`performExport`; empty-state footer. `xcodegen generate`.
7. **Host wiring** — `SettingsAccountsView` & `AccountSettingsView`: fetch account apps, pass `availableApps`, forward `appsBundles` in `onExport`.
8. **Localization** — add §6 strings.
9. **Verify** — `xcodegen generate --spec project.yml` + `xcodebuild build`; delegate suite to `test-runner`; fix→re-run until green.

### Risks & edge cases
- **Apps not synced at export time** — fall back to "all apps" (no `appsBundles`); never block export.
- **Three write paths** — the non-obvious one is `SwiftDataBlobStore` (Rust core writes apps directly). §5b is mandatory.
- **SwiftData migration** — safe (optional + decode-tolerant); verify `AccountModel` is a Codable blob, not a rigid `@Model`.
- **Bundle ID vs ASC app ID** — plan uses **bundle ID** (issue proposal + human-readable; unique within a team).
- **Cascade to reviews/versions/widgets** — handled: excluded apps never persisted ⇒ no orphan references.
- **Duplicated export code** — shared builder preferred; fallback is duplicating the 3-line addition. Flag to reviewer.
- **`JSONSerialization` typing** — `appsBundles` may deserialize as `[Any]`; tolerant casting on import.

---

**Backward-compat guarantee restated:** absent / `null` / `[]` all ⇒ every app available. Only a non-empty `appsBundles` restricts. Existing files and accounts are unaffected.
