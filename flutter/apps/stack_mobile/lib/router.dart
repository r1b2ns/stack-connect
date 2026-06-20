import 'package:go_router/go_router.dart';

import 'features/accounts/add_account_screen.dart';
import 'features/apps/app_detail_screen.dart';
import 'features/apps/apps_screen.dart';
import 'features/builds/builds_screen.dart';
import 'features/home/home_screen.dart';
import 'features/reviews/reviews_screen.dart';

/// Top-level router for the mobile app: a single navigation stack.
///
/// `/`                                          → home shell (Accounts tab)
/// `/accounts/add`                              → add-account form
/// `/accounts/:accountId/apps`                  → apps for an account
/// `/accounts/:accountId/apps/:appId`           → app detail
/// `/accounts/:accountId/apps/:appId/reviews`   → ratings & reviews
/// `/accounts/:accountId/apps/:appId/builds`    → testflight builds
GoRouter buildRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'accounts/add',
            builder: (context, state) => const AddAccountScreen(),
          ),
          GoRoute(
            path: 'accounts/:accountId/apps',
            builder: (context, state) => AppsScreen(
              accountId: state.pathParameters['accountId']!,
            ),
            routes: [
              GoRoute(
                path: ':appId',
                builder: (context, state) => AppDetailScreen(
                  accountId: state.pathParameters['accountId']!,
                  appId: state.pathParameters['appId']!,
                ),
                routes: [
                  GoRoute(
                    path: 'reviews',
                    builder: (context, state) => ReviewsScreen(
                      accountId: state.pathParameters['accountId']!,
                      appId: state.pathParameters['appId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'builds',
                    builder: (context, state) => BuildsScreen(
                      accountId: state.pathParameters['accountId']!,
                      appId: state.pathParameters['appId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
