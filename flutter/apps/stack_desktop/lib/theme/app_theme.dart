import 'package:fluent_ui/fluent_ui.dart';

import 'brand_tokens.dart';

/// Builds the Fluent light/dark [FluentThemeData] from the brand tokens.
abstract final class AppTheme {
  static FluentThemeData light() => _build(Brightness.light);

  static FluentThemeData dark() => _build(Brightness.dark);

  static FluentThemeData _build(Brightness brightness) {
    return FluentThemeData(
      brightness: brightness,
      accentColor: BrandTokens.accent,
    );
  }
}
