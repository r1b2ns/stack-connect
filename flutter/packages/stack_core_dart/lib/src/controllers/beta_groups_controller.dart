import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gateway/core_gateway.dart';
import 'package:stack_core_rust/stack_core_rust.dart';
import 'connected_provider.dart';

/// The (account, app) key a [BetaGroupsController] is scoped to.
typedef BetaGroupsKey = ({String accountId, String appId});

/// TestFlight beta groups for a single (account, app).
///
/// Loads through the connected provider's Beta Groups handle. This is a
/// read-only slice: it lists the groups and exposes no mutations.
class BetaGroupsController
    extends FamilyAsyncNotifier<List<BetaGroupInfo>, BetaGroupsKey> {
  @override
  Future<List<BetaGroupInfo>> build(BetaGroupsKey key) async {
    final gateway = ref.read(coreGatewayProvider);
    final provider =
        await ref.read(connectedProviderProvider(key.accountId).future);

    final groups = gateway.betaGroups(provider);
    if (groups == null) {
      // The provider does not expose beta groups for this account.
      return const <BetaGroupInfo>[];
    }
    return gateway.fetchBetaGroups(groups, key.appId);
  }
}

/// The beta groups controller the UI slice consumes, keyed by
/// (accountId, appId).
final betaGroupsControllerProvider = AsyncNotifierProvider.family<
    BetaGroupsController,
    List<BetaGroupInfo>,
    BetaGroupsKey>(BetaGroupsController.new);
