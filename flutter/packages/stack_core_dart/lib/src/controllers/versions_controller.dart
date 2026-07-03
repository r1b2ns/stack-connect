import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gateway/core_gateway.dart';
import 'package:stack_core_rust/stack_core_rust.dart';
import 'connected_provider.dart';

/// The (account, app) key a [VersionsController] is scoped to.
typedef VersionsKey = ({String accountId, String appId});

/// App Store versions for a single (account, app), newest first.
///
/// Loads through the connected provider's App Store Versions handle. This is a
/// read-only slice: it lists the versions and exposes no mutations.
class VersionsController
    extends FamilyAsyncNotifier<List<AppStoreVersionInfo>, VersionsKey> {
  @override
  Future<List<AppStoreVersionInfo>> build(VersionsKey key) async {
    final gateway = ref.read(coreGatewayProvider);
    final provider =
        await ref.read(connectedProviderProvider(key.accountId).future);

    final versions = gateway.appStoreVersions(provider);
    if (versions == null) {
      // The provider does not expose app store versions for this account.
      return const <AppStoreVersionInfo>[];
    }
    return gateway.fetchVersions(versions, key.appId);
  }
}

/// The versions controller the UI slice consumes, keyed by (accountId, appId).
final versionsControllerProvider = AsyncNotifierProvider.family<
    VersionsController,
    List<AppStoreVersionInfo>,
    VersionsKey>(VersionsController.new);
