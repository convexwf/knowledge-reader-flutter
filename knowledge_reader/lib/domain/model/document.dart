/// Domain models mirroring the server document schema.
///
/// Field names follow the wire format (snake_case) so the mapping layer stays
/// obvious; Dart-style names are used for members consumed by widgets.
class KnowledgeDocument {
  const KnowledgeDocument({
    required this.docId,
    required this.meta,
    required this.sections,
  });

  final String docId;
  final DocumentMeta meta;
  final List<DocumentSection> sections;

  factory KnowledgeDocument.fromJson(Map<String, dynamic> json) {
    return KnowledgeDocument(
      docId: (json['doc_id'] ?? '') as String,
      meta: DocumentMeta.fromJson(_stringMap(json['meta'])),
      sections: ((json['sections'] ?? const []) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(DocumentSection.fromJson)
          .toList(growable: false),
    );
  }

  String get title => meta.title;
}

class DocumentMeta {
  const DocumentMeta({
    required this.title,
    this.pageTitle,
    this.sourceUrl,
    this.authors = const [],
    this.language,
    this.sectionCount,
    this.assetCount,
  });

  final String title;
  final String? pageTitle;
  final String? sourceUrl;
  final List<String> authors;
  final String? language;
  final int? sectionCount;
  final int? assetCount;

  factory DocumentMeta.fromJson(Map<String, dynamic> json) {
    final source = _stringMap(json['source']);
    return DocumentMeta(
      title: (json['title'] ?? '') as String,
      pageTitle: json['page_title'] as String?,
      sourceUrl: source['url'] as String?,
      authors: ((json['authors'] ?? const []) as List<dynamic>).whereType<String>().toList(growable: false),
      language: json['language'] as String?,
      sectionCount: json['section_count'] as int?,
      assetCount: json['asset_count'] as int?,
    );
  }
}

/// Tolerant map conversion: `const {}` literals have the runtime type
/// `_ConstMap<dynamic, dynamic>` and cannot be cast to `Map<String, dynamic>`.
Map<String, dynamic> _stringMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item));
  }
  return <String, dynamic>{};
}

/// Section types defined by the server document contract.
class SectionType {
  static const heading = 'heading';
  static const paragraph = 'paragraph';
  static const blockquote = 'blockquote';
  static const list = 'list';
  static const table = 'table';
  static const code = 'code';
  static const figure = 'figure';
}

class DocumentSection {
  const DocumentSection({
    required this.type,
    this.sectionId,
    this.anchorId,
    this.level,
    this.content,
    this.language,
    this.items = const [],
    this.rows = const [],
    this.assets = const [],
  });

  final String type;
  final String? sectionId;
  final String? anchorId;
  final int? level;
  final String? content;
  final String? language;
  final List<SectionListItem> items;
  final List<List<String>> rows;
  final List<SectionAsset> assets;

  factory DocumentSection.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] ?? const []) as List<dynamic>;
    final rawRows = (json['rows'] ?? const []) as List<dynamic>;
    return DocumentSection(
      type: (json['type'] ?? SectionType.paragraph) as String,
      sectionId: json['section_id'] as String?,
      anchorId: json['anchor_id'] as String?,
      level: json['level'] as int?,
      content: json['content'] as String?,
      language: json['language'] as String?,
      items: rawItems.map(SectionListItem.fromJson).toList(growable: false),
      rows: rawRows
          .whereType<List<dynamic>>()
          .map((row) => row.map((cell) => '${cell ?? ''}').toList(growable: false))
          .toList(growable: false),
      assets: ((json['assets'] ?? const []) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(SectionAsset.fromJson)
          .toList(growable: false),
    );
  }
}

class SectionListItem {
  const SectionListItem({required this.text, this.children = const []});

  final String text;
  final List<SectionListItem> children;

  factory SectionListItem.fromJson(dynamic value) {
    if (value is String) {
      return SectionListItem(text: value);
    }
    if (value is Map<String, dynamic>) {
      return SectionListItem(
        text: (value['text'] ?? '') as String,
        children: ((value['items'] ?? const []) as List<dynamic>)
            .map(SectionListItem.fromJson)
            .toList(growable: false),
      );
    }
    return const SectionListItem(text: '');
  }
}

class SectionAsset {
  const SectionAsset({this.assetId, this.path, this.sourceUrl, this.alt, this.caption});

  final String? assetId;
  final String? path;
  final String? sourceUrl;
  final String? alt;
  final String? caption;

  factory SectionAsset.fromJson(Map<String, dynamic> json) {
    return SectionAsset(
      assetId: json['asset_id'] as String?,
      path: json['path'] as String?,
      sourceUrl: json['source_url'] as String?,
      alt: json['alt'] as String?,
      caption: json['caption'] as String?,
    );
  }

  /// Asset id derived from a `assets/<assetId>` reference when `asset_id` is missing.
  String? get resolvedAssetId {
    final direct = assetId;
    if (direct != null && direct.isNotEmpty) return direct;
    final reference = path ?? sourceUrl;
    if (reference == null) return null;
    final match = RegExp(r'(?:^|/)assets/([^/]+)$').firstMatch(reference);
    return match?.group(1);
  }
}
