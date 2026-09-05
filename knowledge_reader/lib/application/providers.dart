import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/theme.dart';
import '../data/local/library_store.dart';
import '../data/remote/server_client.dart';
import '../domain/model/catalog.dart';
import '../domain/model/document.dart';

const _configKey = 'server_config';
const _preferencesKey = 'reader_preferences';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

/// Shared, lazily created local library.
final libraryStoreProvider = FutureProvider<LibraryStore>((ref) async => LibraryStore.open());

class ServerConfigNotifier extends AsyncNotifier<ServerConfig> {
  /// Build-time defaults so debug builds can ship pre-configured, e.g.
  /// `flutter build apk --debug --dart-define=SERVER_BASE_URL=http://127.0.0.1:18765`.
  static const _defaultBaseUrl = String.fromEnvironment('SERVER_BASE_URL');
  static const _defaultToken = String.fromEnvironment('SERVER_TOKEN', defaultValue: 'dev-token');

  @override
  Future<ServerConfig> build() async {
    final storage = ref.read(secureStorageProvider);
    final raw = await storage.read(key: _configKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final stored = ServerConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (stored.isConfigured) return stored;
      } catch (_) {
        // Fall through to the build-time default.
      }
    }
    if (_defaultBaseUrl.isNotEmpty) {
      final fallback = ServerConfig(baseUrl: _defaultBaseUrl, token: _defaultToken);
      await storage.write(key: _configKey, value: jsonEncode(fallback.toJson()));
      return fallback;
    }
    return const ServerConfig(baseUrl: '', token: '');
  }

  Future<void> save(ServerConfig config) async {
    await ref.read(secureStorageProvider).write(key: _configKey, value: jsonEncode(config.toJson()));
    state = AsyncData(config);
    // The catalog watches the derived ServerClient, so the new configuration
    // propagates automatically; invalidating it here would create a cycle.
  }
}

final serverConfigProvider = AsyncNotifierProvider<ServerConfigNotifier, ServerConfig>(ServerConfigNotifier.new);

Provider<ServerClient?> serverClientProvider = Provider<ServerClient?>((ref) {
  final config = ref.watch(serverConfigProvider).value;
  if (config == null || !config.isConfigured) return null;
  return ServerClient(config: config);
});

/// Catalog snapshot plus the ETag needed for the next conditional request.
class CatalogState {
  const CatalogState({required this.snapshot, this.etag});

  final CatalogSnapshot snapshot;
  final String? etag;
}

class CatalogNotifier extends AsyncNotifier<CatalogState> {
  String? _etag;

  @override
  Future<CatalogState> build() async {
    final store = await ref.watch(libraryStoreProvider.future);
    final cached = await store.readCatalog();
    final client = ref.watch(serverClientProvider);
    if (client == null) {
      if (cached == null) throw ServerException('尚未配置服务器');
      return CatalogState(snapshot: cached);
    }
    try {
      final result = await client.fetchCatalog(etag: _etag);
      if (result.notModified && cached != null) {
        _etag = result.etag;
        return CatalogState(snapshot: cached, etag: result.etag);
      }
      final snapshot = result.snapshot ?? cached;
      if (snapshot == null) throw ServerException('服务器未返回目录');
      await store.writeCatalog(snapshot);
      _etag = result.etag;
      return CatalogState(snapshot: snapshot, etag: result.etag);
    } on ServerException {
      if (cached != null) return CatalogState(snapshot: cached);
      rethrow;
    }
  }

