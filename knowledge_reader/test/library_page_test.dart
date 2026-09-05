import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_reader/application/providers.dart';
import 'package:knowledge_reader/data/local/library_store.dart';
import 'package:knowledge_reader/domain/model/catalog.dart';
import 'package:knowledge_reader/features/library/library_page.dart';

void main() {
  final now = DateTime.utc(2026, 9, 13, 12);

  CatalogItem item({
    required String itemId,
    required String title,
    String sourceType = 'url',
    String? sourceUrl,
    String? contentHash,
    int? packageBytes,
    int? sectionCount,
  }) {
    return CatalogItem(
      itemId: itemId,
      title: title,
      sourceType: sourceType,
      state: 'parsed',
      updatedAt: now,
      docId: 'doc-$itemId',
      contentHash: contentHash,
      packageBytes: packageBytes,
      sectionCount: sectionCount,
      sourceUrl: sourceUrl,
    );
  }

  Future<void> pumpLibrary(
    WidgetTester tester, {
    required List<CatalogItem> items,
    Map<String, LocalItemState> library = const {},
    Map<String, ReadingProgress> progress = const {},
    Map<String, DownloadState> downloads = const {},
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProvider.overrideWith(() => _FakeCatalog(CatalogSnapshot(
                schemaVersion: 1,
                serverTime: now,
                items: items,
              ))),
          libraryIndexProvider.overrideWith(() => _FakeLibrary(library)),
          progressProvider.overrideWith(() => _FakeProgress(progress)),
          downloadProvider.overrideWith(() => _FakeDownloads(downloads)),
        ],
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows download state, source host, size and reading progress', (tester) async {
    await pumpLibrary(
      tester,
      items: [
        item(
          itemId: 'url:sha256:aaa',
          title: '已读完的文章',
          sourceUrl: 'https://example.com/post/1',
          contentHash: 'aaa',
          packageBytes: 2048,
          sectionCount: 10,
        ),
        item(
          itemId: 'epub:sha256:bbb',
          title: '需要更新的书',
          sourceType: 'epub',
          contentHash: 'bbb-new',
          packageBytes: 2097152,
          sectionCount: 4561,
        ),
        item(itemId: 'url:sha256:ccc', title: '还没下载的文章', contentHash: 'ccc'),
      ],
      library: {
        'url:sha256:aaa': LocalItemState(
          itemId: 'url:sha256:aaa',
          docId: 'doc-url:sha256:aaa',
          contentHash: 'aaa',
          installedAt: now,
          contentBytes: 2048,
          fileCount: 2,
        ),
        'epub:sha256:bbb': LocalItemState(
          itemId: 'epub:sha256:bbb',
          docId: 'doc-epub:sha256:bbb',
          contentHash: 'bbb-old',
          installedAt: now,
          contentBytes: 1400000,
          fileCount: 12,
        ),
      },
      progress: {
        'url:sha256:aaa': ReadingProgress(
          itemId: 'url:sha256:aaa',
          sectionId: 'section-5',
          offset: 0.5,
          updatedAt: now,
          sectionIndex: 4,
          sectionCount: 10,
        ),
      },
    );

    expect(find.text('已下载'), findsOneWidget);
    expect(find.text('需更新'), findsOneWidget);
    expect(find.text('未下载'), findsOneWidget);
    expect(find.textContaining('example.com'), findsOneWidget);
    expect(find.textContaining('epub'), findsWidgets);
    expect(find.textContaining('2 MB'), findsOneWidget);
    expect(find.textContaining('4561 节'), findsOneWidget);
    expect(find.textContaining('读到 45%'), findsOneWidget);
  });

  testWidgets('surfaces the download failure reason inline', (tester) async {
    await pumpLibrary(
      tester,
      items: [item(itemId: 'url:sha256:ddd', title: '下载失败的条目', contentHash: 'ddd')],
      downloads: {
        'url:sha256:ddd': const DownloadState(
          phase: DownloadPhase.failed,
          message: '无法连接到服务器',
        ),
      },
    );

    expect(find.text('无法连接到服务器'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });
}

class _FakeCatalog extends CatalogNotifier {
  _FakeCatalog(this.snapshot);

  final CatalogSnapshot snapshot;

  @override
  Future<CatalogState> build() async => CatalogState(snapshot: snapshot);
}

class _FakeLibrary extends LibraryIndexNotifier {
  _FakeLibrary(this.items);

  final Map<String, LocalItemState> items;

  @override
  Future<Map<String, LocalItemState>> build() async => items;
}

class _FakeProgress extends ProgressNotifier {
  _FakeProgress(this.items);

  final Map<String, ReadingProgress> items;

  @override
  Future<Map<String, ReadingProgress>> build() async => items;
}

class _FakeDownloads extends DownloadNotifier {
  _FakeDownloads(this.initial);

  final Map<String, DownloadState> initial;

  @override
  Map<String, DownloadState> build() => initial;
}
