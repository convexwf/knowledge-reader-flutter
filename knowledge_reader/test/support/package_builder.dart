import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:knowledge_reader/domain/rule/content_hash.dart';
import 'package:path/path.dart' as p;

/// Builds a minimal, valid offline package (manifest + document + markdown) so
/// tests can exercise installation without a server.
Future<File> buildTestPackage(
  Directory directory, {
  required String itemId,
  required String body,
  bool corruptHash = false,
}) async {
  final documentBytes = utf8.encode(jsonEncode({
    'doc_id': 'doc-$itemId',
    'meta': {'title': 'Test Document'},
    'sections': [
      {'type': 'paragraph', 'content': body, 'section_id': 'section-1'}
    ],
  }));
  final markdownBytes = utf8.encode('# Test Document\n\n$body\n');
  final files = [
    PackageFile(path: 'document.json', bytes: documentBytes),
    PackageFile(path: 'markdown.md', bytes: markdownBytes),
  ];
  final contentHash = packageContentHash(files);

  final manifestBytes = utf8.encode(jsonEncode({
    'schemaVersion': 1,
    'itemId': itemId,
    'docId': 'doc-$itemId',
    'contentHash': corruptHash ? '0' * 64 : contentHash,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'sourceType': 'url',
    'title': 'Test Document',
    'documentBytes': documentBytes.length,
    'sections': 1,
    'files': files
        .map((file) => {'path': file.path, 'sha256': sha256Hex(file.bytes), 'size': file.bytes.length})
        .toList(),
    'assets': const [],
    'warnings': const [],
  }));

  final archive = Archive()
    ..addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
  for (final file in files) {
    archive.addFile(ArchiveFile(file.path, file.bytes.length, file.bytes));
  }

  final archiveFile = File(p.join(directory.path, 'package-${DateTime.now().microsecondsSinceEpoch}.zip'));
  await archiveFile.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return archiveFile;
}
