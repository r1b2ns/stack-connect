// Generates Flutter ARB files for `stack_core_dart` from the iOS String
// Catalog, which is the single source of truth for app copy.
//
// ── What it does ─────────────────────────────────────────────────────────────
//   1. Reads the iOS catalog at  ../StackConnect/Resources/Localizable.xcstrings
//      (relative to the `flutter/` directory; the path is resolved robustly from
//      this script's own location so it also works from other CWDs).
//   2. Reads the key mapping at   tool/l10n_keys.yaml  (English source text ->
//      stable Dart key, plus placeholder declarations).
//   3. Emits one ARB per catalog locale (subject to the coverage threshold
//      below) into  packages/stack_core_dart/lib/l10n/app_<flutterLocale>.arb,
//      with `@@locale`, the key/value pairs, and `@key` metadata (description +
//      placeholders, ICU `{name}` syntax) on the `en` TEMPLATE only.
//
//      The catalog<->Flutter locale mapping is [_localeMap]: en->en, de->de,
//      es->es, es-MX->es_MX, fr->fr, it->it, ja->ja, ko->ko, nl->nl,
//      pt-BR->pt, pt-PT->pt_PT, ru->ru, sv->sv, zh-Hant->zh_Hant.
//
// ── Resolution rules ─────────────────────────────────────────────────────────
//   • `en` is the source/template: every value is the catalog key itself (or
//     the placeholder `template`). It is also the universal fallback.
//   • For any other locale, each key takes the catalog's translated value for
//     that locale (state==translated, non-empty) when present; otherwise it
//     FALLS BACK to the English value. The inline `pt:` fallbacks in the
//     mapping are honored ONLY for the `pt` locale (pt-BR). Other locales are
//     never hand-translated here — English fallback is intentional.
//   • iOS `%@` / `%lld` / `%1$@` tokens in catalog values are converted to the
//     ICU `{name}` placeholders declared in the mapping (only the interpolated
//     keys use them).
//   • The catalog is NEVER written to.
//
// ── Coverage threshold ───────────────────────────────────────────────────────
//   A locale whose real catalog coverage is below [_minCoveragePct] of the
//   total keys is SKIPPED (it would be ~all English) and reported as skipped.
//   `en` and `pt` are always kept.
//
// ── Run ──────────────────────────────────────────────────────────────────────
//   From `flutter/`:  dart run tool/gen_l10n_from_xcstrings.dart
//   Staleness check:  dart run tool/gen_l10n_from_xcstrings.dart --check
//
// The mapping file's schema is documented at the top of tool/l10n_keys.yaml.

import 'dart:convert';
import 'dart:io';

/// Catalog locale -> Flutter ARB locale (used for `@@locale` and the filename
/// suffix `app_<value>.arb`). Order here is the emit/report order.
const _localeMap = <String, String>{
  'en': 'en', // source / template
  'de': 'de',
  'es': 'es',
  'es-MX': 'es_MX',
  'fr': 'fr',
  'it': 'it',
  'ja': 'ja',
  'ko': 'ko',
  'nl': 'nl',
  'pt-BR': 'pt',
  'pt-PT': 'pt_PT',
  'ru': 'ru',
  'sv': 'sv',
  'zh-Hant': 'zh_Hant',
};

/// Locales always emitted regardless of coverage (the pilot/source set).
const _alwaysKeep = <String>{'en', 'pt'};

/// Minimum real-catalog coverage (% of total keys) for a non-kept locale to be
/// emitted. Below this it is skipped (it would be ~all English).
const _minCoveragePct = 10.0;

