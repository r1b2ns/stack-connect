import 'dart:async';
import 'dart:typed_data';

import 'package:mocktail/mocktail.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

/// In-memory [AccountsStore] preserving insertion order.
class FakeAccountsStore implements AccountsStore {
  final List<AccountRecord> _records = [];

  @override
  Future<List<AccountRecord>> all() async => List.unmodifiable(_records);

  @override
  Future<void> upsert(AccountRecord account) async {
    _records.removeWhere((r) => r.id == account.id);
    _records.add(account);
  }

  @override
  Future<void> remove(String id) async {
    _records.removeWhere((r) => r.id == id);
  }
}

/// In-memory [BlobCache] keyed by (typeName, id), insertion-ordered.
class FakeBlobCache implements BlobCache {
  final List<CachedBlob> _blobs = [];

  @override
  Future<void> save(String typeName, String id, String json) async {
    _blobs.removeWhere((b) => b.typeName == typeName && b.id == id);
    _blobs.add(CachedBlob(typeName: typeName, id: id, json: json));
  }

  @override
  Future<String?> fetch(String typeName, String id) async {
    for (final b in _blobs) {
      if (b.typeName == typeName && b.id == id) return b.json;
    }
    return null;
  }

  @override
  Future<List<CachedBlob>> fetchAll(String typeName) async =>
      _blobs.where((b) => b.typeName == typeName).toList(growable: false);

  @override
  Future<void> delete(String typeName, String id) async {
    _blobs.removeWhere((b) => b.typeName == typeName && b.id == id);
  }
}

/// In-memory [SecretStore].
class FakeSecretStore implements SecretStore {
  final Map<String, Map<String, String>> _store = {};

  @override
  Future<void> setSecret(String accountId, String key, String value) async {
    (_store[accountId] ??= {})[key] = value;
  }

  @override
  Future<String?> secret(String accountId, String key) async =>
      _store[accountId]?[key];

  @override
  Future<void> deleteAccount(String accountId) async {
    _store.remove(accountId);
  }
}

/// A [CoreGateway] fake that loads no dylib and hits no network.
///
/// Only [credentialSchema] returns useful data (so the add-account form renders
/// in tests); the live operations are not exercised by the smoke test and throw
/// if called.
class FakeCoreGateway implements CoreGateway {
  const FakeCoreGateway();

  @override
  List<ServiceKind> availableServices() => const [ServiceKind.appStoreConnect];

  @override
  List<CredentialField> credentialSchema(ServiceKind kind) => const [
        CredentialField(
          key: 'keyId',
          label: 'Key ID',
          secret: false,
          multiline: false,
        ),
        CredentialField(
          key: 'issuerId',
          label: 'Issuer ID',
          secret: false,
          multiline: false,
        ),
        CredentialField(
          key: 'privateKey',
          label: 'Private key (.p8)',
          secret: true,
          multiline: true,
        ),
      ];

  @override
  Future<FrbProvider> connect({
    required ServiceKind kind,
    required String accountId,
    required List<FrbCredential> credentials,
    bool debugLogging = false,
    FutureOr<void> Function(String) debugLogger = _noop,
  }) =>
      throw UnimplementedError('connect not used in smoke test');

  @override
  Future<void> validate(FrbProvider provider) =>
      throw UnimplementedError('validate not used in smoke test');

  @override
  Future<List<AppInfo>> fetchApps(FrbProvider provider) =>
      throw UnimplementedError('fetchApps not used in smoke test');

  @override
  FrbReviews? reviews(FrbProvider provider) => null;

  @override
  Future<List<CustomerReview>> fetchCustomerReviews(
    FrbReviews reviews,
    String appId,
  ) =>
      throw UnimplementedError('fetchCustomerReviews not used in smoke test');

  @override
  Future<ReviewResponse> replyToReview(
    FrbReviews reviews, {
    required String reviewId,
    required String body,
  }) =>
      throw UnimplementedError('replyToReview not used in smoke test');

  @override
  FrbBuilds? builds(FrbProvider provider) => null;

  @override
  Future<List<BuildInfo>> fetchBuilds(FrbBuilds builds, String appId) =>
      throw UnimplementedError('fetchBuilds not used in smoke test');

  @override
  FrbAppStoreVersions? appStoreVersions(FrbProvider provider) => null;

  @override
  Future<List<AppStoreVersionInfo>> fetchVersions(
    FrbAppStoreVersions versions,
    String appId,
  ) =>
      throw UnimplementedError('fetchVersions not used in smoke test');

  @override
  FrbBetaGroups? betaGroups(FrbProvider provider) => null;

  @override
  Future<List<BetaGroupInfo>> fetchBetaGroups(
    FrbBetaGroups groups,
    String appId,
  ) =>
      throw UnimplementedError('fetchBetaGroups not used in smoke test');

  @override
  FrbSyncService makeSyncService(FrbProvider provider, String accountId) =>
      throw UnimplementedError('makeSyncService not used in smoke test');

