import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'router.dart';
import 'theme/app_theme.dart';

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
      routerConfig: _router,
    );
  }
}
