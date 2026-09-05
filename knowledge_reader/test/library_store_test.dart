import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_reader/data/local/library_store.dart';
import 'package:path/path.dart' as p;

import 'support/package_builder.dart';

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
    final archive = await buildTestPackage(workspace, itemId: _itemId, body: 'first version');
    final state = await store.installPackage(itemId: _itemId, archiveFile: archive);

    expect(state.contentHash, isNotEmpty);
    expect(await store.documentFile(_itemId, state.contentHash).exists(), isTrue);
    expect(await archive.exists(), isFalse, reason: 'downloaded archive should be removed');

    final library = await store.readLibrary();
    expect(library[_itemId]?.contentHash, state.contentHash);
  });

  test('keeps only the active version after an update', () async {
    final first = await buildTestPackage(workspace, itemId: _itemId, body: 'first version');
    final firstState = await store.installPackage(itemId: _itemId, archiveFile: first);

    final second = await buildTestPackage(workspace, itemId: _itemId, body: 'second version');
    final secondState = await store.installPackage(itemId: _itemId, archiveFile: second);

    expect(secondState.contentHash, isNot(firstState.contentHash));
    expect(await store.contentDirectory(_itemId, firstState.contentHash).exists(), isFalse);
    expect(await store.contentDirectory(_itemId, secondState.contentHash).exists(), isTrue);
  });

  test('rejects a package whose content hash does not match', () async {
    final archive = await buildTestPackage(workspace, itemId: _itemId, body: 'tampered', corruptHash: true);
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

  test('pruneMissing drops packages and progress that left the catalog', () async {
    final kept = await buildTestPackage(workspace, itemId: _itemId, body: 'kept');
    final dropped = await buildTestPackage(workspace, itemId: _otherItemId, body: 'dropped');
    final keptState = await store.installPackage(itemId: _itemId, archiveFile: kept);
    final droppedState = await store.installPackage(itemId: _otherItemId, archiveFile: dropped);
    await store.writeProgress(ReadingProgress(
      itemId: _otherItemId,
      sectionId: 'section-1',
      offset: 0.3,
      updatedAt: DateTime.now().toUtc(),
    ));

    final removed = await store.pruneMissing({_itemId});

    expect(removed, [_otherItemId]);
    expect(await store.contentDirectory(_otherItemId, droppedState.contentHash).exists(), isFalse);
    expect(await store.contentDirectory(_itemId, keptState.contentHash).exists(), isTrue);
    expect((await store.readLibrary()).keys, [_itemId]);
    expect((await store.readProgress()).containsKey(_otherItemId), isFalse);
  });

  test('pruneMissing keeps everything when the catalog still lists the item', () async {
    final archive = await buildTestPackage(workspace, itemId: _itemId, body: 'kept');
    await store.installPackage(itemId: _itemId, archiveFile: archive);

    expect(await store.pruneMissing({_itemId}), isEmpty);
    expect((await store.readLibrary()).containsKey(_itemId), isTrue);
  });
}

const _itemId = 'url:sha256:reader-test';
const _otherItemId = 'epub:sha256:reader-orphan';