  @override
  Future<List<AppInfo>> syncApps(
    FrbSyncService service, {
    required FutureOr<void> Function(String typeName, String id, String json)
        persist,
  }) =>
      throw UnimplementedError('syncApps not used in smoke test');

  @override
  AccountExport decryptScexport({
    required List<int> bytes,
    required String password,
  }) =>
      throw UnimplementedError('decryptScexport not used in smoke test');

  @override
  Uint8List encryptScexport({
    required AccountExport account,
    required String password,
  }) =>
      throw UnimplementedError('encryptScexport not used in smoke test');
}

FutureOr<void> _noop(String _) {}

/// Opaque FRB sentinels. The configurable gateway hands these back to the
/// controllers, which only pass them around (never introspect them), so a bare
/// mocktail mock is a sufficient stand-in for the real Rust-opaque handles.
class _FakeFrbProvider extends Mock implements FrbProvider {}

class _FakeFrbReviews extends Mock implements FrbReviews {}

class _FakeFrbBuilds extends Mock implements FrbBuilds {}

class _FakeFrbAppStoreVersions extends Mock implements FrbAppStoreVersions {}

class _FakeFrbBetaGroups extends Mock implements FrbBetaGroups {}

class _FakeFrbSyncService extends Mock implements FrbSyncService {}

/// A fully scriptable [CoreGateway] for widget/integration tests.
///
/// Unlike [FakeCoreGateway] (which only renders the credential schema and throws
/// on every live call), this drives the whole app with canned data and no
/// dylib/network:
///   * [connectError] / [validateError] let the add-account flow exercise the
///     `StackError` mapping and the "nothing persisted" guarantee.
///   * [appsToSync] is what `syncApps` returns (and persists into the cache).
///   * [reviewsByApp] seeds the reviews list; [replyToReview] records each reply
///     and mutates the seeded review so the re-fetch shows the developer
///     response (mirroring the real invalidate-and-refetch behaviour).
class ConfigurableFakeCoreGateway implements CoreGateway {
  ConfigurableFakeCoreGateway({
    this.connectError,
    this.validateError,
    this.decryptResult,
    this.decryptError,
    this.encryptResult,
    this.encryptError,
    List<AppInfo>? appsToSync,
    Map<String, List<CustomerReview>>? reviewsByApp,
    Map<String, List<BuildInfo>>? buildsByApp,
    Map<String, List<AppStoreVersionInfo>>? versionsByApp,
    Map<String, List<BetaGroupInfo>>? betaGroupsByApp,
    this.exposesReviews = true,
    this.exposesBuilds = true,
    this.exposesVersions = true,
    this.exposesBetaGroups = true,
  })  : appsToSync = appsToSync ?? const [],
        _reviewsByApp = {
          for (final entry in (reviewsByApp ?? const {}).entries)
            entry.key: List<CustomerReview>.of(entry.value),
        },
        _buildsByApp = {
          for (final entry in (buildsByApp ?? const {}).entries)
            entry.key: List<BuildInfo>.of(entry.value),
        },
        _versionsByApp = {
          for (final entry in (versionsByApp ?? const {}).entries)
            entry.key: List<AppStoreVersionInfo>.of(entry.value),
        },
        _betaGroupsByApp = {
          for (final entry in (betaGroupsByApp ?? const {}).entries)
            entry.key: List<BetaGroupInfo>.of(entry.value),
        };

  /// Thrown from [connect] when non-null (e.g. `StackError.auth`).
  final Object? connectError;

  /// Thrown from [validate] when non-null (e.g. `StackError.pendingAgreements`).
  final Object? validateError;

  /// Returned from [decryptScexport] when non-null (drives the import flow).
  final AccountExport? decryptResult;

  /// Thrown from [decryptScexport] when non-null (e.g. `StackError.auth` for a
  /// wrong password). Takes precedence over [decryptResult].
  final Object? decryptError;

  /// Returned from [encryptScexport] when non-null (drives the export flow).
  final Uint8List? encryptResult;

  /// Thrown from [encryptScexport] when non-null. Takes precedence over
  /// [encryptResult].
  final Object? encryptError;

  /// Apps returned (and persisted) by [syncApps].
  final List<AppInfo> appsToSync;

  /// Whether the provider exposes a reviews handle.
  final bool exposesReviews;

  /// Whether the provider exposes a builds handle.
  final bool exposesBuilds;

  /// Whether the provider exposes an app store versions handle.
  final bool exposesVersions;

  /// Whether the provider exposes a beta groups handle.
  final bool exposesBetaGroups;

  final Map<String, List<CustomerReview>> _reviewsByApp;

  final Map<String, List<BuildInfo>> _buildsByApp;

  final Map<String, List<AppStoreVersionInfo>> _versionsByApp;

  final Map<String, List<BetaGroupInfo>> _betaGroupsByApp;

  /// Records of every [replyToReview] call, in order, for assertions.
  final List<({String reviewId, String body})> replyCalls = [];

