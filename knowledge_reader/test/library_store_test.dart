import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_reader/data/local/library_store.dart';
import 'package:knowledge_reader/domain/rule/content_hash.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory workspace;
  late LibraryStore store;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('reader-library-');
    store = await LibraryStore.open(
      rootOverride: Directory(p.join(workspace.path, 'support')),
      cacheOverride: Directory(p.join(workspace.path, 'cache')),
    );
  });

  tearDown(() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  });

  test('installs a package and switches the version pointer', () async {
    final archive = await _buildPackage(workspace, itemId: _itemId, body: 'first version');
    final state = await store.installPackage(itemId: _itemId, archiveFile: archive);

    expect(state.contentHash, isNotEmpty);
    expect(await store.documentFile(_itemId, state.contentHash).exists(), isTrue);
    expect(await archive.exists(), isFalse, reason: 'downloaded archive should be removed');

    final library = await store.readLibrary();
    expect(library[_itemId]?.contentHash, state.contentHash);
  });

  test('keeps only the active version after an update', () async {
    final first = await _buildPackage(workspace, itemId: _itemId, body: 'first version');
    final firstState = await store.installPackage(itemId: _itemId, archiveFile: first);

    final second = await _buildPackage(workspace, itemId: _itemId, body: 'second version');
    final secondState = await store.installPackage(itemId: _itemId, archiveFile: second);

    expect(secondState.contentHash, isNot(firstState.contentHash));
    expect(await store.contentDirectory(_itemId, firstState.contentHash).exists(), isFalse);
    expect(await store.contentDirectory(_itemId, secondState.contentHash).exists(), isTrue);
  });

  test('rejects a package whose content hash does not match', () async {
    final archive = await _buildPackage(workspace, itemId: _itemId, body: 'tampered', corruptHash: true);
    await expectLater(
      store.installPackage(itemId: _itemId, archiveFile: archive),
      throwsA(isA<Exception>()),
    );
    expect(await store.readLibrary(), isEmpty);
  });

  test('persists reading progress', () async {
    await store.writeProgress(ReadingProgress(
      itemId: _itemId,
      sectionId: 'section-3',
      offset: 0.25,
      updatedAt: DateTime.now().toUtc(),
    ));
    final progress = await store.readProgress();
    expect(progress[_itemId]?.sectionId, 'section-3');
    expect(progress[_itemId]?.offset, 0.25);
  });
}

const _itemId = 'url:sha256:reader-test';

Future<File> _buildPackage(
  Directory directory, {
  required String itemId,
  required String body,
  bool corruptHash = false,
}) async {
  final documentBytes = utf8.encode(jsonEncode({
    'doc_id': 'doc-reader-test',
    'meta': {'title': 'Reader Test'},
    'sections': [
      {'type': 'paragraph', 'content': body, 'section_id': 'section-1'}
    ],
  }));
  final markdownBytes = utf8.encode('# Reader Test\n\n$body\n');
  final files = [
    PackageFile(path: 'document.json', bytes: documentBytes),
    PackageFile(path: 'markdown.md', bytes: markdownBytes),
  ];
  final contentHash = packageContentHash(files);

  final manifest = jsonEncode({
    'schemaVersion': 1,
    'itemId': itemId,
    'docId': 'doc-reader-test',
    'contentHash': corruptHash ? '0' * 64 : contentHash,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'sourceType': 'url',
    'title': 'Reader Test',
    'documentBytes': documentBytes.length,
    'sections': 1,
    'files': files
        .map((file) => {'path': file.path, 'sha256': sha256Hex(file.bytes), 'size': file.bytes.length})
        .toList(),
    'assets': const [],
    'warnings': const [],
  });
  final manifestBytes = utf8.encode(manifest);

  final archive = Archive()
    ..addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
  for (final file in files) {
    archive.addFile(ArchiveFile(file.path, file.bytes.length, file.bytes));
  }

  final archiveFile = File(p.join(directory.path, 'package-${DateTime.now().microsecondsSinceEpoch}.zip'));
  await archiveFile.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return archiveFile;
}
