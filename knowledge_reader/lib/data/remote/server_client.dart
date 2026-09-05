import 'dart:io';

import 'package:dio/dio.dart';

import '../../domain/model/catalog.dart';

class ServerConfig {
  const ServerConfig({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  String get normalizedBaseUrl {
    var value = baseUrl.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  bool get isConfigured => normalizedBaseUrl.isNotEmpty && token.isNotEmpty;

  Map<String, dynamic> toJson() => {'baseUrl': baseUrl, 'token': token};

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        baseUrl: (json['baseUrl'] ?? '') as String,
        token: (json['token'] ?? '') as String,
      );
}

class ServerException implements Exception {
  ServerException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ServerException(${statusCode ?? '-'}): $message';
}

class ServerHealth {
  const ServerHealth({required this.service, required this.version});

  final String service;
  final String version;
}

class CatalogFetchResult {
  const CatalogFetchResult({this.snapshot, this.etag});

  final CatalogSnapshot? snapshot;
  final String? etag;

  bool get notModified => snapshot == null;
}

class PackageFetchResult {
  const PackageFetchResult({required this.notModified, this.etag, this.file});

  final bool notModified;
  final String? etag;
  final File? file;
}

/// Thin typed wrapper over the server's reader API.
class ServerClient {
  ServerClient({required this.config, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              validateStatus: (status) => status != null && (status < 400 || status == 304),
            )) {
    _dio.options.baseUrl = config.normalizedBaseUrl;
    _dio.options.headers['authorization'] = 'Bearer ${config.token}';
  }

  final ServerConfig config;
  final Dio _dio;

  Future<ServerHealth> health() async {
    final response = await _get('/api/health');
    final data = _asMap(response.data);
    return ServerHealth(
      service: '${data['service'] ?? 'knowledge-ingest-server'}',
      version: '${data['version'] ?? 'unknown'}',
    );
  }

  /// Fetches the catalog snapshot; returns `notModified` for a 304 response.
  Future<CatalogFetchResult> fetchCatalog({String? etag}) async {
    final response = await _get(
      '/api/sync/catalog',
      options: Options(headers: _ifNoneMatch(etag)),
    );
    final responseEtag = _etagOf(response.headers);
    if (response.statusCode == 304) {
      return CatalogFetchResult(etag: responseEtag ?? etag);
    }
    final snapshot = CatalogSnapshot.fromJson(_asMap(response.data));
    if (snapshot.schemaVersion != 1) {
      throw ServerException('unsupported catalog schema ${snapshot.schemaVersion}');
    }
    return CatalogFetchResult(snapshot: snapshot, etag: responseEtag);
  }

  /// Downloads an offline package into [target].
  Future<PackageFetchResult> downloadPackage({
    required String itemId,
    required File target,
    String? etag,
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      await target.parent.create(recursive: true);
      final response = await _dio.download(
        '/api/items/${Uri.encodeComponent(itemId)}/package',
        target.path,
        options: Options(
          headers: _ifNoneMatch(etag),
          receiveTimeout: const Duration(minutes: 10),
        ),
        onReceiveProgress: onProgress,
      );
      if (response.statusCode == 304) {
        if (await target.exists()) await target.delete();
        return PackageFetchResult(notModified: true, etag: _etagOf(response.headers) ?? etag);
      }
      return PackageFetchResult(
        notModified: false,
        etag: _etagOf(response.headers),
        file: target,
      );
    } on DioException catch (error) {
      throw _toServerException(error);
    }
  }

  Future<Response<dynamic>> _get(String path, {Options? options}) async {
    try {
      return await _dio.get<dynamic>(path, options: options);
    } on DioException catch (error) {
      throw _toServerException(error);
    }
  }

  ServerException _toServerException(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    final message = data is Map && data['message'] is String
        ? data['message'] as String
        : error.message ?? error.type.name;
    return ServerException(message, statusCode: status);
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, item) => MapEntry('$key', item));
    return const {};
  }

  static String? _etagOf(Headers? headers) {
    final value = headers?.value('etag');
    if (value == null) return null;
    return value;
  }

  /// `If-None-Match` requires quoted entity tags; callers may pass a raw
  /// content hash (for example straight from the catalog snapshot).
  static Map<String, dynamic>? _ifNoneMatch(String? etag) {
    if (etag == null || etag.isEmpty) return null;
    final trimmed = etag.trim();
    final quoted = trimmed.startsWith('"') || trimmed.startsWith('W/"') ? trimmed : '"$trimmed"';
    return {'if-none-match': quoted};
  }
}
