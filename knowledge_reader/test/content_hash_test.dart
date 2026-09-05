import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_reader/domain/rule/content_hash.dart';

void main() {
  // Vector produced by the server implementation of the same contract
  // (apps/knowledge-ingest-server/src/package.ts) so both sides stay aligned.
  const serverVector = '660cff05f1896d85c726ed7f762116006697b36268a3f30206f49d1b315c2f4f';

  final entries = <PackageFile>[
    PackageFile(path: 'document.json', bytes: utf8.encode('{"doc_id":"x","sections":[]}')),
    PackageFile(path: 'markdown.md', bytes: utf8.encode('# title\n')),
    PackageFile(path: 'assets/a.png', bytes: const [1, 2, 3, 4]),
  ];

  test('content hash matches the server implementation', () {
    expect(packageContentHash(entries), serverVector);
  });

  test('content hash ignores entry order', () {
    final reversed = entries.reversed.toList(growable: false);
    expect(packageContentHash(reversed), serverVector);
  });

  test('content bytes count uncompressed sizes', () {
    expect(packageContentBytes(entries), 28 + 8 + 4);
  });
}
