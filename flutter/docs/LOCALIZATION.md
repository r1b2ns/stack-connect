# Localization — Single Source of Truth (iOS + Flutter)

## Current state (discovery)

- **iOS native** (`StackConnect/Resources/Localizable.xcstrings`): a mature Apple String Catalog with ~1,176 string keys across 14 locales (de, es, es-MX, fr, it, ja, ko, nl, pt-BR, pt-PT, ru, sv, zh-Hant, plus en source). pt-BR is already translated. Keys ARE the English source text; Xcode auto-extracts strings from `String(localized:)` at build time, with a GUI editor. sourceLanguage=en, catalog version 1.1.
- **Flutter** (apps/stack_desktop + apps/stack_mobile): NO localization at all. ~140 hardcoded English string literals; ~35 duplicated across desktop and mobile; ~15 use interpolation (e.g. `'${app.bundleId} · ${app.platform}'`, version/build, license error). No flutter_localizations, no ARB, no delegates. The shared package stack_core_dart has no UI strings.

## Why one file is not trivial (the core constraint)

A comparison table of the incompatible conventions:

| Aspect | iOS | Flutter gen-l10n |
|--------|-----|------------------|
| **Key** | English source text | Dart identifier (e.g. addAccount) |
| **Authoring** | Xcode auto-extraction | Manual ARB |
| **Placeholders** | %@, %lld, %1$@ | {name}, ICU plural |
| **Format** | .xcstrings | .arb |

**Conclusion:** unifying requires either rekeying iOS (rejected — touches 1,176 Swift call sites and loses Xcode auto-extraction) OR a generator that reconciles the formats.

## Chosen approach: A — .xcstrings as canonical source, generate Flutter ARB

The single source is the existing `Localizable.xcstrings` (already 14 languages). A script generates the Flutter ARB files from it. iOS is unchanged (keeps Xcode + auto-extraction + GUI). Flutter inherits pt-BR and the other languages for any string already in the catalog.

### Components

1. **Generator** `flutter/tool/gen_l10n_from_xcstrings.dart` — Parses the catalog and emits `app_en.arb`, `app_pt.arb`, ... (maps pt-BR → pt). Converts placeholders %@/%lld/%1$@ → ICU {name}; catalog plural variations → ICU {count, plural, ...}.

2. **Mapping file** `flutter/tool/l10n_keys.yaml` (version-controlled) — Maps English source text → stable Dart key (slug → camelCase), resolves collisions, and names the placeholders for the ~15 interpolated strings. Reviewed by a human once; new strings add one line. May carry inline en/pt fallbacks for Flutter-only strings not yet in the catalog.

3. **Shared l10n in stack_core_dart** — The generated ARB + Flutter gen-l10n produce ONE AppLocalizations consumed by both apps (dedupes the ~35 shared strings). l10n.yaml + `generate: true`.

4. **Wiring** — `apps/stack_desktop/lib/app.dart` (FluentApp.router) and `apps/stack_mobile/lib/app.dart` (MaterialApp.router): localizationsDelegates (AppLocalizations.delegate, plus FluentLocalizations on desktop and GlobalMaterial/Widgets/Cupertino on mobile) + supportedLocales: [en, pt, ...].

5. **Migration** — Replace the ~140 hardcoded strings with `AppLocalizations.of(context).<key>` (and formatX(...) for interpolations).

6. **Flutter-only strings** — (e.g. Builds/Versions/BetaGroups screens, desktop "soon"/settings) added to the .xcstrings as manual entries to preserve single-source (they show as "stale" in Xcode but persist), or kept in a separate FlutterOnly.xcstrings. During the pilot these may live as inline fallbacks in the mapping file to avoid editing the live catalog.

7. **Continuous sync** — The generator runs via melos / pre-build, and a CI check fails if the ARB is stale vs the .xcstrings.

## Phases

| Phase | Description |
|-------|-------------|
| **0** | Decision + setup. |
| **1** | Generator + mapping file. |
| **2** | l10n infra wired in both apps (shared via stack_core_dart). |
| **3** | Pilot: migrate the apps / archived / app-detail screens (desktop + mobile). |
| **4** | Migrate the rest feature-by-feature. |
| **5** | CI guard: a lint that fails on `Text('literal')` plus the staleness check. |
| **6** | Expand from en+pt to every well-covered catalog locale. |

