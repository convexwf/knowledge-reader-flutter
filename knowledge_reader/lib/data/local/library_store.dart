import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/model/catalog.dart';
import '../../domain/rule/content_hash.dart';
import 'package_extractor.dart';

/// Per-item local state: which package version is active on disk.
class LocalItemState {
  const LocalItemState({
    required this.itemId,
    required this.docId,
    required this.contentHash,
    required this.installedAt,
    required this.contentBytes,
    required this.fileCount,
  });

  final String itemId;
  final String docId;
  final String contentHash;
  final DateTime installedAt;
  final int contentBytes;
  final int fileCount;

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'docId': docId,
        'contentHash': contentHash,
        'installedAt': installedAt.toIso8601String(),
        'contentBytes': contentBytes,
        'fileCount': fileCount,
      };

  factory LocalItemState.fromJson(Map<String, dynamic> json) {
    return LocalItemState(
      itemId: (json['itemId'] ?? '') as String,
      docId: (json['docId'] ?? '') as String,
      contentHash: (json['contentHash'] ?? '') as String,
      installedAt: DateTime.tryParse('${json['installedAt'] ?? ''}')?.toUtc() ?? DateTime.now().toUtc(),
      contentBytes: (json['contentBytes'] ?? 0) as int,
      fileCount: (json['fileCount'] ?? 0) as int,
    );
  }
}

class ReadingProgress {
  const ReadingProgress({
    required this.itemId,
    required this.sectionId,
    required this.offset,
    required this.updatedAt,
    this.sectionIndex,
    this.sectionCount,
  });

  final String itemId;
  final String? sectionId;
  final double offset;
  final DateTime updatedAt;
  final int? sectionIndex;
  final int? sectionCount;

  /// Rough completion ratio used by the library list.
  double? get fraction {
    final index = sectionIndex;
    final total = sectionCount;
    if (index == null || total == null || total <= 0) return null;
    return ((index + offset) / total).clamp(0, 1);
  }

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'sectionId': sectionId,
        'offset': offset,
        'updatedAt': updatedAt.toIso8601String(),
        if (sectionIndex != null) 'sectionIndex': sectionIndex,
        if (sectionCount != null) 'sectionCount': sectionCount,
      };

  factory ReadingProgress.fromJson(Map<String, dynamic> json) {
    return ReadingProgress(
      itemId: (json['itemId'] ?? '') as String,
      sectionId: json['sectionId'] as String?,
      offset: (json['offset'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}')?.toUtc() ?? DateTime.now().toUtc(),
      sectionIndex: json['sectionIndex'] as int?,
      sectionCount: json['sectionCount'] as int?,
    );
  }
}

/// File-system backed library implementing the layout in the design doc.
///
/// Every JSON state file is written through a temp file + rename so a killed
/// process can never leave a half-written index behind.
class LibraryStore {
  LibraryStore._(this.rootDirectory, this.cacheDirectory);

  final Directory rootDirectory;
  final Directory cacheDirectory;

  static Future<LibraryStore> open({
    Directory? rootOverride,
    Directory? cacheOverride,
  }) async {
    final root = rootOverride ?? Directory(p.join((await getApplicationSupportDirectory()).path, 'library'));
    final cache = cacheOverride ?? Directory(p.join((await getTemporaryDirectory()).path, 'library'));
    final store = LibraryStore._(root, cache);
    await store.ensureLayout();
    return store;
  }

  File get catalogFile => File(p.join(rootDirectory.path, 'catalog.json'));
  File get libraryFile => File(p.join(rootDirectory.path, 'library.json'));
  File get progressFile => File(p.join(rootDirectory.path, 'progress.json'));
  Directory get itemsDirectory => Directory(p.join(rootDirectory.path, 'items'));
  Directory get tempDirectory => Directory(p.join(cacheDirectory.path, 'tmp'));

  Future<void> ensureLayout() async {
    await rootDirectory.create(recursive: true);
    await itemsDirectory.create(recursive: true);
    await tempDirectory.create(recursive: true);
  }

