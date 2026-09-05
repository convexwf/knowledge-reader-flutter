/// Catalog snapshot served by `GET /api/sync/catalog`.
class CatalogSnapshot {
  const CatalogSnapshot({
    required this.schemaVersion,
    required this.serverTime,
    required this.items,
  });

  final int schemaVersion;
  final DateTime serverTime;
  final List<CatalogItem> items;

  factory CatalogSnapshot.fromJson(Map<String, dynamic> json) {
    return CatalogSnapshot(
      schemaVersion: (json['schemaVersion'] ?? 0) as int,
      serverTime: DateTime.tryParse('${json['serverTime'] ?? ''}') ?? DateTime.now().toUtc(),
      items: ((json['items'] ?? const []) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(CatalogItem.fromJson)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'serverTime': serverTime.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(growable: false),
      };
}

class CatalogItem {
  const CatalogItem({
    required this.itemId,
    required this.title,
    required this.sourceType,
    required this.state,
    required this.updatedAt,
    this.docId,
    this.parsedAt,
    this.contentHash,
    this.packageBytes,
    this.assetCount,
    this.sectionCount,
    this.sourceUrl,
  });

  final String itemId;
  final String title;
  final String sourceType;
  final String state;
  final DateTime updatedAt;
  final String? docId;
  final DateTime? parsedAt;
  final String? contentHash;
  final int? packageBytes;
  final int? assetCount;
  final int? sectionCount;
  final String? sourceUrl;

  factory CatalogItem.fromJson(Map<String, dynamic> json) {
    return CatalogItem(
      itemId: (json['itemId'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      sourceType: (json['sourceType'] ?? '') as String,
      state: (json['state'] ?? '') as String,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}')?.toUtc() ?? DateTime.now().toUtc(),
      docId: json['docId'] as String?,
      parsedAt: DateTime.tryParse('${json['parsedAt'] ?? ''}')?.toUtc(),
      contentHash: json['contentHash'] as String?,
      packageBytes: json['packageBytes'] as int?,
      assetCount: json['assetCount'] as int?,
      sectionCount: json['sectionCount'] as int?,
      sourceUrl: json['sourceUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'title': title,
        'sourceType': sourceType,
        'state': state,
        'updatedAt': updatedAt.toIso8601String(),
        if (docId != null) 'docId': docId,
        if (parsedAt != null) 'parsedAt': parsedAt!.toIso8601String(),
        if (contentHash != null) 'contentHash': contentHash,
        if (packageBytes != null) 'packageBytes': packageBytes,
        if (assetCount != null) 'assetCount': assetCount,
        if (sectionCount != null) 'sectionCount': sectionCount,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
      };

  bool get isParsed => state == 'parsed';

  /// Host shown in the library list; falls back to the source type for items
  /// without a URL (for example imported EPUB books).
  String get sourceLabel {
    final url = sourceUrl;
    if (url == null || url.isEmpty) return sourceType;
    return Uri.tryParse(url)?.host ?? sourceType;
  }
}

/// Offline package manifest written by the server (`manifest.json`).
class PackageManifest {
  const PackageManifest({
    required this.schemaVersion,
    required this.itemId,
    required this.docId,
    required this.contentHash,
    required this.title,
    required this.files,
  });

  final int schemaVersion;
  final String itemId;
  final String docId;
  final String contentHash;
  final String title;
  final List<PackageFileEntry> files;

  factory PackageManifest.fromJson(Map<String, dynamic> json) {
    return PackageManifest(
      schemaVersion: (json['schemaVersion'] ?? 0) as int,
      itemId: (json['itemId'] ?? '') as String,
      docId: (json['docId'] ?? '') as String,
      contentHash: (json['contentHash'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      files: ((json['files'] ?? const []) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(PackageFileEntry.fromJson)
          .toList(growable: false),
    );
  }
}

class PackageFileEntry {
  const PackageFileEntry({required this.path, required this.sha256, required this.size});

  final String path;
  final String sha256;
  final int size;

  factory PackageFileEntry.fromJson(Map<String, dynamic> json) {
    return PackageFileEntry(
      path: (json['path'] ?? '') as String,
      sha256: (json['sha256'] ?? '') as String,
      size: (json['size'] ?? 0) as int,
    );
  }
}
