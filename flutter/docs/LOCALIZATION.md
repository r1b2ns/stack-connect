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

**Status:** Plan approved; pilot in progress (apps / archived / app-detail screens, en + pt).
