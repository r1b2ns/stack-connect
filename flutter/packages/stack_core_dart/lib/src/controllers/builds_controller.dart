import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gateway/core_gateway.dart';
import 'package:stack_core_rust/stack_core_rust.dart';
import 'connected_provider.dart';

/// The (account, app) key a [BuildsController] is scoped to.
typedef BuildsKey = ({String accountId, String appId});

/// TestFlight / App Store Connect builds for a single (account, app), newest
/// first.
///
/// Loads through the connected provider's Builds handle. This is a read-only
/// slice: it lists the builds and exposes no mutations.
class BuildsController extends FamilyAsyncNotifier<List<BuildInfo>, BuildsKey> {
  @override
  Future<List<BuildInfo>> build(BuildsKey key) async {
    final gateway = ref.read(coreGatewayProvider);
    final provider =
        await ref.read(connectedProviderProvider(key.accountId).future);

    final builds = gateway.builds(provider);
    if (builds == null) {
      // The provider does not expose builds for this account.
      return const <BuildInfo>[];
    }
    return gateway.fetchBuilds(builds, key.appId);
  }
}

/// The builds controller the UI slice consumes, keyed by (accountId, appId).
final buildsControllerProvider = AsyncNotifierProvider.family<BuildsController,
    List<BuildInfo>, BuildsKey>(BuildsController.new);
