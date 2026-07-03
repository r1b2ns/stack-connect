import 'package:go_router/go_router.dart';

import 'features/shell/home_shell.dart';

/// Top-level router for the desktop app. A single `/` route for the host slice.
GoRouter buildRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeShell(),
      ),
    ],
  );
}
