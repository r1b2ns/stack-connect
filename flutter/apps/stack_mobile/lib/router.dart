import 'package:go_router/go_router.dart';

import 'features/accounts/add_account_screen.dart';
import 'features/apps/app_detail_screen.dart';
import 'features/apps/apps_screen.dart';
import 'features/apps/archived_apps_screen.dart';
import 'features/beta_groups/beta_groups_screen.dart';
import 'features/builds/builds_screen.dart';
import 'features/home/home_screen.dart';
import 'features/reviews/reviews_screen.dart';
import 'features/versions/versions_screen.dart';

/// Top-level router for the mobile app: a single navigation stack.
///
/// `/`                                          → home shell (Accounts tab)
/// `/accounts/add`                              → add-account form
/// `/accounts/:accountId/apps`                  → apps for an account
/// `/accounts/:accountId/archived-apps`         → archived apps for an account
/// `/accounts/:accountId/apps/:appId`           → app detail
/// `/accounts/:accountId/apps/:appId/reviews`   → ratings & reviews
/// `/accounts/:accountId/apps/:appId/builds`    → testflight builds
/// `/accounts/:accountId/apps/:appId/versions`  → app store versions
/// `/accounts/:accountId/apps/:appId/beta-groups` → beta groups
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
            path: 'accounts/:accountId/archived-apps',
            builder: (context, state) => ArchivedAppsScreen(
              accountId: state.pathParameters['accountId']!,
            ),
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
                  GoRoute(
                    path: 'versions',
                    builder: (context, state) => VersionsScreen(
                      accountId: state.pathParameters['accountId']!,
                      appId: state.pathParameters['appId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'beta-groups',
                    builder: (context, state) => BetaGroupsScreen(
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
