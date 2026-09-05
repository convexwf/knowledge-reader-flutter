import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../data/local/library_store.dart';
import '../../data/remote/server_client.dart';
import '../../domain/model/catalog.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final library = ref.watch(libraryIndexProvider).value ?? const {};
    final downloads = ref.watch(downloadProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('知识库'),
        actions: [
          IconButton(
            tooltip: '同步目录',
            icon: const Icon(Icons.sync),
            onPressed: () => ref.read(catalogProvider.notifier).sync(),
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _message(context, ref, _friendlyError(error), isError: true),
        data: (state) {
          final items = state.snapshot.items;
          if (items.isEmpty) return _message(context, ref, '目录为空，先同步一次');
          return RefreshIndicator(
            onRefresh: () => ref.read(catalogProvider.notifier).sync(),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                return _tile(context, ref, item, library[item.itemId], downloads[item.itemId]);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    WidgetRef ref,
    CatalogItem item,
    LocalItemState? local,
    DownloadState? download,
  ) {
    final sizeLabel = item.packageBytes == null ? null : '${(item.packageBytes! / 1024).round()} KB';
    final subtitle = [
      item.sourceType,
      _formatDate(item.parsedAt ?? item.updatedAt),
      ?sizeLabel,
    ].where((value) => value.isNotEmpty).join(' · ');

    Widget trailing;
    if (download != null && !download.done && download.error == null) {
      trailing = SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(value: download.progress, strokeWidth: 2.5),
      );
    } else if (local != null && local.contentHash == item.contentHash) {
      trailing = const Icon(Icons.offline_pin, color: Colors.green);
    } else if (download?.error != null) {
      trailing = IconButton(
        tooltip: '下载失败，点击重试',
        icon: const Icon(Icons.error_outline, color: Colors.redAccent),
        onPressed: () => ref.read(downloadProvider.notifier).download(item),
      );
    } else {
      trailing = IconButton(
        tooltip: '下载离线包',
        icon: const Icon(Icons.download_outlined),
        onPressed: () => ref.read(downloadProvider.notifier).download(item),
      );
    }

    return ListTile(
      title: Text(item.title.isEmpty ? item.itemId : item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
      onTap: () async {
        // Capture the router before awaiting: the list rebuilds while the
        // download runs, which unmounts this tile's context.
        final router = GoRouter.of(context);
        final installed = local != null && local.contentHash == item.contentHash;
        if (!installed) {
          await ref.read(downloadProvider.notifier).download(item);
          // Read the authoritative store state: the provider refresh triggered
          // by the download is asynchronous and may still hold the old map.
          final store = await ref.read(libraryStoreProvider.future);
          final refreshed = (await store.readLibrary())[item.itemId];
          if (refreshed == null) return;
        }
        router.push('/reader/${Uri.encodeComponent(item.itemId)}');
      },
    );
  }

  Widget _message(BuildContext context, WidgetRef ref, String text, {bool isError = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: isError ? Colors.redAccent : null)),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => isError
                  ? context.push('/settings/server')
                  : ref.read(catalogProvider.notifier).sync(),
              child: Text(isError ? '配置服务器' : '同步目录'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number < 10 ? '0$number' : '$number';
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

/// Surfaces the server's own message instead of the raw exception string.
String _friendlyError(Object error) {
  if (error is ServerException) return error.message;
  return '$error';
}
