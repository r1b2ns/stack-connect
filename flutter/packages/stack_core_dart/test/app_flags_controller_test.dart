import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import 'support/fakes.dart';

String _flagsBlob({
  required String accountId,
  required String appId,
  bool isFavorite = false,
  bool isArchived = false,
}) =>
    jsonEncode({
      'accountId': accountId,
      'appId': appId,
      'isFavorite': isFavorite,
      'isArchived': isArchived,
    });

void main() {
  const accountId = 'acct-1';

  late FakeBlobCache blobs;

  setUp(() {
    blobs = FakeBlobCache();
  });

  ProviderContainer makeContainer({BlobCache? cache}) {
    final container = ProviderContainer(
      overrides: [
        blobCacheProvider.overrideWithValue(cache ?? blobs),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('AppFlagsController.build', () {
    test('decodes existing flag blobs and filters by accountId', () async {
      await blobs.save(
        kAppFlagsBlobType,
        '$accountId.app-1',
        _flagsBlob(accountId: accountId, appId: 'app-1', isFavorite: true),
      );
      await blobs.save(
        kAppFlagsBlobType,
        '$accountId.app-2',
        _flagsBlob(accountId: accountId, appId: 'app-2', isArchived: true),
      );
      // Belongs to a different account — must be filtered out.
      await blobs.save(
        kAppFlagsBlobType,
        'other.app-3',
        _flagsBlob(accountId: 'other', appId: 'app-3', isFavorite: true),
      );

      final container = makeContainer();
      final flags =
          await container.read(appFlagsControllerProvider(accountId).future);

      expect(flags.keys, unorderedEquals(['app-1', 'app-2']));
      expect(flags['app-1'], const AppFlags(isFavorite: true));
      expect(flags['app-2'], const AppFlags(isArchived: true));
    });

    test('tolerates malformed JSON by skipping the row', () async {
      await blobs.save(kAppFlagsBlobType, '$accountId.bad', 'not json {');
      await blobs.save(
        kAppFlagsBlobType,
        '$accountId.app-1',
        _flagsBlob(accountId: accountId, appId: 'app-1', isFavorite: true),
      );

      final container = makeContainer();
      final flags =
          await container.read(appFlagsControllerProvider(accountId).future);

      expect(flags.keys, ['app-1']);
    });

    test('empty cache yields an empty map', () async {
      final container = makeContainer();
      final flags =
          await container.read(appFlagsControllerProvider(accountId).future);
      expect(flags, isEmpty);
    });
  });

  group('AppFlagsController.toggleFavorite / toggleArchive', () {
    test('toggleFavorite persists and emits updated state', () async {
      final container = makeContainer();
      final provider = appFlagsControllerProvider(accountId);
      await container.read(provider.future);

      await container.read(provider.notifier).toggleFavorite('app-1');

      expect(container.read(provider).value!['app-1'],
          const AppFlags(isFavorite: true));
      final persisted = await blobs.fetch(kAppFlagsBlobType, '$accountId.app-1');
      expect(persisted, isNotNull);
      expect(jsonDecode(persisted!), {
        'accountId': accountId,
        'appId': 'app-1',
        'isFavorite': true,
        'isArchived': false,
      });
    });

    test('toggleArchive persists and emits updated state', () async {
      final container = makeContainer();
      final provider = appFlagsControllerProvider(accountId);
      await container.read(provider.future);

      await container.read(provider.notifier).toggleArchive('app-1');

      expect(container.read(provider).value!['app-1'],
          const AppFlags(isArchived: true));
    });

    test('toggling twice returns to the original flag', () async {
      final container = makeContainer();
      final provider = appFlagsControllerProvider(accountId);
      await container.read(provider.future);

      await container.read(provider.notifier).toggleFavorite('app-1');
      await container.read(provider.notifier).toggleFavorite('app-1');

      expect(container.read(provider).value!['app-1'],
          const AppFlags(isFavorite: false));
    });

    test('preserves the other flag when toggling one', () async {
      await blobs.save(
        kAppFlagsBlobType,
        '$accountId.app-1',
        _flagsBlob(accountId: accountId, appId: 'app-1', isFavorite: true),
      );
      final container = makeContainer();
      final provider = appFlagsControllerProvider(accountId);
      await container.read(provider.future);

      await container.read(provider.notifier).toggleArchive('app-1');

      expect(container.read(provider).value!['app-1'],
          const AppFlags(isFavorite: true, isArchived: true));
    });
  });

  group('AppFlagsController revert on save failure', () {
    test('reverts optimistic update and rethrows', () async {
      final throwing = _ThrowingBlobCache();
      final container = makeContainer(cache: throwing);
      final provider = appFlagsControllerProvider(accountId);
      await container.read(provider.future);

      await expectLater(
        container.read(provider.notifier).toggleFavorite('app-1'),
        throwsA(isA<StateError>()),
      );

      // State reverted: no flag for app-1.
      expect(container.read(provider).value, isEmpty);
    });

    test('revert restores the previous flag, not just clears it', () async {
      // Seed an existing favorite for app-1 in a working cache first.
      final throwing = _ThrowingBlobCache();
      await throwing.delegate.save(
        kAppFlagsBlobType,
        '$accountId.app-1',
        _flagsBlob(accountId: accountId, appId: 'app-1', isFavorite: true),
      );
      final container = makeContainer(cache: throwing);
      final provider = appFlagsControllerProvider(accountId);
      await container.read(provider.future);

      throwing.failSaves = true;
      await expectLater(
        container.read(provider.notifier).toggleArchive('app-1'),
        throwsA(isA<StateError>()),
      );

      // Reverted to the pre-toggle favorite-only state.
      expect(container.read(provider).value!['app-1'],
          const AppFlags(isFavorite: true));
    });
  });
}

/// [BlobCache] whose `save` throws (optionally gated by [failSaves]).
///
/// Reads delegate to an in-memory [FakeBlobCache] so `build` can still seed
/// state before a save is exercised.
class _ThrowingBlobCache implements BlobCache {
  final FakeBlobCache delegate = FakeBlobCache();
  bool failSaves = true;

  @override
  Future<void> save(String typeName, String id, String json) async {
    if (failSaves) throw StateError('save failed');
    await delegate.save(typeName, id, json);
  }

  @override
  Future<String?> fetch(String typeName, String id) =>
      delegate.fetch(typeName, id);

  @override
  Future<List<CachedBlob>> fetchAll(String typeName) =>
      delegate.fetchAll(typeName);

  @override
  Future<void> delete(String typeName, String id) =>
      delegate.delete(typeName, id);
}
