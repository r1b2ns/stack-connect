// Hardcoded user-facing string lint for the Flutter apps.
//
// Scans `apps/stack_desktop/lib` and `apps/stack_mobile/lib` for
// `Text('...')` / `Text("...")` constructors carrying a human-language string
// literal that should be localized via `AppLocalizations` instead. Prints each
// finding as `file:line  <literal>` and exits 1 when any are found, so it can
// gate CI alongside `analyze` / `test`.
//
// ── What counts as a finding ─────────────────────────────────────────────────
//   A `Text(` immediately wrapping a single-quoted or double-quoted literal
//   (optionally `const`-prefixed) whose content is "human language":
//     • contains at least one ASCII letter, AND
//     • either contains an ASCII space OR has length > 2
//   …so single glyphs ("—", "·") and 1–2 char tokens are skipped.
//   Pure interpolations like `Text('$foo')` (the literal is only `$...`
//   placeholders / punctuation, no static letters) are NOT findings — there is
//   no translatable text there.
//
// ── Opt-outs ─────────────────────────────────────────────────────────────────
//   • `// l10n-ignore` on the same line OR the line directly above suppresses
//     that finding (use sparingly, with a reason).
//   • The ALLOWLIST below exempts brand/proper nouns and pure punctuation that
//     are intentionally never localized.
//   • _excludedPaths lists files deferred from localization (the add-account
//     flows, which still carry WIP) — see the TODO(l10n) note there.
//
// ── Run ──────────────────────────────────────────────────────────────────────
//   From `flutter/`:  dart run tool/check_no_hardcoded_strings.dart

import 'dart:io';

/// Literals that are legitimately NOT localized:
///   • brand / proper nouns (rendered verbatim in every locale)
///   • pure punctuation / separators used as glyphs
/// Compared against the literal's exact, trimmed content.
const _allowlist = <String>{
  // Brand / proper nouns.
  'Stack Connect',
  'StackConnect',
  'GitHub',
  'Github',
  'Firebase',
  'Play Store',
  // Pure punctuation / separators (also filtered by the heuristic, kept here as
  // explicit intent in case they appear with surrounding context).
  '·',
  '—',
  '…',
  '-',
};

/// Files deferred from localization. They still carry unrelated work-in-progress
/// and were intentionally skipped by the migration; excluded so the lint stays
/// green today.
///
/// TODO(l10n): localize the add-account flows (desktop + mobile) and remove
/// these exclusions. They are the only user-facing screens still pending.
const _excludedPaths = <String>[
  'features/accounts/add_account_pane.dart', // desktop add-account (WIP)
  'features/accounts/add_account_screen.dart', // mobile add-account (WIP)
];

/// Library roots to scan, relative to `flutter/`.
const _scanRoots = <String>[
  'apps/stack_desktop/lib',
  'apps/stack_mobile/lib',
];

/// Matches `Text('literal')` or `Text("literal")`, optionally `const`-prefixed.
/// Group 2 is the literal content. Escaped quotes inside the literal are
/// tolerated.
final _textLiteral = RegExp(
  r'''(?:const\s+)?Text\(\s*(['"])((?:\\.|(?!\1).)*)\1''',
);

void main(List<String> args) {
  final flutterRoot = _flutterRoot();
  final findings = <_Finding>[];
  var suppressedByIgnore = 0;
  var suppressedByAllowlist = 0;
  var excludedFiles = 0;

  for (final root in _scanRoots) {
    final dir = Directory(_join(flutterRoot, root));
    if (!dir.existsSync()) continue;

    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (_isExcluded(entity.path)) {
        excludedFiles++;
        continue;
      }

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        for (final match in _textLiteral.allMatches(line)) {
          final literal = _unescape(match.group(2)!);
          if (!_isHumanLanguage(literal)) continue;

          if (_allowlist.contains(literal.trim())) {
            suppressedByAllowlist++;
            continue;
          }
          if (_hasIgnore(lines, i)) {
            suppressedByIgnore++;
            continue;
          }

          findings.add(
            _Finding(
              path: _relative(flutterRoot, entity.path),
              line: i + 1,
              literal: literal,
            ),
          );
        }
      }
    }
  }

  if (findings.isEmpty) {
    stdout.writeln('check_no_hardcoded_strings: PASS — no hardcoded '
        'user-facing Text literals found');
    stdout.writeln('  suppressed: $suppressedByAllowlist allowlisted, '
        '$suppressedByIgnore via // l10n-ignore, '
        '$excludedFiles excluded file(s)');
    exit(0);
  }

  stderr.writeln('check_no_hardcoded_strings: FAIL — '
      '${findings.length} hardcoded user-facing Text literal(s):');
  stderr.writeln('');
  for (final f in findings) {
    stderr.writeln('  ${f.path}:${f.line}  ${_quote(f.literal)}');
  }
  stderr.writeln('');
  stderr.writeln('Localize via AppLocalizations (add a key to '
      'tool/l10n_keys.yaml, regenerate), or — if genuinely not translatable —');
  stderr.writeln('add it to the allowlist in this script or annotate the line '
      'with `// l10n-ignore`.');
  exit(1);
}

/// Heuristic: a "human language" literal contains a letter and is more than a
/// glyph/token. Pure interpolations (only `$...` and punctuation, no static
/// letters) are excluded.
bool _isHumanLanguage(String literal) {
  final trimmed = literal.trim();
  if (trimmed.isEmpty) return false;

  // Strip Dart string interpolations (`$foo`, `${expr}`) so a literal that is
  // ONLY interpolation (e.g. `'$_githubUri'`) carries no translatable text.
  final staticPart =
      trimmed.replaceAll(RegExp(r'\$\{[^}]*\}'), '').replaceAll(
            RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'),
            '',
          );

  final hasLetter = RegExp('[A-Za-z]').hasMatch(staticPart);
  if (!hasLetter) return false;

  final hasSpace = staticPart.contains(' ');
  return hasSpace || staticPart.trim().length > 2;
}

/// True when the current line ([index]) or the line directly above carries a
/// `// l10n-ignore` opt-out comment.
bool _hasIgnore(List<String> lines, int index) {
  bool isIgnore(String s) => s.contains('// l10n-ignore');
  if (isIgnore(lines[index])) return true;
  if (index > 0 && isIgnore(lines[index - 1])) return true;
  return false;
}

bool _isExcluded(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return _excludedPaths.any(normalized.endsWith);
}

/// Unescapes `\'`, `\"`, and `\\` so the reported literal reads naturally.
String _unescape(String s) => s
    .replaceAll(r"\'", "'")
    .replaceAll(r'\"', '"')
    .replaceAll(r'\\', r'\');

String _quote(String s) => "'$s'";

// ── Path helpers ──────────────────────────────────────────────────────────────

String _flutterRoot() {
  final scriptPath = Platform.script.toFilePath();
  final sep = Platform.pathSeparator;
  final idx = scriptPath.lastIndexOf('${sep}tool$sep');
  if (idx >= 0) return scriptPath.substring(0, idx);
  // Fallback: assume CWD is `flutter/`.
  return Directory.current.path;
}

String _join(String a, String b) {
  final sep = Platform.pathSeparator;
  final bb = b.replaceAll('/', sep);
  return a.endsWith(sep) ? '$a$bb' : '$a$sep$bb';
}

String _relative(String root, String path) {
  if (path.startsWith(root)) {
    final rel = path.substring(root.length);
    return rel.startsWith(Platform.pathSeparator) ? rel.substring(1) : rel;
  }
  return path;
}

class _Finding {
  _Finding({required this.path, required this.line, required this.literal});
  final String path;
  final int line;
  final String literal;
}
