import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'router.dart';
import 'theme/app_theme.dart';

/// Root Material 3 application widget.
class StackMobileApp extends StatefulWidget {
  const StackMobileApp({super.key});

  @override
  State<StackMobileApp> createState() => _StackMobileAppState();
}

class _StackMobileAppState extends State<StackMobileApp> {
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Stack Connect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
    );
  }
}