void main(List<String> args) {
  // `--check` (CI staleness guard): generate the ARB in memory and diff against
  // the on-disk files instead of writing. Exits 1 on drift, 0 when up to date.
  final checkMode = args.contains('--check');

  final scriptDir = _scriptDir();
  // flutter/tool/gen_l10n_from_xcstrings.dart  ->  flutter/
  final flutterRoot = Directory(_join(scriptDir, '..')).absolute;

  final catalogPath = _join(
    flutterRoot.path,
    '../StackConnect/Resources/Localizable.xcstrings',
  );
  final mappingPath = _join(flutterRoot.path, 'tool/l10n_keys.yaml');
  final outDir = _join(
    flutterRoot.path,
    'packages/stack_core_dart/lib/l10n',
  );

  final catalogFile = File(catalogPath);
  if (!catalogFile.existsSync()) {
    stderr.writeln('error: catalog not found at $catalogPath');
    exit(1);
  }
  final mappingFile = File(mappingPath);
  if (!mappingFile.existsSync()) {
    stderr.writeln('error: mapping not found at $mappingPath');
    exit(1);
  }

  final catalog =
      json.decode(catalogFile.readAsStringSync()) as Map<String, dynamic>;
  final catalogStrings = (catalog['strings'] as Map).cast<String, dynamic>();

  final mapping = _Mapping.parse(mappingFile.readAsStringSync());
  final total = mapping.strings.length + mapping.placeholders.length;

  // Build the ARB content + a coverage stat for every catalog locale.
  final results = <_LocaleResult>[];
  for (final catalogLocale in _localeMap.keys) {
    final flutterLocale = _localeMap[catalogLocale]!;
    results.add(
      _buildLocale(
        catalogLocale: catalogLocale,
        flutterLocale: flutterLocale,
        mapping: mapping,
        catalogStrings: catalogStrings,
      ),
    );
  }

  // Decide which locales to emit: always keep [_alwaysKeep]; otherwise require
  // [_minCoveragePct] real catalog coverage.
  bool keep(_LocaleResult r) =>
      _alwaysKeep.contains(r.flutterLocale) || r.coveragePct >= _minCoveragePct;
  final kept = results.where(keep).toList();
  final skipped = results.where((r) => !keep(r)).toList();

  if (checkMode) {
    final drift = <String>[];
    for (final r in kept) {
      drift.addAll(
        _driftFor(
          path: _join(outDir, 'app_${r.flutterLocale}.arb'),
          expected: r.arb,
          locale: r.flutterLocale,
        ),
      );
    }
    // Flag any on-disk ARB for a now-skipped locale that should be removed.
    for (final r in skipped) {
      final f = File(_join(outDir, 'app_${r.flutterLocale}.arb'));
      if (f.existsSync()) {
        drift.add('app_${r.flutterLocale}.arb: present on disk but locale is '
            'below the ${_minCoveragePct.toStringAsFixed(0)}% threshold '
            '(${r.fromCatalog}/$total) — delete it');
      }
    }
    if (drift.isEmpty) {
      stdout.writeln(
        'l10n ARB up to date ($total keys, ${kept.length} locales: '
        '${kept.map((r) => r.flutterLocale).join(', ')})',
      );
      exit(0);
    }
    stderr.writeln('l10n ARB is STALE — regenerate with:');
    stderr.writeln('  dart run tool/gen_l10n_from_xcstrings.dart');
    stderr.writeln('');
    for (final line in drift) {
      stderr.writeln('  $line');
    }
    exit(1);
  }

  Directory(outDir).createSync(recursive: true);
  for (final r in kept) {
    File(_join(outDir, 'app_${r.flutterLocale}.arb')).writeAsStringSync(r.arb);
  }

  // ── Summary ─────────────────────────────────────────────────────────────────
  stdout.writeln('l10n generation complete');
  stdout.writeln('  catalog : $catalogPath');
  stdout.writeln('  output  : $outDir/app_<locale>.arb');
  stdout.writeln('  keys per locale : $total');
  stdout.writeln('  included locales (${kept.length}):');
  for (final r in kept) {
    final fallback = total - r.fromCatalog;
    final note = r.flutterLocale == 'en' ? '  (source/template)' : '';
    stdout.writeln(
      '    ${r.flutterLocale.padRight(7)} '
      '${r.fromCatalog}/$total from catalog, '
      '$fallback English fallback$note',
    );
  }
  if (skipped.isNotEmpty) {
    stdout.writeln('  skipped locales (<${_minCoveragePct.toStringAsFixed(0)}% '
        'coverage, ${skipped.length}):');
    for (final r in skipped) {
      stdout.writeln(
        '    ${r.flutterLocale.padRight(7)} '
        '${r.fromCatalog}/$total from catalog '
        '(${r.coveragePct.toStringAsFixed(1)}%) — not emitted',
      );
    }
  }
}