  Future<void> sync() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final catalogProvider = AsyncNotifierProvider<CatalogNotifier, CatalogState>(CatalogNotifier.new);

/// Local library contents (which packages are installed).
class LibraryIndexNotifier extends AsyncNotifier<Map<String, LocalItemState>> {
  @override
  Future<Map<String, LocalItemState>> build() async {
    final store = await ref.watch(libraryStoreProvider.future);
    return store.readLibrary();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final libraryIndexProvider =
    AsyncNotifierProvider<LibraryIndexNotifier, Map<String, LocalItemState>>(LibraryIndexNotifier.new);

class DownloadState {
  const DownloadState({this.received = 0, this.total = 0, this.error, this.done = false});

  final int received;
  final int total;
  final String? error;
  final bool done;

  double? get progress => total > 0 ? received / total : null;
}

class DownloadNotifier extends Notifier<Map<String, DownloadState>> {
  @override
  Map<String, DownloadState> build() => const {};

  Future<void> download(CatalogItem item) async {
    final client = ref.read(serverClientProvider);
    if (client == null) return;
    final store = await ref.read(libraryStoreProvider.future);
    _update(item.itemId, const DownloadState());
    try {
      final result = await client.downloadPackage(
        itemId: item.itemId,
        target: store.tempArchive(item.itemId),
        onProgress: (received, total) => _update(item.itemId, DownloadState(received: received, total: total)),
      );
      if (result.notModified) {
        _update(item.itemId, const DownloadState(done: true));
      } else if (result.file != null) {
        await store.installPackage(itemId: item.itemId, archiveFile: result.file!);
        _update(item.itemId, const DownloadState(done: true));
      }
      ref.invalidate(libraryIndexProvider);
    } catch (error) {
      _update(item.itemId, DownloadState(error: '$error'));
    }
  }

  void _update(String itemId, DownloadState state) {
    this.state = {...this.state, itemId: state};
  }
}

final downloadProvider = NotifierProvider<DownloadNotifier, Map<String, DownloadState>>(DownloadNotifier.new);

/// Reader state for the currently opened item.
class ReaderState {
  const ReaderState({
    required this.item,
    this.document,
    this.progress,
    this.offline = false,
    this.warning,
  });

  final CatalogItem item;
  final KnowledgeDocument? document;
  final ReadingProgress? progress;
  final bool offline;
  final String? warning;
}

class ReaderNotifier extends AsyncNotifier<ReaderState?> {
  @override
  Future<ReaderState?> build() async => null;

  Future<void> open(CatalogItem item) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(item));
  }

  Future<ReaderState> _load(CatalogItem item) async {
    final store = await ref.read(libraryStoreProvider.future);
    final library = await store.readLibrary();
    final local = library[item.itemId];

    if (local != null) {
      final file = store.documentFile(item.itemId, local.contentHash);
      if (await file.exists()) {
        final document = KnowledgeDocument.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
        final progress = (await store.readProgress())[item.itemId];
        return ReaderState(item: item, document: document, progress: progress, offline: true);
      }
    }

    final client = ref.read(serverClientProvider);
    if (client == null) {
      return ReaderState(item: item, warning: '文档未下载，且服务器未配置');
    }
    return ReaderState(item: item, warning: '文档未下载，请先在库中下载离线包');
  }

  Future<void> saveProgress(String sectionId, double offset) async {
    final current = state.value;
    if (current == null) return;
    final store = await ref.read(libraryStoreProvider.future);
    await store.writeProgress(ReadingProgress(
      itemId: current.item.itemId,
      sectionId: sectionId,
      offset: offset,
      updatedAt: DateTime.now().toUtc(),
    ));
  }
}

final readerProvider = AsyncNotifierProvider<ReaderNotifier, ReaderState?>(ReaderNotifier.new);

class PreferencesNotifier extends AsyncNotifier<ReaderPreferences> {
  @override
  Future<ReaderPreferences> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_preferencesKey);
    if (raw == null || raw.isEmpty) return const ReaderPreferences();
    try {
      return ReaderPreferences.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ReaderPreferences();
    }
  }

  Future<void> save(ReaderPreferences next) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferencesKey, jsonEncode(next.toJson()));
    state = AsyncData(next);
  }
}

final preferencesProvider =
    AsyncNotifierProvider<PreferencesNotifier, ReaderPreferences>(PreferencesNotifier.new);

/// Total bytes used by installed packages.
Future<int> libraryUsage(LibraryStore store, Map<String, LocalItemState> library) async {
  var total = 0;
  for (final state in library.values) {
    final directory = store.contentDirectory(state.itemId, state.contentHash);
    if (!await directory.exists()) continue;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
  }
  return total;
}