## Supported languages & coverage

Flutter now ships the same languages the iOS catalog already translates. The
generator emits one ARB per catalog locale **whose real coverage of the mapped
keys is ≥ 10%**; locales below that threshold are skipped (they would be ~all
English) rather than shipped as English-only. `en` is the source/template and the
universal fallback; for any other locale each key uses the catalog's translated
value when present, else falls back to English (the `pt` inline fallbacks in
`l10n_keys.yaml` still apply to `pt` only).

**Included (9)** — coverage out of 98 keys (from the generator's summary):

| Locale (ARB) | Catalog locale | From catalog | English fallback |
|--------------|----------------|--------------|------------------|
| `en` | en (source) | template | — |
| `de` | de | 46/98 | 52 |
| `es` | es | 46/98 | 52 |
| `fr` | fr | 46/98 | 52 |
| `it` | it | 46/98 | 52 |
| `ja` | ja | 46/98 | 52 |
| `ko` | ko | 46/98 | 52 |
| `nl` | nl | 46/98 | 52 |
| `pt` | pt-BR | 46/98 (+inline pt fallbacks) | rest |

**Skipped (< 10% coverage, 0/98 in the catalog today):** `es-MX` (→`es_MX`),
`pt-PT` (→`pt_PT`), `ru`, `sv`, `zh-Hant` (→`zh_Hant`). They are listed in the
generator's `_localeMap` and will be emitted automatically once the catalog
gains translations for them and they cross the threshold.

`AppLocalizations.supportedLocales` is generated from these ARBs, and both apps
bind `supportedLocales: AppLocalizations.supportedLocales`, so the new languages
are picked up automatically.

### Desktop Fluent locale resolution

`fluent_ui`'s `FluentLocalizations.delegate` ships strings for a fixed language
set and matches on `languageCode` only. Every currently-included locale (en, de,
es, fr, it, ja, ko, nl, pt) **is** in Fluent's set, so it resolves them directly.
As a guard, `apps/stack_desktop/lib/app.dart` adds a
`localeListResolutionCallback` that steers the active locale to a Fluent-safe
language (falling back to `en`) if a device/app locale Fluent can't localize ever
appears — preventing a "No FluentLocalizations found" assert. App copy still comes
from `AppLocalizations`; the Global Material/Widgets/Cupertino delegates cover all
our locales, and mobile (`MaterialApp` + Global delegates) needs no such guard.
A desktop test pumps the shell under **every** `supportedLocales` entry to prove
no Fluent assert fires.

## Tooling & commands

There is **no melos / script runner** in this repo (the workspace uses Dart's
native pub `workspace:`), and **no CI** (`.github/workflows/` does not exist).
The pipeline is therefore driven by three raw `dart run` commands from the
`flutter/` directory:

| Command | Raw invocation (run from `flutter/`) | Purpose |
|---------|--------------------------------------|---------|
| `l10n:gen`   | `dart run tool/gen_l10n_from_xcstrings.dart` then, in `packages/stack_core_dart`, `flutter gen-l10n` (or `flutter pub get`) | Regenerate `app_en.arb` / `app_pt.arb` from the catalog + mapping, then rebuild `AppLocalizations`. |
| `l10n:check` | `dart run tool/gen_l10n_from_xcstrings.dart --check` | Staleness guard: regenerates in memory and diffs against the committed ARB. Prints drifted keys and **exits 1** if `l10n_keys.yaml` or the catalog changed without a regen; **exits 0** ("l10n ARB up to date") otherwise. Writes nothing. |
| `l10n:lint`  | `dart run tool/check_no_hardcoded_strings.dart` | Fails (**exit 1**) on any hardcoded user-facing `Text('...')` literal outside the allowlist / opt-outs / deferred paths. |

> If a melos.yaml (or other script runner) is later added, register these three
> as `l10n:gen` / `l10n:check` / `l10n:lint` so the names above resolve.

### `l10n:gen` — regenerate

Run after editing `tool/l10n_keys.yaml` or whenever the iOS catalog changes:

```sh
cd flutter
dart run tool/gen_l10n_from_xcstrings.dart
cd packages/stack_core_dart && flutter pub get   # triggers `flutter gen-l10n`
```

### `l10n:check` — staleness guard (CI)

```sh
cd flutter
dart run tool/gen_l10n_from_xcstrings.dart --check
```

The check decodes both the freshly-generated and on-disk ARB and reports which
keys were **added / removed / changed**, so a reviewer sees exactly what drifted.

### `l10n:lint` — hardcoded-string scanner (CI)

```sh
cd flutter
dart run tool/check_no_hardcoded_strings.dart
```

Scans `apps/stack_desktop/lib` + `apps/stack_mobile/lib` for `Text('...')` /
`Text("...")` literals that look like human language (contain a letter and
either a space or length > 2; pure `$`-interpolations are ignored).

**Opt-out:** add `// l10n-ignore` on the **same line or the line directly above**
a `Text(...)` to suppress one finding. Use sparingly, with a reason.

**Allowlist policy** (curated in `tool/check_no_hardcoded_strings.dart`): only
literals that are intentionally never translated —
- brand / proper nouns: `Stack Connect`, `StackConnect`, `GitHub`, `Github`,
  `Firebase`, `Play Store`;
- pure punctuation / separators: `·`, `—`, `…`, `-`.

Anything else that is genuinely user-facing must be localized with a real key
rather than allowlisted.

**Excluded paths** (deferred, still WIP — see `TODO(l10n)` in the scanner):
`features/accounts/add_account_pane.dart` (desktop) and
`features/accounts/add_account_screen.dart` (mobile).

### CI integration (when CI is added)

No CI exists yet. When one is introduced, add these two gates next to the
existing `flutter analyze` / `flutter test` steps (single lines, run from
`flutter/`):

```sh
dart run tool/gen_l10n_from_xcstrings.dart --check   # l10n:check
dart run tool/check_no_hardcoded_strings.dart        # l10n:lint
```

## Alternatives considered

- **B — Translation Management System** (Lokalise / Crowdin / Tolgee / Phrase): Natively import/export BOTH .xcstrings and .arb; the cloud becomes the single source, with a translator UI and translation states. Best for scaling translation and adding languages, at the cost of SaaS + CI integration. **Recommended if the translation team grows.**
- **C — Neutral master** (CSV/JSON/YAML) generating both formats: More flexible but adds indirection and still requires importing the existing translations first.
- **Rejected — rekeying iOS to semantic keys:** Massive, risky refactor of a mature app; loses Xcode auto-extraction.

## Risks / watch-outs

- **Generating keys from English text** is the sensitive part (collisions, punctuation) — mitigated by the reviewed mapping file.
- **Positional %@ placeholders** need names — defined manually for the ~15 interpolated cases.
- **Keeping Flutter-only strings** inside the iOS catalog requires discipline (or a separate catalog).

## Inventory summary (for sizing)

| Category | Count |
|----------|-------|
| Total distinct Flutter strings | ~140 |
| Shared desktop + mobile | ~35 |
| Desktop-only | ~65 |
| Mobile-only | ~40 |
| With interpolation | ~15 |
| In stack_core_dart | 0 |

Grouped roughly by feature: accounts, apps, app detail, archived, reviews, home, settings (desktop), builds/versions/beta-groups (mobile), shell/nav.

---

**Status:** Phases 0–6 done. All user-facing screens migrated to `AppLocalizations`
**except** the add-account flows (desktop `add_account_pane.dart` + mobile
`add_account_screen.dart`), which remain the only pending screens and are excluded
from `l10n:lint`. Flutter now ships **9 languages** (en, de, es, fr, it, ja, ko,
nl, pt) — every catalog locale at/above the 10% coverage threshold; 5 more
(es_MX, pt_PT, ru, sv, zh_Hant) are wired and skipped until the catalog
translates them. Phase 5 guards remain in place: the generator's `--check`
staleness gate (now diffing all 9 locale ARBs) and the hardcoded-string scanner.
There is no melos/CI in the repo, so the three commands run as raw `dart run`
invocations (documented above) and should be wired into CI when one is added.
