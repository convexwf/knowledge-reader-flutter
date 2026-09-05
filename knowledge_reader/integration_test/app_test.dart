import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:knowledge_reader/main.dart';

/// On-device end-to-end test: configures the server, syncs the catalog,
/// downloads an offline package and opens it in the reader.
///
/// The default base URL assumes `adb reverse tcp:18765 tcp:18765`, which maps
/// the device's loopback port to the host's knowledge-ingest-server. Override
/// with `--dart-define=SERVER_BASE_URL=https://your-server` when needed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const host = String.fromEnvironment('SERVER_BASE_URL', defaultValue: 'http://127.0.0.1:18765');
  const token = 'dev-token';
  final pageUrl = 'https://example.com/android-smoke-${DateTime.now().millisecondsSinceEpoch}';
  final dio = Dio(BaseOptions(
    baseUrl: host,
    headers: {'authorization': 'Bearer $token'},
    validateStatus: (status) => status != null && status < 400,
  ));

  testWidgets('configures server, syncs and opens a document', (tester) async {
    var serverReady = true;
    try {
      await dio.get<Map<String, dynamic>>('/api/health');
    } catch (_) {
      serverReady = false;
    }
    if (!serverReady) {
      markTestSkipped('knowledge-ingest-server is not reachable from the emulator');
      return;
    }

    // Arrange: a small parsed item so the download stays fast on the emulator.
    final saved = await dio.post<Map<String, dynamic>>('/api/ingest/save', data: {
      'inputMode': 'browser_html',
      'snapshot': {
        'pageUrl': pageUrl,
        'canonicalUrl': pageUrl,
        'pageTitle': 'Android Smoke Article',
        'title': 'Android Smoke Article',
        'html': _fixtureHtml,
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'meta': {'author': 'Emulator Writer'},
      },
    });
    final fixtureItemId = '${(saved.data?['status'] as Map?)?['itemId']}';

    try {
      await tester.pumpWidget(const ProviderScope(child: KnowledgeReaderApp()));
      await tester.pump(const Duration(seconds: 1));

      // Configure the server.
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await waitFor(tester, find.text('服务器'));

      await tester.enterText(find.byType(TextField).at(0), host);
      await tester.enterText(find.byType(TextField).at(1), token);
      await tester.tap(find.text('保存'));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('测试连接'));
      await waitFor(tester, find.textContaining('连接成功'), timeout: const Duration(seconds: 30));

      // Back to the library and sync the catalog.
      await tester.pageBack();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byIcon(Icons.sync));
      await waitFor(tester, find.text('Android Smoke Article'), timeout: const Duration(seconds: 60));

      // Open the item: the reader downloads the package and renders it.
      await tester.tap(find.text('Android Smoke Article').first);
      await waitFor(
        tester,
        richTextContaining('offline reader smoke fixture'),
        timeout: const Duration(seconds: 120),
      );

      expect(find.text('Android Smoke Article'), findsWidgets);
      expect(find.byIcon(Icons.list_alt), findsOneWidget);
    } finally {
      if (fixtureItemId.isNotEmpty) {
        await dio.delete<void>('/api/items/${Uri.encodeComponent(fixtureItemId)}?mode=purge');
      } else {
        await dio.delete<void>('/api/ingest', queryParameters: {'url': pageUrl, 'mode': 'purge'});
      }
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}

Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('timed out waiting for $finder');
}

/// The reader renders paragraphs with `Text.rich`, so plain `Text.data` finders
/// never match body content; this finder inspects rendered spans instead.
Finder richTextContaining(String needle) => find.byWidgetPredicate((widget) {
      if (widget is RichText) return widget.text.toPlainText().contains(needle);
      if (widget is Text) {
        final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
        return text.contains(needle);
      }
      return false;
    });

const _fixtureHtml = '''
<!doctype html>
<html lang="en">
  <head>
    <title>Android Smoke Article</title>
    <meta name="author" content="Emulator Writer">
  </head>
  <body>
    <article>
      <h1>Android Smoke Article</h1>
      <p>This paragraph proves the offline reader smoke fixture survives the full round trip from the Android client.</p>
      <p>A second paragraph keeps the parser above its minimum readable length so the fixture is saved as a parsed document.</p>
      <blockquote>Reader smoke fixture</blockquote>
      <ul><li>First point</li><li>Second point</li></ul>
    </article>
  </body>
</html>
''';
