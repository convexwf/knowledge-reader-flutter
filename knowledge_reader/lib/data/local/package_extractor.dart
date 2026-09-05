import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../../domain/model/catalog.dart';

class PackageExtractionException implements Exception {
  PackageExtractionException(this.message);

  final String message;

  @override
  String toString() => 'PackageExtractionException: $message';
}

class PackageExtractionResult {
  const PackageExtractionResult({required this.manifest, required this.files});

  final PackageManifest manifest;
  final List<String> files;
}

/// Extracts a server-built offline package with path traversal protection.
class PackageExtractor {
  /// Rejects absolute paths, drive letters, empty segments and `..` escapes.
  static bool isSafeEntryPath(String path) {
    if (path.isEmpty) return false;
    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('/')) return false;
    if (RegExp(r'^[A-Za-z]:').hasMatch(normalized)) return false;
    for (final segment in normalized.split('/')) {
      if (segment.isEmpty || segment == '.' || segment == '..') return false;
    }
    return true;
  }

  static Future<PackageExtractionResult> extract({
    required File archive,
    required Directory target,
  }) async {
    final Archive decoded;
    try {
      decoded = ZipDecoder().decodeBytes(await archive.readAsBytes());
    } catch (error) {
      throw PackageExtractionException('invalid zip archive: $error');
    }

    await target.create(recursive: true);
    final files = <String>[];
    PackageManifest? manifest;

    for (final entry in decoded.files) {
      if (entry.isDirectory) continue;
      if (entry.isSymbolicLink) {
        throw PackageExtractionException('symbolic links are not allowed: ${entry.name}');
      }
      if (!isSafeEntryPath(entry.name)) {
        throw PackageExtractionException('unsafe entry path: ${entry.name}');
      }
      final targetFile = File('${target.path}${Platform.pathSeparator}'
          '${entry.name.replaceAll('/', Platform.pathSeparator)}');
      await targetFile.parent.create(recursive: true);
      final bytes = entry.content;
      await targetFile.writeAsBytes(bytes, flush: true);
      files.add(entry.name);
      if (entry.name == 'manifest.json') {
        try {
          manifest = PackageManifest.fromJson(
            jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
          );
        } catch (error) {
          throw PackageExtractionException('manifest.json is not valid JSON: $error');
        }
      }
    }

    if (manifest == null) {
      throw PackageExtractionException('manifest.json is missing from the package');
    }
    return PackageExtractionResult(manifest: manifest, files: files);
  }
}
