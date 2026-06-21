import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rust/domain.dart';
// Prefixed: avoids the name clash between the top-level `availableServices`
// binding function and the [CoreGateway.availableServices] method.
import '../rust/frb_api.dart' as frb;
import '../rust/frb_api.dart'
    show
        FrbAppStoreVersions,
        FrbBetaGroups,
        FrbBuilds,
        FrbCredential,
        FrbProvider,
        FrbReviews,
        FrbSyncService;
import '../rust/service/kind.dart';

/// A no-op debug-log sink.
///
/// FRB 2.12 cannot express `Option<DartFn>`, so [CoreGateway.connect] requires a
/// callback. Normal use passes this sink together with `debugLogging: false` so
/// the core never logs (mirroring the UniFFI `debug_logger: None` release path).
FutureOr<void> _noopDebugLogger(String _) {}

/// The single seam between the controllers and the generated flutter_rust_bridge
/// API.
///
/// Controllers MUST depend on [CoreGateway] and never call `frb_api` functions
/// directly. That indirection is what makes the controllers unit-testable: tests
/// mock [CoreGateway] (with mocktail) so no dylib is loaded and no network is
/// hit. The real implementation, [FrbCoreGateway], is the only place that
/// touches the binding.
abstract interface class CoreGateway {
  /// The services the core can connect today (sync in the core).
  List<ServiceKind> availableServices();

  /// The credential form to render for [kind] (sync in the core).
  List<CredentialField> credentialSchema(ServiceKind kind);

  /// Connects an account and returns a live provider handle.
  ///
  /// [credentials] are the already-resolved secrets the host read back from its
  /// secure store. Debug logging is off by default.
  Future<FrbProvider> connect({
    required ServiceKind kind,
    required String accountId,
    required List<FrbCredential> credentials,
    bool debugLogging,
    FutureOr<void> Function(String) debugLogger,
  });

  /// Verifies a provider's credentials against the live service.
  Future<void> validate(FrbProvider provider);

  /// Lists the apps visible to the connected account.
  Future<List<AppInfo>> fetchApps(FrbProvider provider);

  /// The provider's Reviews handle, or `null` when unsupported.
  FrbReviews? reviews(FrbProvider provider);

  /// All customer reviews for [appId], newest first.
  Future<List<CustomerReview>> fetchCustomerReviews(
    FrbReviews reviews,
    String appId,
  );

  /// Upserts the developer response for [reviewId].
  Future<ReviewResponse> replyToReview(
    FrbReviews reviews, {
    required String reviewId,
    required String body,
  });

  /// The provider's Builds handle, or `null` when unsupported.
  FrbBuilds? builds(FrbProvider provider);

  /// All TestFlight / App Store Connect builds for [appId], newest first.
  Future<List<BuildInfo>> fetchBuilds(FrbBuilds builds, String appId);

  /// The provider's App Store Versions handle, or `null` when unsupported.
  FrbAppStoreVersions? appStoreVersions(FrbProvider provider);

  /// All App Store versions for [appId], newest first.
  Future<List<AppStoreVersionInfo>> fetchVersions(
    FrbAppStoreVersions versions,
    String appId,
  );

  /// The provider's Beta Groups handle, or `null` when unsupported.
  FrbBetaGroups? betaGroups(FrbProvider provider);

  /// All TestFlight beta groups for [appId].
  Future<List<BetaGroupInfo>> fetchBetaGroups(
    FrbBetaGroups groups,
    String appId,
  );

  /// Builds a sync service for [provider] and [accountId].
  FrbSyncService makeSyncService(FrbProvider provider, String accountId);

  /// Runs an apps sync, persisting each buffered blob through [persist], and
  /// returns the fetched apps.
  Future<List<AppInfo>> syncApps(
    FrbSyncService service, {
    required FutureOr<void> Function(String typeName, String id, String json)
        persist,
  });
}

/// The real [CoreGateway]: a thin adapter over the generated `frb_api`.
///
/// Stateless — every method forwards straight to the binding.
class FrbCoreGateway implements CoreGateway {
  const FrbCoreGateway();

  @override
  List<ServiceKind> availableServices() => frb.availableServices();

  @override
  List<CredentialField> credentialSchema(ServiceKind kind) =>
      frb.credentialSchema(kind: kind);

  @override
  Future<FrbProvider> connect({
    required ServiceKind kind,
    required String accountId,
    required List<FrbCredential> credentials,
    bool debugLogging = false,
    FutureOr<void> Function(String) debugLogger = _noopDebugLogger,
  }) =>
      frb.connect(
        kind: kind,
        accountId: accountId,
        credentials: credentials,
        debugLogging: debugLogging,
        debugLogger: debugLogger,
      );

  @override
  Future<void> validate(FrbProvider provider) => provider.validate();

  @override
  Future<List<AppInfo>> fetchApps(FrbProvider provider) => provider.fetchApps();

  @override
  FrbReviews? reviews(FrbProvider provider) => provider.reviews();

  @override
  Future<List<CustomerReview>> fetchCustomerReviews(
    FrbReviews reviews,
    String appId,
  ) =>
      reviews.fetchCustomerReviews(appId: appId);

  @override
  Future<ReviewResponse> replyToReview(
    FrbReviews reviews, {
    required String reviewId,
    required String body,
  }) =>
      reviews.replyToReview(reviewId: reviewId, body: body);

  @override
  FrbBuilds? builds(FrbProvider provider) => provider.builds();

  @override
  Future<List<BuildInfo>> fetchBuilds(FrbBuilds builds, String appId) =>
      builds.fetchBuilds(appId: appId, limit: 200);

  @override
  FrbAppStoreVersions? appStoreVersions(FrbProvider provider) =>
      provider.appStoreVersions();

  @override
  Future<List<AppStoreVersionInfo>> fetchVersions(
    FrbAppStoreVersions versions,
    String appId,
  ) =>
      versions.fetchVersions(appId: appId, limit: 200);

  @override
  FrbBetaGroups? betaGroups(FrbProvider provider) => provider.betaGroups();

  @override
  Future<List<BetaGroupInfo>> fetchBetaGroups(
    FrbBetaGroups groups,
    String appId,
  ) =>
      groups.fetchBetaGroups(appId: appId, limit: 200);

  @override
  FrbSyncService makeSyncService(FrbProvider provider, String accountId) =>
      frb.makeSyncService(provider: provider, accountId: accountId);

  @override
  Future<List<AppInfo>> syncApps(
    FrbSyncService service, {
    required FutureOr<void> Function(String typeName, String id, String json)
        persist,
  }) =>
      service.syncApps(persist: persist);
}

/// The [CoreGateway] controllers depend on.
///
/// Override this in a `ProviderContainer` (tests) or `ProviderScope` (apps) to
/// inject a mock or an alternative implementation.
final coreGatewayProvider = Provider<CoreGateway>(
  (ref) => const FrbCoreGateway(),
);
