import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_reader/application/providers.dart';
import 'package:knowledge_reader/data/local/library_store.dart';
import 'package:knowledge_reader/data/remote/server_client.dart';
import 'package:knowledge_reader/domain/model/catalog.dart';
import 'package:path/path.dart' as p;

import 'support/package_builder.dart';

/// Catalog sync reconciles local packages against the server snapshot.
/// These tests pin the safety rule: only a *fresh* snapshot may delete content,
/// an offline fallback to the cached catalog must never remove anything.
void main() {
  late Directory workspace;
  late LibraryStore store;
  final now = DateTime.utc(2026, 9, 13);

  CatalogSnapshot snapshotWith(List<String> itemIds) => CatalogSnapshot(
        schemaVersion: 1,
        serverTime: now,
        items: [
          for (final itemId in itemIds)
            CatalogItem(
              itemId: itemId,
              title: itemId,
              sourceType: 'url',
              state: 'parsed',
              updatedAt: now,
              contentHash: 'hash-$itemId',
            ),
        ],
      );

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('reader-reconcile-');
    store = await LibraryStore.open(
      rootOverride: Directory(p.join(workspace.path, 'support')),
      cacheOverride: Directory(p.join(workspace.path, 'cache')),
    );
    for (final itemId in const ['url:sha256:kept', 'url:sha256:orphan']) {
      final archive = await buildTestPackage(workspace, itemId: itemId, body: 'body of $itemId');
      await store.installPackage(itemId: itemId, archiveFile: archive);
    }
  });

  tearDown(() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  });

  ProviderContainer containerWith(ServerClient client) {
    final container = ProviderContainer(overrides: [
      libraryStoreProvider.overrideWith((ref) async => store),
      serverClientProvider.overrideWithValue(client),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('a fresh snapshot removes packages the server no longer lists', () async {
    final container = containerWith(_FakeClient(
      result: CatalogFetchResult(snapshot: snapshotWith(['url:sha256:kept']), etag: '"etag"'),
    ));

    final state = await container.read(catalogProvider.future);

    expect(state.fromNetwork, isTrue);
    expect(state.prunedCount, 1);
    expect((await store.readLibrary()).keys, ['url:sha256:kept']);
    expect(await store.itemDirectory('url:sha256:orphan').exists(), isFalse);
  });

  test('an offline fallback to the cached catalog deletes nothing', () async {
    // The cached snapshot already lacks the orphan, but because the request
    // failed the client must leave the local copy alone.
    await store.writeCatalog(snapshotWith(['url:sha256:kept']));
    final container = containerWith(_FakeClient(error: ServerException('无法连接到服务器')));

    final state = await container.read(catalogProvider.future);

    expect(state.fromNetwork, isFalse);
    expect(state.prunedCount, 0);
    expect((await store.readLibrary()).keys.toSet(), {'url:sha256:kept', 'url:sha256:orphan'});
    expect(await store.itemDirectory('url:sha256:orphan').exists(), isTrue);
  });
}

class _FakeClient extends ServerClient {
  _FakeClient({this.result, this.error})
      : super(config: const ServerConfig(baseUrl: 'http://server.test', token: 'token'));

  final CatalogFetchResult? result;
  final ServerException? error;

  @override
  Future<CatalogFetchResult> fetchCatalog({String? etag}) async {
    if (error != null) throw error!;
    return result!;
  }
}
