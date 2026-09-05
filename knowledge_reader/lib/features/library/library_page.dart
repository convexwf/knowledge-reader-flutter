import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../data/local/library_store.dart';
import '../../data/remote/server_client.dart';
import '../../domain/model/catalog.dart';

/// How a catalog entry relates to what is stored on this device.
enum LocalContentState { notDownloaded, upToDate, needsUpdate }

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final library = ref.watch(libraryIndexProvider).value ?? const {};
    final progress = ref.watch(progressProvider).value ?? const {};
    final downloads = ref.watch(downloadProvider);

    // A fresh catalog may have removed local packages; refresh the local index
    // and tell the user instead of letting rows silently disappear.
    ref.listen(catalogProvider, (previous, next) {
      final state = next.value;
      if (state == null || state.prunedCount == 0) return;
      ref.read(libraryIndexProvider.notifier).refresh();
      ref.read(progressProvider.notifier).refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清理 ${state.prunedCount} 个服务端已删除的条目')),
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('知识库'),
        actions: [
          IconButton(
            tooltip: '同步目录',
            icon: const Icon(Icons.sync),
            onPressed: () => _sync(context, ref),
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
            onRefresh: () => _sync(context, ref),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                return _tile(
                  context,
                  ref,
                  item,
                  library[item.itemId],
                  progress[item.itemId],
                  downloads[item.itemId],
                );
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
    ReadingProgress? reading,
    DownloadState? download,
  ) {
    final state = _localState(item, local);
    final active = download?.isActive ?? false;
    final failed = download?.hasFailed ?? false;

    final meta = [
      item.sourceLabel,
      if (item.packageBytes != null) _formatBytes(item.packageBytes!),
      if (item.sectionCount != null) '${item.sectionCount} 节',
    ].join(' · ');

    final progressText = _progressText(reading);
    final installing = download?.phase == DownloadPhase.installing;

    return ListTile(
      isThreeLine: progressText != null || active || failed,
      title: Text(item.title.isEmpty ? item.itemId : item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Row(
            children: [
              _StateChip(state: state),
              const SizedBox(width: 6),
              Expanded(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: installing ? null : download?.progress, minHeight: 3),
            const SizedBox(height: 2),
            Text(
              installing ? '正在解压并校验…' : '下载中…点击右侧可取消',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (failed) ...[
            const SizedBox(height: 4),
            Text(
              download?.message ?? '下载失败',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
            ),
          ],
          if (progressText != null && !active) ...[
            const SizedBox(height: 4),
            Text(progressText, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
      trailing: _trailing(ref, item, state, download),
      onTap: () => _open(context, ref, item, state),
      onLongPress: () => _showActions(context, ref, item, local, state),
    );
  }

  /// Syncs the catalog, waits for the local reconciliation to finish and tells
  /// the user when server-side deletions removed local packages.
  Future<void> _sync(BuildContext context, WidgetRef ref) async {
    await ref.read(catalogProvider.notifier).sync();
    await ref.read(libraryIndexProvider.notifier).refresh();
    await ref.read(progressProvider.notifier).refresh();
  }

  Widget _trailing(WidgetRef ref, CatalogItem item, LocalContentState state, DownloadState? download) {
    if (download?.isActive ?? false) {
      return IconButton(
        tooltip: '取消下载',
        icon: const Icon(Icons.close),
        onPressed: () => ref.read(downloadProvider.notifier).cancel(item.itemId),
      );
    }
    if (download?.hasFailed ?? false) {
      return IconButton(
        tooltip: '下载失败，点击重试',
        icon: const Icon(Icons.refresh, color: Colors.redAccent),
        onPressed: () => ref.read(downloadProvider.notifier).download(item),
      );
    }
    switch (state) {
      case LocalContentState.upToDate:
        return const Tooltip(
          message: '已下载，可离线阅读',
          child: Icon(Icons.offline_pin, color: Colors.green),
        );
      case LocalContentState.needsUpdate:
        return IconButton(
          tooltip: '内容已更新，点击下载新版本',
          icon: const Icon(Icons.sync_problem, color: Colors.orange),
          onPressed: () => ref.read(downloadProvider.notifier).download(item),
        );
      case LocalContentState.notDownloaded:
        return IconButton(
          tooltip: '下载离线包',
          icon: const Icon(Icons.download_outlined),
          onPressed: () => ref.read(downloadProvider.notifier).download(item),
        );
    }
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    CatalogItem item,
    LocalContentState state,
  ) async {
    // Capture the router first: the list rebuilds while downloading, which
    // unmounts this row's context.
    final router = GoRouter.of(context);
    if (state == LocalContentState.upToDate) {
      router.push('/reader/${Uri.encodeComponent(item.itemId)}');
      return;
    }
    await ref.read(downloadProvider.notifier).download(item);
    final store = await ref.read(libraryStoreProvider.future);
    final installed = (await store.readLibrary())[item.itemId];
    if (installed == null) return; // 失败时行内已经显示原因
    router.push('/reader/${Uri.encodeComponent(item.itemId)}');
  }

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    CatalogItem item,
    LocalItemState? local,
    LocalContentState state,
  ) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('打开'),
              subtitle: state == LocalContentState.upToDate ? null : const Text('需要先下载离线包'),
              enabled: state == LocalContentState.upToDate,
              onTap: () {
                Navigator.of(sheetContext).pop();
                router.push('/reader/${Uri.encodeComponent(item.itemId)}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(local == null ? '下载离线包' : '重新下载'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                ref.read(downloadProvider.notifier).download(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除离线包'),
              enabled: local != null,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final store = await ref.read(libraryStoreProvider.future);
                await store.removeItem(item.itemId);
                ref.invalidate(libraryIndexProvider);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制链接'),
              enabled: item.sourceUrl != null,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Clipboard.setData(ClipboardData(text: item.sourceUrl!));
                messenger.showSnackBar(const SnackBar(content: Text('链接已复制')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('详情'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showDetails(context, item, local);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context, CatalogItem item, LocalItemState? local) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('条目详情'),
        content: SingleChildScrollView(
          child: Text([
            '标题：${item.title}',
            '来源：${item.sourceUrl ?? item.sourceType}',
            'itemId：${item.itemId}',
            'docId：${item.docId ?? '—'}',
            '服务端指纹：${item.contentHash ?? '—'}',
            '本地指纹：${local?.contentHash ?? '未下载'}',
            '包大小：${item.packageBytes == null ? '—' : _formatBytes(item.packageBytes!)}',
            '更新时间：${_formatDate(item.parsedAt ?? item.updatedAt)}',
          ].join('\n')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
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

LocalContentState _localState(CatalogItem item, LocalItemState? local) {
  if (local == null) return LocalContentState.notDownloaded;
  if (item.contentHash != null && local.contentHash != item.contentHash) {
    return LocalContentState.needsUpdate;
  }
  return LocalContentState.upToDate;
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final LocalContentState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      LocalContentState.upToDate => ('已下载', Colors.green),
      LocalContentState.needsUpdate => ('需更新', Colors.orange),
      LocalContentState.notDownloaded => ('未下载', Theme.of(context).colorScheme.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

String? _progressText(ReadingProgress? progress) {
  final fraction = progress?.fraction;
  if (fraction == null || fraction < 0.01) return null;
  final percent = (fraction * 100).clamp(1, 100).round();
  final when = progress == null ? '' : ' · ${_formatRelative(progress.updatedAt)}';
  return '读到 $percent%$when';
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    final megabytes = bytes / (1024 * 1024);
    final text = megabytes >= 10 || megabytes == megabytes.roundToDouble()
        ? megabytes.round().toString()
        : megabytes.toStringAsFixed(1);
    return '$text MB';
  }
  return '${(bytes / 1024).round()} KB';
}

String _formatRelative(DateTime value) {
  final diff = DateTime.now().toUtc().difference(value);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  return _formatDate(value);
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