  static final _provider = _FakeFrbProvider();
  static final _reviews = _FakeFrbReviews();
  static final _builds = _FakeFrbBuilds();
  static final _versions = _FakeFrbAppStoreVersions();
  static final _betaGroups = _FakeFrbBetaGroups();
  static final _syncService = _FakeFrbSyncService();

  @override
  List<ServiceKind> availableServices() => const [ServiceKind.appStoreConnect];

  @override
  List<CredentialField> credentialSchema(ServiceKind kind) => const [
        CredentialField(
          key: 'keyId',
          label: 'Key ID',
          secret: false,
          multiline: false,
        ),
        CredentialField(
          key: 'issuerId',
          label: 'Issuer ID',
          secret: false,
          multiline: false,
        ),
        CredentialField(
          key: 'privateKey',
          label: 'Private key (.p8)',
          secret: true,
          multiline: true,
        ),
      ];

  @override
  Future<FrbProvider> connect({
    required ServiceKind kind,
    required String accountId,
    required List<FrbCredential> credentials,
    bool debugLogging = false,
    FutureOr<void> Function(String) debugLogger = _noop,
  }) async {
    if (connectError != null) throw connectError!;
    return _provider;
  }

  @override
  Future<void> validate(FrbProvider provider) async {
    if (validateError != null) throw validateError!;
  }

  @override
  Future<List<AppInfo>> fetchApps(FrbProvider provider) async => appsToSync;

  @override
  FrbReviews? reviews(FrbProvider provider) => exposesReviews ? _reviews : null;

  @override
  Future<List<CustomerReview>> fetchCustomerReviews(
    FrbReviews reviews,
    String appId,
  ) async =>
      List.unmodifiable(_reviewsByApp[appId] ?? const []);

  @override
  Future<ReviewResponse> replyToReview(
    FrbReviews reviews, {
    required String reviewId,
    required String body,
  }) async {
    replyCalls.add((reviewId: reviewId, body: body));
    final response = ReviewResponse(
      id: 'resp-$reviewId',
      body: body,
      state: 'PUBLISHED',
    );
    // Mirror the real backend: attach the response so the re-fetch shows it.
    for (final entry in _reviewsByApp.entries) {
      final list = entry.value;
      for (var i = 0; i < list.length; i++) {
        final review = list[i];
        if (review.id == reviewId) {
          list[i] = CustomerReview(
            id: review.id,
            rating: review.rating,
            title: review.title,
            body: review.body,
            reviewerNickname: review.reviewerNickname,
            createdDate: review.createdDate,
            territory: review.territory,
            response: response,
          );
        }
      }
    }
    return response;
  }

  @override
  FrbBuilds? builds(FrbProvider provider) => exposesBuilds ? _builds : null;

  @override
  Future<List<BuildInfo>> fetchBuilds(FrbBuilds builds, String appId) async =>
      List.unmodifiable(_buildsByApp[appId] ?? const []);

  @override
  FrbAppStoreVersions? appStoreVersions(FrbProvider provider) =>
      exposesVersions ? _versions : null;

  @override
  Future<List<AppStoreVersionInfo>> fetchVersions(
    FrbAppStoreVersions versions,
    String appId,
  ) async =>
      List.unmodifiable(_versionsByApp[appId] ?? const []);

  @override
  FrbBetaGroups? betaGroups(FrbProvider provider) =>
      exposesBetaGroups ? _betaGroups : null;

  @override
  Future<List<BetaGroupInfo>> fetchBetaGroups(
    FrbBetaGroups groups,
    String appId,
  ) async =>
      List.unmodifiable(_betaGroupsByApp[appId] ?? const []);

  @override
  FrbSyncService makeSyncService(FrbProvider provider, String accountId) {
    _currentAccountId = accountId;
    return _syncService;
  }

  @override
  Future<List<AppInfo>> syncApps(
    FrbSyncService service, {
    required FutureOr<void> Function(String typeName, String id, String json)
        persist,
  }) async {
    for (final app in appsToSync) {
      // Persist in the same JSON shape AppsController._decodeAppBlob expects;
      // accountId is carried so cross-account cache filtering works.
      final json = '{"id":"${app.id}","name":"${app.name}",'
          '"bundleId":"${app.bundleId}",'
          '"platform":${app.platform == null ? 'null' : '"${app.platform}"'},'
          '"accountId":"${_currentAccountId ?? ''}"}';
      await persist(kAppBlobType, app.id, json);
    }
    return appsToSync;
  }

  @override
  AccountExport decryptScexport({
    required List<int> bytes,
    required String password,
  }) {
    if (decryptError != null) throw decryptError!;
    if (decryptResult != null) return decryptResult!;
    throw UnimplementedError('decryptScexport not configured');
  }

  @override
  Uint8List encryptScexport({
    required AccountExport account,
    required String password,
  }) {
    if (encryptError != null) throw encryptError!;
    if (encryptResult != null) return encryptResult!;
    throw UnimplementedError('encryptScexport not configured');
  }

  /// The accountId most recently passed to [makeSyncService], used to stamp the
  /// persisted blob so [AppsController] reads it back for the right account.
  String? _currentAccountId;
}
