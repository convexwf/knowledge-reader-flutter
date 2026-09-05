import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_reader/data/local/library_store.dart';
import 'package:knowledge_reader/data/remote/server_client.dart';
import 'package:knowledge_reader/domain/model/document.dart';
import 'package:knowledge_reader/domain/rule/content_hash.dart';
import 'package:path/path.dart' as p;

/// End-to-end smoke test against a locally running knowledge-ingest-server.
///
/// The test skips itself when the server is not reachable, so `flutter test`
/// stays green without Docker; when the server is up it exercises the real
/// client code path: catalog snapshot → package download → integrity check →
/// atomic install → document parse.
void main() {
  const baseUrl = 'http://127.0.0.1:18765';
  const token = 'dev-token';

  test('live server: catalog to installed document', () async {
    final client = ServerClient(config: const ServerConfig(baseUrl: baseUrl, token: token));
    try {
      await client.health();
    } catch (error) {
      markTestSkipped('server is not running on $baseUrl ($error)');
      return;
    }

    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      headers: {'authorization': 'Bearer $token'},
      validateStatus: (status) => status != null && status < 400,
    ));
    final pageUrl = 'https://example.com/reader-smoke-${DateTime.now().millisecondsSinceEpoch}';
    final workspace = await Directory.systemTemp.createTemp('reader-live-');
    var itemId = '';

    try {
      final save = await dio.post<Map<String, dynamic>>('/api/ingest/save', data: {
        'inputMode': 'browser_html',
        'snapshot': {
          'pageUrl': pageUrl,
          'canonicalUrl': pageUrl,
          'pageTitle': 'Reader Smoke Article',
          'title': 'Reader Smoke Article',
          'html': _fixtureHtml,
          'capturedAt': DateTime.now().toUtc().toIso8601String(),
          'meta': {'author': 'Smoke Writer'},
        },
      });
      itemId = '${(save.data?['status'] as Map?)?['itemId']}';
      expect(itemId, startsWith('url:sha256:'));

      final catalog = await client.fetchCatalog();
      final entry = catalog.snapshot!.items.firstWhere((item) => item.itemId == itemId);
      expect(entry.contentHash, isNotNull);
      expect(entry.packageBytes, isNotNull);
      expect(entry.sectionCount, greaterThan(0));
      expect(entry.sourceUrl, pageUrl);
      expect(entry.sourceLabel, 'example.com');

      final store = await LibraryStore.open(
        rootOverride: Directory(p.join(workspace.path, 'support')),
        cacheOverride: Directory(p.join(workspace.path, 'cache')),
      );
      final download = await client.downloadPackage(
        itemId: itemId,
        target: store.tempArchive(itemId),
      );
      expect(download.notModified, isFalse, reason: 'server should return 200 for a fresh etag');
      expect(download.file, isNotNull);
      expect(download.etag, '"${entry.contentHash}"');

      final state = await store.installPackage(itemId: itemId, archiveFile: download.file!);
      expect(state.contentHash, entry.contentHash);

      final document = KnowledgeDocument.fromJson(
        jsonDecode(await store.documentFile(itemId, state.contentHash).readAsString()) as Map<String, dynamic>,
      );
      expect(document.title, 'Reader Smoke Article');
      expect(document.sections, isNotEmpty);
      expect(
        document.sections.any((section) => (section.content ?? '').contains('offline reader smoke fixture')),
        isTrue,
      );

      // The stored bytes must reproduce the catalog fingerprint (contract check).
      final files = <PackageFile>[];
      await for (final entity in store.contentDirectory(itemId, state.contentHash).list(recursive: true)) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: store.contentDirectory(itemId, state.contentHash).path);
        final normalized = relative.replaceAll(Platform.pathSeparator, '/');
        if (normalized == 'manifest.json') continue;
        files.add(PackageFile(path: normalized, bytes: await entity.readAsBytes()));
      }
      expect(packageContentHash(files), entry.contentHash);

      // A second download with the same etag must short-circuit.
      final cached = await client.downloadPackage(
        itemId: itemId,
        target: store.tempArchive(itemId),
        etag: download.etag,
      );
      expect(cached.notModified, isTrue);
    } finally {
      if (itemId.isNotEmpty) {
        await dio.delete<void>(
          '/api/ingest',
          queryParameters: {'url': pageUrl, 'mode': 'purge'},
        );
      }
      await workspace.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('live server: existing library item installs with its assets', () async {
    final client = ServerClient(config: const ServerConfig(baseUrl: baseUrl, token: token));
    try {
      await client.health();
    } catch (error) {
      markTestSkipped('server is not running on $baseUrl ($error)');
      return;
    }

    final catalog = await client.fetchCatalog();
    final items = catalog.snapshot?.items.where((item) => item.isParsed).toList(growable: false) ?? const [];
    if (items.isEmpty) {
      markTestSkipped('server catalog has no parsed item yet');
      return;
    }
    final entry = items.first;

    final workspace = await Directory.systemTemp.createTemp('reader-live-existing-');
    try {
      final store = await LibraryStore.open(
        rootOverride: Directory(p.join(workspace.path, 'support')),
        cacheOverride: Directory(p.join(workspace.path, 'cache')),
      );
      final download = await client.downloadPackage(
        itemId: entry.itemId,
        target: store.tempArchive(entry.itemId),
      );
      expect(download.notModified, isFalse);

      final state = await store.installPackage(itemId: entry.itemId, archiveFile: download.file!);
      expect(state.contentHash, entry.contentHash);
      expect(state.fileCount, greaterThan(1));

      final document = KnowledgeDocument.fromJson(
        jsonDecode(await store.documentFile(entry.itemId, state.contentHash).readAsString()) as Map<String, dynamic>,
      );
      expect(document.sections, isNotEmpty);
      expect(entry.sectionCount, greaterThan(0));

      // Assets referenced by the document must be present locally.
      final assetIds = document.sections
          .expand((section) => section.assets)
          .map((asset) => asset.resolvedAssetId)
          .whereType<String>()
          .take(3)
          .toList(growable: false);
      for (final assetId in assetIds) {
        expect(await store.assetFile(entry.itemId, state.contentHash, assetId).exists(), isTrue);
      }
    } finally {
      await workspace.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

const _fixtureHtml = '''
<!doctype html>
<html lang="en">
  <head>
    <title>Reader Smoke Article</title>
    <meta name="author" content="Smoke Writer">
  </head>
  <body>
    <article>
      <h1>Reader Smoke Article</h1>
      <p>This paragraph exists to prove the offline reader smoke fixture survives the full round trip from the client.</p>
      <p>A second paragraph keeps the parser above its minimum readable length so the fixture is saved as a parsed document.</p>
      <ul><li>First point</li><li>Second point</li></ul>
    </article>
  </body>
</html>
''';
