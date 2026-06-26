import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'router.dart';
import 'theme/app_theme.dart';

/// Language codes that `FluentLocalizations` (fluent_ui) ships strings for.
///
/// `FluentLocalizations.delegate.isSupported` matches on `languageCode` only.
/// Every locale in [AppLocalizations.supportedLocales] is currently in this set,
/// so Fluent resolves them directly — but [_resolveFluentSafeLocale] guards
/// against a device/app locale whose language Fluent does NOT ship (which would
/// otherwise throw a "No FluentLocalizations found" assert at runtime). Our own
/// [AppLocalizations] and the Global* delegates are unaffected by this guard.
const _fluentSupportedLanguages = <String>{
  'ar', 'be', 'bn', 'ca', 'cs', 'de', 'el', 'en', 'es', 'fa', 'fr', 'he', //
  'hi', 'hr', 'hu', 'id', 'it', 'ja', 'ko', 'ku', 'ms', 'my', 'ne', 'nl', //
  'pl', 'pt', 'ro', 'ru', 'sk', 'sv', 'ta', 'th', 'tl', 'tr', 'ug', 'uk', //
  'ur', 'uz', 'vi', 'zh',
};

/// Root Fluent application widget.
class StackDesktopApp extends StatefulWidget {
  const StackDesktopApp({super.key});

  @override
  State<StackDesktopApp> createState() => _StackDesktopAppState();
}

class _StackDesktopAppState extends State<StackDesktopApp> {
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return FluentApp.router(
      title: 'Stack Connect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        FluentLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // Guard `FluentLocalizations` against a locale whose language it does not
      // ship (would assert at runtime). App strings still come from
      // [AppLocalizations]; this only steers Fluent's own widget strings.
      localeListResolutionCallback: (locales, supported) =>
          _resolveFluentSafeLocale(locales, supported),
      routerConfig: _router,
    );
  }
}

/// Resolves the active locale so that whatever is chosen has a Fluent-supported
/// language, falling back to the first supported locale (en) otherwise.
///
/// Mirrors Flutter's default best-match (exact locale → same language) but
/// rejects any candidate Fluent can't localize, so the app never lands on a
/// locale that makes `FluentLocalizations` throw.
Locale _resolveFluentSafeLocale(
  List<Locale>? preferred,
  Iterable<Locale> supported,
) {
  final supportedList = supported.toList();
  bool fluentSafe(Locale l) =>
      _fluentSupportedLanguages.contains(l.languageCode);

  for (final want in preferred ?? const <Locale>[]) {
    // Exact match first, then language-only match — both must be Fluent-safe.
    final exact = supportedList
        .where((s) => s == want && fluentSafe(s))
        .firstOrNull;
    if (exact != null) return exact;
    final byLang = supportedList
        .where((s) => s.languageCode == want.languageCode && fluentSafe(s))
        .firstOrNull;
    if (byLang != null) return byLang;
  }
  // Nothing matched (or matches weren't Fluent-safe): first Fluent-safe
  // supported locale, else the first supported locale (en is always present).
  return supportedList.firstWhere(fluentSafe, orElse: () => supportedList.first);
}