/// Builds the ARB content and coverage stat for one [catalogLocale].
///
/// `en` (the source) takes the catalog key as every value and carries the
/// `@key` metadata. Every other locale takes the catalog's translated value
/// when present (counting toward [_LocaleResult.fromCatalog]); else the inline
/// `pt:` fallback (pt only); else the English value.
_LocaleResult _buildLocale({
  required String catalogLocale,
  required String flutterLocale,
  required _Mapping mapping,
  required Map<String, dynamic> catalogStrings,
}) {
  final isEn = flutterLocale == 'en';
  final isPt = flutterLocale == 'pt';
  final entries = <_ArbEntry>[];
  var fromCatalog = 0;

  // ── Simple strings ────────────────────────────────────────────────────────
  for (final s in mapping.strings) {
    final en = s.source;
    String value;
    if (isEn) {
      value = en;
    } else {
      final translated = _catalogValue(catalogStrings, s.source, catalogLocale);
      if (translated != null) {
        fromCatalog++;
        value = translated;
      } else {
        // Inline pt: fallback applies to the pt locale only; else English.
        value = (isPt ? s.pt : null) ?? en;
      }
    }
    entries.add(
      _ArbEntry(key: s.dartKey, value: value, meta: isEn ? s.metaJson() : null),
    );
  }

  // ── Placeholder (interpolated) strings ────────────────────────────────────
  // Placeholders are not looked up in the catalog by literal text; the template
  // is the en value, and pt may override via inline pt:. Other locales reuse
  // the (English) template.
  for (final p in mapping.placeholders) {
    final value = isEn ? p.template : (isPt ? (p.pt ?? p.template) : p.template);
    entries.add(
      _ArbEntry(key: p.dartKey, value: value, meta: isEn ? p.metaJson() : null),
    );
  }

  final total = mapping.strings.length + mapping.placeholders.length;
  return _LocaleResult(
    flutterLocale: flutterLocale,
    arb: _renderArb(flutterLocale, entries),
    fromCatalog: fromCatalog,
    total: total,
  );
}

/// The generated ARB + coverage stat for a single locale.
class _LocaleResult {
  _LocaleResult({
    required this.flutterLocale,
    required this.arb,
    required this.fromCatalog,
    required this.total,
  });

  final String flutterLocale;
  final String arb;

  /// Count of keys whose value came from a real catalog translation.
  final int fromCatalog;
  final int total;

  double get coveragePct => total == 0 ? 0 : 100 * fromCatalog / total;
}

