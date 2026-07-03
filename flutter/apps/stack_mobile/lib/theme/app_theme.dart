import 'package:flutter/material.dart';

import 'brand_tokens.dart';

/// Builds the Material 3 light/dark [ThemeData] from the brand tokens.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BrandTokens.seed,
        brightness: brightness,
      ),
    );
  }
}
