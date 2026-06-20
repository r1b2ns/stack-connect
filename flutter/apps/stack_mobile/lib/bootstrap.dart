import 'package:flutter/material.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'app.dart';

/// Initializes the Rust runtime, then runs the app under a [ProviderScope].
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const ProviderScope(child: StackMobileApp()));
}