  /// Removes leftovers from interrupted downloads or extractions.
  Future<void> cleanupTemp() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
    await tempDirectory.create(recursive: true);
    final staging = Directory(itemsDirectory.path);
    await for (final entity in staging.list()) {
      if (entity is Directory && p.basename(entity.path).startsWith('.staging-')) {
        await entity.delete(recursive: true);
      }
    }
  }

  Future<CatalogSnapshot?> readCatalog() async => _readJson(catalogFile, CatalogSnapshot.fromJson);

  Future<void> writeCatalog(CatalogSnapshot snapshot) => _writeJson(catalogFile, snapshot.toJson());

  Future<Map<String, LocalItemState>> readLibrary() async {
    final json = await _readJsonMap(libraryFile);
    return _stringMap(json?['items'])
        .map((key, value) => MapEntry(key, LocalItemState.fromJson(_stringMap(value))));
  }

  Future<void> _writeLibrary(Map<String, LocalItemState> items) => _writeJson(libraryFile, {
        'schemaVersion': 1,
        'items': items.map((key, value) => MapEntry(key, value.toJson())),
      });

  Future<Map<String, ReadingProgress>> readProgress() async {
    final json = await _readJsonMap(progressFile);
    return _stringMap(json?['items'])
        .map((key, value) => MapEntry(key, ReadingProgress.fromJson(_stringMap(value))));
  }

  Future<void> writeProgress(ReadingProgress progress) async {
    final all = await readProgress();
    all[progress.itemId] = progress;
    await _writeJson(progressFile, {
      'schemaVersion': 1,
      'items': all.map((key, value) => MapEntry(key, value.toJson())),
    });
  }

  /// Item ids contain `:` (for example `url:sha256:…`), which is not a legal
  /// path character on every platform. Encode anything outside the safe set so
  /// the mapping stays deterministic and reversible.
  static String encodePathSegment(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      if (RegExp(r'[A-Za-z0-9._-]').hasMatch(char)) {
        buffer.write(char);
        continue;
      }
      for (final byte in utf8.encode(char)) {
        buffer.write('%${byte.toRadixString(16).padLeft(2, '0')}');
      }
    }
    return buffer.toString();
  }

  Directory itemDirectory(String itemId) =>
      Directory(p.join(itemsDirectory.path, encodePathSegment(itemId)));

  Directory contentDirectory(String itemId, String contentHash) =>
      Directory(p.join(itemDirectory(itemId).path, contentHash));

  File documentFile(String itemId, String contentHash) =>
      File(p.join(contentDirectory(itemId, contentHash).path, 'document.json'));

  File markdownFile(String itemId, String contentHash) =>
      File(p.join(contentDirectory(itemId, contentHash).path, 'markdown.md'));

  File assetFile(String itemId, String contentHash, String assetId) =>
      File(p.join(contentDirectory(itemId, contentHash).path, 'assets', assetId));

  /// Downloads land here before verification.
  File tempArchive(String itemId) =>
      File(p.join(tempDirectory.path, '${encodePathSegment(itemId)}.package.zip'));

  /// Installs a downloaded package atomically and returns the new local state.
  ///
  /// Steps: extract to staging, verify every file hash, verify the package
  /// content hash, move the staging directory into place, then switch the
  /// pointer in `library.json`. A crash before the pointer switch leaves the
  /// previous version intact.
  Future<LocalItemState> installPackage({
    required String itemId,
    required File archiveFile,
  }) async {
    final itemRoot = itemDirectory(itemId);
    final staging = Directory(p.join(itemRoot.path, '.staging-${DateTime.now().microsecondsSinceEpoch}'));
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }

    try {
      final extracted = await PackageExtractor.extract(archive: archiveFile, target: staging);
      final manifest = extracted.manifest;
      if (manifest.itemId.isNotEmpty && manifest.itemId != itemId) {
        throw PackageExtractionException('manifest itemId ${manifest.itemId} does not match $itemId');
      }

      final files = <PackageFile>[];
      for (final entry in manifest.files) {
        final file = File(p.join(staging.path, entry.path.replaceAll('/', Platform.pathSeparator)));
        if (!await file.exists()) {
          throw PackageExtractionException('package is missing ${entry.path}');
        }
        final bytes = await file.readAsBytes();
        if (sha256Hex(bytes) != entry.sha256) {
          throw PackageExtractionException('hash mismatch for ${entry.path}');
        }
        files.add(PackageFile(path: entry.path, bytes: bytes));
      }

      final computed = packageContentHash(files);
      if (computed != manifest.contentHash) {
        throw PackageExtractionException('content hash mismatch: expected ${manifest.contentHash}');
      }

      final target = contentDirectory(itemId, manifest.contentHash);
      if (await target.exists()) {
        await target.delete(recursive: true);
      }
      await target.parent.create(recursive: true);
      await staging.rename(target.path);

      final state = LocalItemState(
        itemId: itemId,
        docId: manifest.docId,
        contentHash: manifest.contentHash,
        installedAt: DateTime.now().toUtc(),
        contentBytes: packageContentBytes(files),
        fileCount: files.length,
      );
      final library = await readLibrary();
      library[itemId] = state;
      await _writeLibrary(library);
      await _pruneVersions(itemId, manifest.contentHash);
      return state;
    } catch (_) {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      rethrow;
    } finally {
      if (await archiveFile.exists()) {
        await archiveFile.delete();
      }
    }
  }

  Future<void> removeItem(String itemId) async {
    final directory = itemDirectory(itemId);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    final library = await readLibrary();
    library.remove(itemId);
    await _writeLibrary(library);
  }

  Future<void> _pruneVersions(String itemId, String keepHash) async {
    final directory = itemDirectory(itemId);
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is! Directory) continue;
      if (p.basename(entity.path) == keepHash) continue;
      await entity.delete(recursive: true);
    }
  }

  Future<void> _writeJson(File file, Map<String, dynamic> value) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(value), flush: true);
    try {
      await temp.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) {
        await file.delete();
      }
      await temp.rename(file.path);
    }
  }

  Future<Map<String, dynamic>?> _readJsonMap(File file) async {
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<T?> _readJson<T>(File file, T Function(Map<String, dynamic>) decode) async {
    final json = await _readJsonMap(file);
    return json == null ? null : decode(json);
  }
}

/// Tolerant map conversion: literal `const {}` defaults have the runtime type
/// `_ConstMap<dynamic, dynamic>` and cannot be cast to `Map<String, dynamic>`.
Map<String, dynamic> _stringMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item));
  }
  return <String, dynamic>{};
}
