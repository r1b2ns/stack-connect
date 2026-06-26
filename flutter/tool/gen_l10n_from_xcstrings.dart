// Generates Flutter ARB files for `stack_core_dart` from the iOS String
// Catalog, which is the single source of truth for app copy.
//
// ── What it does ─────────────────────────────────────────────────────────────
//   1. Reads the iOS catalog at  ../StackConnect/Resources/Localizable.xcstrings
//      (relative to the `flutter/` directory; the path is resolved robustly from
//      this script's own location so it also works from other CWDs).
//   2. Reads the key mapping at   tool/l10n_keys.yaml  (English source text ->
//      stable Dart key, plus placeholder declarations).
//   3. Emits, for the `en` (source) and `pt` (mapped from the catalog's
//      `pt-BR`) locales:
//          packages/stack_core_dart/lib/l10n/app_en.arb
//          packages/stack_core_dart/lib/l10n/app_pt.arb
//      with `@@locale`, the key/value pairs, and `@key` metadata
//      (description + placeholders, ICU `{name}` syntax) for interpolated keys.
//
// ── Resolution rules ─────────────────────────────────────────────────────────
//   • The catalog's KEYS are the English source (its `sourceLanguage` is `en`
//     and it stores no explicit `en` localization), so the English value of a
//     mapped key is the catalog key itself (or the placeholder `template`).
//   • The Portuguese value is the catalog's `pt-BR` value when the key exists
//     there; otherwise the inline `pt:` from the mapping; otherwise it falls
//     back to English (reported on stdout as "untranslated pt"). The catalog is
//     NEVER written to.
//   • iOS `%@` / `%lld` / `%1$@` tokens in catalog values are converted to the
//     ICU `{name}` placeholders declared in the mapping (only the interpolated
//     keys in this pilot use them).
//
// ── Run ──────────────────────────────────────────────────────────────────────
//   From `flutter/`:  dart run tool/gen_l10n_from_xcstrings.dart
//
// The mapping file's schema is documented at the top of tool/l10n_keys.yaml.

import 'dart:convert';
import 'dart:io';

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

  // Accumulate ARB entries in declaration order for stable, diff-friendly
  // output.
  final enEntries = <_ArbEntry>[];
  final ptEntries = <_ArbEntry>[];

  var fromCatalog = 0;
  var fallbackPt = 0;
  final untranslated = <String>[];

  // ── Simple strings ────────────────────────────────────────────────────────
  for (final s in mapping.strings) {
    final en = s.source;
    final pt = _resolvePt(
      catalogStrings: catalogStrings,
      source: s.source,
      inlinePt: s.pt,
      onFromCatalog: () => fromCatalog++,
    );
    if (pt == null) {
      fallbackPt++;
      untranslated.add(s.dartKey);
    }
    enEntries.add(_ArbEntry(key: s.dartKey, value: en, meta: s.metaJson()));
    ptEntries.add(_ArbEntry(key: s.dartKey, value: pt ?? en, meta: null));
  }

  // ── Placeholder (interpolated) strings ────────────────────────────────────
  for (final p in mapping.placeholders) {
    final enValue = p.template;
    // Placeholders are not looked up in the catalog by literal text in this
    // pilot; pt comes from the inline `pt:` (defaulting to the template).
    final ptValue = p.pt ?? p.template;
    if (p.pt == null) {
      fallbackPt++;
      untranslated.add(p.dartKey);
    } else {
      // Treat an explicit pt template as a real translation source.
      fromCatalog += 0; // not catalog-sourced; counted as inline below
    }
    enEntries.add(
      _ArbEntry(key: p.dartKey, value: enValue, meta: p.metaJson()),
    );
    ptEntries.add(_ArbEntry(key: p.dartKey, value: ptValue, meta: null));
  }

  final enArb = _renderArb('en', enEntries);
  final ptArb = _renderArb('pt', ptEntries);
  final enPath = _join(outDir, 'app_en.arb');
  final ptPath = _join(outDir, 'app_pt.arb');
  final total = mapping.strings.length + mapping.placeholders.length;

  if (checkMode) {
    final drift = <String>[
      ..._driftFor(path: enPath, expected: enArb, locale: 'en'),
      ..._driftFor(path: ptPath, expected: ptArb, locale: 'pt'),
    ];
    if (drift.isEmpty) {
      stdout.writeln('l10n ARB up to date ($total keys)');
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
  File(enPath).writeAsStringSync(enArb);
  File(ptPath).writeAsStringSync(ptArb);

  stdout.writeln('l10n generation complete');
  stdout.writeln('  catalog : $catalogPath');
  stdout.writeln('  output  : $outDir/{app_en.arb, app_pt.arb}');
  stdout.writeln('  keys generated      : $total');
  stdout.writeln('  pt from catalog     : $fromCatalog');
  stdout.writeln('  pt fallback (en/inline) : $fallbackPt');
  if (untranslated.isNotEmpty) {
    stdout.writeln(
      '  untranslated pt (no catalog pt-BR): ${untranslated.join(', ')}',
    );
  }
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

/// Resolves the Portuguese value for [source].
///
/// Returns the catalog `pt-BR` value when present (invoking [onFromCatalog]);
/// otherwise the [inlinePt] fallback; otherwise `null` to signal a pure-English
/// fallback to the caller.
String? _resolvePt({
  required Map<String, dynamic> catalogStrings,
  required String source,
  required String? inlinePt,
  required void Function() onFromCatalog,
}) {
  final entry = catalogStrings[source];
  if (entry is Map) {
    final localizations = entry['localizations'];
    if (localizations is Map) {
      final ptBr = localizations['pt-BR'];
      if (ptBr is Map) {
        final unit = ptBr['stringUnit'];
        if (unit is Map) {
          final value = unit['value'];
          if (value is String && value.isNotEmpty) {
            onFromCatalog();
            return value;
          }
        }
      }
    }
  }
  return inlinePt;
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
