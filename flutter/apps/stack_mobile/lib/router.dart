import 'package:go_router/go_router.dart';

import 'features/home/home_screen.dart';

/// Top-level router for the mobile app. A single `/` route for the host slice.
GoRouter buildRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );
}
