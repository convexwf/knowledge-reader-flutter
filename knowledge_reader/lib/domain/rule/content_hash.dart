import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A single file inside an offline package.
class PackageFile {
  const PackageFile({required this.path, required this.bytes});

  final String path;
  final List<int> bytes;
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Content hash defined by the offline package contract.
///
/// Entries are sorted by path, each file is hashed, and the resulting
/// `"<path>\0<sha256>\n"` manifest string is hashed again. `manifest.json` never
/// participates, so the hash can be computed before the manifest exists.
String packageContentHash(List<PackageFile> files) {
  final sorted = [...files]..sort((left, right) => left.path.compareTo(right.path));
  final manifest = sorted
      .map((file) => '${file.path}\u0000${sha256Hex(file.bytes)}\n')
      .join();
  return sha256Hex(utf8.encode(manifest));
}

int packageContentBytes(List<PackageFile> files) =>
    files.fold(0, (total, file) => total + file.bytes.length);