/// Returns the catalog's translated value of [source] for [catalogLocale]
/// (state==translated, non-empty), or null when absent.
String? _catalogValue(
  Map<String, dynamic> catalogStrings,
  String source,
  String catalogLocale,
) {
  final entry = catalogStrings[source];
  if (entry is! Map) return null;
  final localizations = entry['localizations'];
  if (localizations is! Map) return null;
  final loc = localizations[catalogLocale];
  if (loc is! Map) return null;
  final unit = loc['stringUnit'];
  if (unit is! Map) return null;
  final state = unit['state'];
  final value = unit['value'];
  if (state == 'translated' && value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

/// Compares the on-disk ARB at [path] against the freshly [expected] content.
///
/// Returns a list of human-readable drift lines (empty when identical): a
/// missing-file marker, or the set of keys that were added / removed / changed
/// relative to the on-disk file. Used by `--check` to fail CI on stale ARB.
List<String> _driftFor({
  required String path,
  required String expected,
  required String locale,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    return ['app_$locale.arb: MISSING on disk (would be created)'];
  }
  final onDisk = file.readAsStringSync();
  if (onDisk == expected) return const [];

  // Decode both to report which KEYS drifted (more useful than a raw text diff).
  Map<String, dynamic> decode(String s) {
    try {
      return (json.decode(s) as Map).cast<String, dynamic>();
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  final expectedMap = decode(expected);
  final onDiskMap = decode(onDisk);
  final expectedKeys = expectedMap.keys.toSet();
  final onDiskKeys = onDiskMap.keys.toSet();

  final added = expectedKeys.difference(onDiskKeys).toList()..sort();
  final removed = onDiskKeys.difference(expectedKeys).toList()..sort();
  final changed = <String>[
    for (final k in expectedKeys.intersection(onDiskKeys))
      if ('${expectedMap[k]}' != '${onDiskMap[k]}') k,
  ]..sort();

  final lines = <String>['app_$locale.arb: drifted'];
  if (added.isNotEmpty) lines.add('  + added:   ${added.join(', ')}');
  if (removed.isNotEmpty) lines.add('  - removed: ${removed.join(', ')}');
  if (changed.isNotEmpty) lines.add('  ~ changed: ${changed.join(', ')}');
  if (added.isEmpty && removed.isEmpty && changed.isEmpty) {
    // Same keys/values but text differs (e.g. formatting) — flag generically.
    lines.add('  (content differs; re-run the generator to normalize)');
  }
  return lines;
}

/// Renders an ARB document with stable 2-space indentation.
String _renderArb(String locale, List<_ArbEntry> entries) {
  final map = <String, dynamic>{'@@locale': locale};
  for (final e in entries) {
    map[e.key] = e.value;
    if (e.meta != null) map['@${e.key}'] = e.meta;
  }
  return '${const JsonEncoder.withIndent('  ').convert(map)}\n';
}

class _ArbEntry {
  _ArbEntry({required this.key, required this.value, required this.meta});

  final String key;
  final String value;
  final Map<String, dynamic>? meta;
}

// ── Mapping model ─────────────────────────────────────────────────────────────

class _StringMapping {
  /// English source text (the catalog key). For disambiguating entries the YAML
  /// key may carry a trailing space (e.g. "Archived "); that is stripped here so
  /// the catalog lookup uses the real text.
  String get source => _sourceRaw.trimRight();
  final String _sourceRaw;

  final String dartKey;
  final String? pt;
  final String? description;

  Map<String, dynamic>? metaJson() {
    if (description == null) return null;
    return {'description': description};
  }

  factory _StringMapping.simple(String source, String dartKey) =>
      _StringMapping._(sourceRaw: source, dartKey: dartKey);

  factory _StringMapping.explicit(
    String source, {
    required String dartKey,
    String? pt,
    String? description,
  }) =>
      _StringMapping._(
        sourceRaw: source,
        dartKey: dartKey,
        pt: pt,
        description: description,
      );

  _StringMapping._({
    required String sourceRaw,
    required this.dartKey,
    this.pt,
    this.description,
  }) : _sourceRaw = sourceRaw;
}

class _PlaceholderMapping {
  _PlaceholderMapping({
    required this.dartKey,
    required this.template,
    required this.args,
    this.pt,
    this.description,
  });

  final String dartKey;
  final String template;
  final String? pt;
  final String? description;

  /// Ordered placeholder name -> Dart type (e.g. `String`).
  final Map<String, String> args;

  Map<String, dynamic> metaJson() {
    final placeholders = <String, dynamic>{};
    for (final entry in args.entries) {
      placeholders[entry.key] = {'type': entry.value};
    }
    return {
      if (description != null) 'description': description,
      'placeholders': placeholders,
    };
  }
}

class _Mapping {
  _Mapping({required this.strings, required this.placeholders});

  final List<_StringMapping> strings;
  final List<_PlaceholderMapping> placeholders;

  /// Parses the restricted YAML schema used by `l10n_keys.yaml`.
  ///
  /// Supported shapes (2-space indentation, no tabs):
  ///   strings:
  ///     "<source>": <dartKey>
  ///     "<source>":
  ///       key: <dartKey>
  ///       pt: "<text>"
  ///       description: "<text>"
  ///   placeholders:
  ///     <dartKey>:
  ///       template: "<text>"
  ///       pt: "<text>"
  ///       description: "<text>"
  ///       args:
  ///         <name>: <Type>
  factory _Mapping.parse(String source) {
    final lines = source.split('\n');
    final strings = <_StringMapping>[];
    final placeholders = <_PlaceholderMapping>[];

    String? section; // 'strings' | 'placeholders'

    // Pending nested-block accumulation.
    String? pendingStringSource;
    String? pendingStringKey;
    String? pendingStringPt;
    String? pendingStringDesc;

    String? pendingPhKey;
    String? pendingPhTemplate;
    String? pendingPhPt;
    String? pendingPhDesc;
    Map<String, String>? pendingPhArgs;
    var inArgs = false;

    void flushString() {
      if (pendingStringSource == null) return;
      strings.add(
        _StringMapping.explicit(
          pendingStringSource!,
          dartKey: pendingStringKey!,
          pt: pendingStringPt,
          description: pendingStringDesc,
        ),
      );
      pendingStringSource = null;
      pendingStringKey = null;
      pendingStringPt = null;
      pendingStringDesc = null;
    }

    void flushPlaceholder() {
      if (pendingPhKey == null) return;
      placeholders.add(
        _PlaceholderMapping(
          dartKey: pendingPhKey!,
          template: pendingPhTemplate ?? '',
          pt: pendingPhPt,
          description: pendingPhDesc,
          args: pendingPhArgs ?? <String, String>{},
        ),
      );
      pendingPhKey = null;
      pendingPhTemplate = null;
      pendingPhPt = null;
      pendingPhDesc = null;
      pendingPhArgs = null;
      inArgs = false;
    }

    for (final raw in lines) {
      final line = _stripComment(raw);
      if (line.trim().isEmpty) continue;

      final indent = _indentOf(line);
      final content = line.trim();

      // Top-level section headers.
      if (indent == 0) {
        flushString();
        flushPlaceholder();
        if (content == 'strings:') {
          section = 'strings';
        } else if (content == 'placeholders:') {
          section = 'placeholders';
        } else {
          section = null;
        }
        continue;
      }

      if (section == 'strings') {
        if (indent == 2) {
          // New string entry — flush any pending nested one.
          flushString();
          final kv = _splitKeyValue(content);
          final key = _unquote(kv.key);
          if (kv.value.isEmpty) {
            // Nested explicit form follows.
            pendingStringSource = key;
          } else {
            // Simple "source": dartKey
            strings.add(_StringMapping.simple(key, kv.value.trim()));
          }
        } else if (indent >= 4 && pendingStringSource != null) {
          final kv = _splitKeyValue(content);
          switch (kv.key) {
            case 'key':
              pendingStringKey = kv.value.trim();
            case 'pt':
              pendingStringPt = _unquote(kv.value.trim());
            case 'description':
              pendingStringDesc = _unquote(kv.value.trim());
          }
        }
      } else if (section == 'placeholders') {
        if (indent == 2) {
          flushPlaceholder();
          final kv = _splitKeyValue(content);
          pendingPhKey = kv.key.trim();
          pendingPhArgs = <String, String>{};
        } else if (pendingPhKey != null) {
          if (indent == 4) {
            inArgs = false;
            final kv = _splitKeyValue(content);
            switch (kv.key) {
              case 'template':
                pendingPhTemplate = _unquote(kv.value.trim());
              case 'pt':
                pendingPhPt = _unquote(kv.value.trim());
              case 'description':
                pendingPhDesc = _unquote(kv.value.trim());
              case 'args':
                inArgs = true;
            }
          } else if (indent >= 6 && inArgs) {
            final kv = _splitKeyValue(content);
            pendingPhArgs![kv.key.trim()] = kv.value.trim();
          }
        }
      }
    }

    flushString();
    flushPlaceholder();

    return _Mapping(strings: strings, placeholders: placeholders);
  }
}

// ── Tiny YAML helpers (scoped to this file's restricted schema) ───────────────

class _KeyValue {
  _KeyValue(this.key, this.value);
  final String key;
  final String value;
}

/// Splits a `key: value` line, respecting a quoted key that may itself contain
/// a colon. Returns the value verbatim (caller trims/unquotes as needed).
_KeyValue _splitKeyValue(String content) {
  if (content.startsWith('"')) {
    // Quoted key — find the closing quote (handling escaped quotes).
    var i = 1;
    final buf = StringBuffer('"');
    while (i < content.length) {
      final ch = content[i];
      buf.write(ch);
      if (ch == '\\' && i + 1 < content.length) {
        buf.write(content[i + 1]);
        i += 2;
        continue;
      }
      if (ch == '"') {
        i++;
        break;
      }
      i++;
    }
    final key = buf.toString();
    final rest = content.substring(i).trimLeft();
    final value = rest.startsWith(':') ? rest.substring(1).trim() : '';
    return _KeyValue(key, value);
  }
  final idx = content.indexOf(':');
  if (idx < 0) return _KeyValue(content, '');
  return _KeyValue(content.substring(0, idx), content.substring(idx + 1));
}

/// Removes a trailing `# comment` not inside a quoted string.
String _stripComment(String line) {
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      // Count preceding backslashes to respect escaping.
      var backslashes = 0;
      var j = i - 1;
      while (j >= 0 && line[j] == '\\') {
        backslashes++;
        j--;
      }
      if (backslashes.isEven) inQuotes = !inQuotes;
    } else if (ch == '#' && !inQuotes) {
      return line.substring(0, i);
    }
  }
  return line;
}

/// Strips surrounding double quotes and unescapes `\"` and `\\`.
String _unquote(String s) {
  final t = s.trim();
  if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
    final inner = t.substring(1, t.length - 1);
    return inner.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
  }
  return t;
}

int _indentOf(String line) {
  var n = 0;
  while (n < line.length && line[n] == ' ') {
    n++;
  }
  return n;
}

// ── Path helpers (avoid importing package:path from a tool script) ────────────

String _scriptDir() {
  final scriptPath = Platform.script.toFilePath();
  final idx = scriptPath.lastIndexOf(Platform.pathSeparator);
  return idx < 0 ? '.' : scriptPath.substring(0, idx);
}

String _join(String a, String b) {
  if (a.endsWith(Platform.pathSeparator)) return '$a$b';
  return '$a${Platform.pathSeparator}$b';
}
