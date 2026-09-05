import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_reader/data/local/package_extractor.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('reader-extract-');
  });

  tearDown(() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  });

  test('accepts package-relative paths and rejects escapes', () {
    expect(PackageExtractor.isSafeEntryPath('document.json'), isTrue);
    expect(PackageExtractor.isSafeEntryPath('assets/a.png'), isTrue);
    expect(PackageExtractor.isSafeEntryPath('../evil.txt'), isFalse);
    expect(PackageExtractor.isSafeEntryPath('assets/../../evil.txt'), isFalse);
    expect(PackageExtractor.isSafeEntryPath('/etc/passwd'), isFalse);
    expect(PackageExtractor.isSafeEntryPath('C:/windows/system32'), isFalse);
    expect(PackageExtractor.isSafeEntryPath('assets//a.png'), isFalse);
    expect(PackageExtractor.isSafeEntryPath(''), isFalse);
  });

  test('extracts a well-formed package', () async {
    final archiveFile = await _writeZip(workspace, {
      'manifest.json': jsonEncode({
        'schemaVersion': 1,
        'itemId': 'url:sha256:abc',
        'docId': 'doc-1',
        'contentHash': 'deadbeef',
        'title': 'Extract Me',
        'files': const [],
      }),
      'document.json': '{"doc_id":"doc-1","sections":[]}',
      'assets/a.png': '',
    });

    final target = Directory(p.join(workspace.path, 'out'));
    final result = await PackageExtractor.extract(archive: archiveFile, target: target);

    expect(result.manifest.docId, 'doc-1');
    expect(result.files..sort(), ['assets/a.png', 'document.json', 'manifest.json']);
    expect(await File(p.join(target.path, 'document.json')).exists(), isTrue);
    expect(await File(p.join(target.path, 'assets', 'a.png')).exists(), isTrue);
  });

  test('refuses archives that try to escape the target directory', () async {
    final archiveFile = await _writeZip(workspace, {'../evil.txt': 'owned'});
    final target = Directory(p.join(workspace.path, 'out'));

    await expectLater(
      PackageExtractor.extract(archive: archiveFile, target: target),
      throwsA(isA<PackageExtractionException>()),
    );
    expect(await File(p.join(workspace.path, 'evil.txt')).exists(), isFalse);
  });

  test('refuses packages without a manifest', () async {
    final archiveFile = await _writeZip(workspace, {'document.json': '{}'});
    await expectLater(
      PackageExtractor.extract(archive: archiveFile, target: Directory(p.join(workspace.path, 'out'))),
      throwsA(isA<PackageExtractionException>()),
    );
  });
}

Future<File> _writeZip(Directory directory, Map<String, String> entries) async {
  final archive = Archive();
  entries.forEach((path, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  });
  final file = File(p.join(directory.path, 'package.zip'));
  await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return file;
}
